extends SceneTree
const Foveation=preload("res://graphics/foveation.gd")
const GazeVRS=preload("res://graphics/gaze_vrs.gd")
class Runtime extends RefCounted:
	var ready:=true
	var native:=false
	var gaze:=false
	var profile_writes:=0
	var foveation_dynamic:=true:
		set(value):foveation_dynamic=value;profile_writes+=1
	var foveation_level:=2:
		set(value):foveation_level=value;profile_writes+=1
	var vrs_min_radius:=20.0
	var vrs_strength:=1.0
	func is_initialized() -> bool:return ready
	func is_foveation_supported() -> bool:return native
	func is_eye_gaze_interaction_supported() -> bool:return gaze
	func get_view_count() -> int:return 2
	func get_transform_for_view(eye:int,origin:Transform3D)->Transform3D:
		return origin*Transform3D(Basis.IDENTITY,Vector3(-.032 if eye==0 else .032,0,0))
	func get_projection_for_view(_eye:int,ratio:float,near:float,far:float)->Projection:
		return Projection.create_perspective(90,ratio,near,far)
var failures: Array=[]
var checks:=0
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:print("FAIL ",label)
	if not ok:failures.append(label)
func _initialize() -> void:run.call_deferred()
func run() -> void:
	var projection:=Projection.create_perspective(90,1.0,.05,100)
	var gaze_pose:=Transform3D.IDENTITY
	check(GazeVRS.project_gaze(Transform3D.IDENTITY,projection,gaze_pose).is_equal_approx(Vector2.ZERO),"Forward -Z gaze projects to the center")
	gaze_pose.basis=Basis(Vector3.UP,-.25)
	check(GazeVRS.project_gaze(Transform3D.IDENTITY,projection,gaze_pose).x>0,"Looking right moves the fovea right")
	gaze_pose.basis=Basis(Vector3.RIGHT,.25)
	check(GazeVRS.project_gaze(Transform3D.IDENTITY,projection,gaze_pose).y>0,"Looking up moves the fovea up")
	gaze_pose.basis=Basis(Vector3.UP,PI)
	check(not GazeVRS.project_gaze(Transform3D.IDENTITY,projection,gaze_pose).is_finite(),"A ray behind the view cannot produce a valid mask")
	gaze_pose=Transform3D.IDENTITY
	var left_eye:=Transform3D(Basis.IDENTITY,Vector3(-.032,0,0))
	var right_eye:=Transform3D(Basis.IDENTITY,Vector3(.032,0,0))
	check(GazeVRS.project_gaze(left_eye,projection,gaze_pose).x>0 and GazeVRS.project_gaze(right_eye,projection,gaze_pose).x<0,"Each eye receives its own projected gaze center")
	var world:=Transform3D(Basis.from_euler(Vector3(.3,.7,.2)),Vector3(10,2,-8))
	check(GazeVRS.project_gaze(world*left_eye,projection,world*gaze_pose).is_equal_approx(GazeVRS.project_gaze(left_eye,projection,gaze_pose)),"World translation and rotation preserve relative gaze projection")
	var mask:=GazeVRS.new();var sharp_counts: Array[int]=[]
	for size in [1,2,3]:
		mask.build(size,1.0);var sharp:=0
		for y in 128:
			for x in 128:
				var rate:=mask.kernel.get_pixel(x+64,y+64).r
				if rate<.1:sharp+=1
		check(mask.kernel.get_pixel(128,128).r==0 and is_equal_approx(mask.kernel.get_pixel(64,64).r,128.0/255),"Mask has a full-rate center and a 2x2 peripheral limit: "+str(size))
		sharp_counts.append(sharp)
	check(sharp_counts[0]<sharp_counts[1] and sharp_counts[1]<sharp_counts[2],"Every fovea-size setting increases the actual sharp area")
	check(mask.texture.get_layers()==2,"Persistent VRS texture contains separate left/right layers")
	var viewport:=SubViewport.new();root.add_child(viewport)
	var xr:=Runtime.new()
	for native in [false,true]:
		xr.native=native
		for gaze in [false,true]:
			xr.gaze=gaze
			for level in [1,2,3,0,2]:
				var before:=xr.profile_writes
				var state:=Foveation.apply(viewport,xr,level)
				check(viewport.vrs_mode==(Viewport.VRS_DISABLED if level==0 else Viewport.VRS_XR),"Toggle actually changes viewport shading: "+str([native,gaze,level]))
				check(state.views==2 and state.gaze_supported==gaze and state.runtime_profile==native,"Reports stereo and runtime capabilities without claiming quad views")
				if native:check((xr.foveation_level==level if level>0 else xr.foveation_level>0) and not xr.foveation_dynamic,"Native preset is stable; Off preserves density-map allocation for later enabling")
				else:check(xr.profile_writes==before,"Generic VRS does not call unsupported runtime profile setters")
				before=xr.profile_writes;Foveation.apply(viewport,xr,level)
				check(xr.profile_writes==before,"Unrelated settings do not recreate the native foveation profile")
				if not native and not gaze and level>0:check(Foveation.description(xr,level).begins_with("Static foveation"),"No-eye headset identifies the static path")
	xr.ready=false;Foveation.apply(viewport,xr,3)
	check(viewport.vrs_mode==Viewport.VRS_DISABLED,"Inactive runtime returns to full-rate shading")
	Foveation.apply(viewport,null,2)
	check(viewport.vrs_mode==Viewport.VRS_DISABLED,"Desktop/headless works without an OpenXR runtime")
	xr.ready=true;xr.native=true;xr.foveation_level=2
	Foveation.apply(viewport,xr,0)
	check(xr.foveation_level==2 and viewport.vrs_mode==Viewport.VRS_DISABLED,"Starting Off keeps native swapchains foveation-capable with full-rate viewport shading")
	Foveation.apply(viewport,xr,1)
	check(xr.foveation_level==1 and viewport.vrs_mode==Viewport.VRS_XR,"Enabling after starting Off selects the requested native profile")
	xr.ready=true;xr.gaze=false;Foveation.apply(viewport,xr,99)
	var high_radius:=xr.vrs_min_radius;var high_strength:=xr.vrs_strength
	Foveation.apply(viewport,xr,1)
	check(xr.vrs_min_radius>high_radius and xr.vrs_strength<high_strength,"Low preserves more central detail than High")
	Foveation.apply(viewport,xr,-5)
	check(viewport.vrs_mode==Viewport.VRS_DISABLED,"Out-of-range direct requests are bounded")
	# Explicit size is independent of the remembered no-eye strength.
	xr.gaze=true;xr.native=false
	var last_radius:=0.0
	for size in [1,2,3]:
		var state:=Foveation.apply(viewport,xr,0,size)
		check(state.mode=="gaze" and viewport.vrs_mode==Viewport.VRS_XR,"Gaze size enables VRS even with static strength saved Off")
		check(xr.vrs_min_radius>last_radius and xr.vrs_strength==1.0,"Larger fovea expands full-quality radius without changing peripheral strength")
		last_radius=xr.vrs_min_radius
	Foveation.apply(viewport,xr,3,0)
	check(viewport.vrs_mode==Viewport.VRS_DISABLED,"Gaze Off overrides remembered static High")
	xr.native=true
	for size in [3,2,1]:
		Foveation.apply(viewport,xr,0,size)
		check(xr.foveation_level==4-size and not xr.foveation_dynamic,"Native size maps Large to Low, Small to High: "+str(size))
	Foveation.apply(viewport,xr,3,0)
	check(viewport.vrs_mode==Viewport.VRS_DISABLED and xr.foveation_level>0,"Gaze Off retains native allocation for later enabling")
	check(Foveation.description(xr,0,3).contains("presets"),"Native size explains coarse runtime-controlled regions")
	xr.gaze=false;var static_state:=Foveation.apply(viewport,xr,1,0)
	check(static_state.mode=="static" and viewport.vrs_mode==Viewport.VRS_XR and xr.foveation_level==1,"Losing gaze capability restores the independent static choice")
	xr.gaze=true;Foveation.apply(viewport,xr,1,0)
	check(viewport.vrs_mode==Viewport.VRS_DISABLED,"Restoring gaze capability restores its own saved Off setting")
	xr.ready=false;Foveation.apply(viewport,xr,3,3)
	check(Foveation.mode(xr)=="inactive" and viewport.vrs_mode==Viewport.VRS_DISABLED,"Disconnected runtime cannot expose active gaze foveation")
	mask.build(2,1.0)
	mask.update_mask(xr,Transform3D.IDENTITY,Transform3D.IDENTITY,true,1.0)
	var uploads:int=mask.update_count
	mask.update_mask(xr,Transform3D.IDENTITY,Transform3D.IDENTITY,true,1.0)
	check(mask.update_count==uploads,"Stationary gaze does not upload new masks")
	mask.update_mask(xr,Transform3D.IDENTITY,Transform3D.IDENTITY,false,1.0)
	for eye in 2:
		check(mask.images[eye].get_pixel(0,0).r==0 and mask.images[eye].get_pixel(64,64).r==0,"Tracking/focus loss restores full rate in each eye")
	mask.update_mask(xr,Transform3D.IDENTITY,Transform3D.IDENTITY,true,1.0)
	check(mask.images[0].get_pixel(0,0).r>0 and mask.gaze_valid,"Valid gaze restores peripheral shading after loss")
	mask.update_mask(xr,Transform3D.IDENTITY,Transform3D(Basis(Vector3.UP,PI),Vector3.ZERO),true,1.0)
	check(not mask.gaze_valid and mask.images[1].get_pixel(0,0).r==0,"Invalid projection restores full rate rather than shading at a stale center")
	check(not mask.supported(xr),"Headless dummy renderer cannot claim GPU VRS support")
	var map=load("res://openxr_action_map.tres") as OpenXRActionMap
	var eye_action:OpenXRAction
	for action:OpenXRAction in map.action_sets[0].actions:
		if action.resource_name=="eye_gaze_pose":eye_action=action
	check(eye_action!=null and eye_action.action_type==OpenXRAction.OPENXR_ACTION_POSE,"Eye-gaze pose is present in the actual action map")
	var binding_found:=false
	for profile:OpenXRInteractionProfile in map.interaction_profiles:
		if profile.interaction_profile_path=="/interaction_profiles/ext/eye_gaze_interaction":
			binding_found=profile.bindings[0].action==eye_action and profile.bindings[0].binding_path=="/user/eyes_ext/input/gaze_ext/pose"
	check(binding_found,"Eye-gaze action binds the standard OpenXR gaze path")
	var rig:=XROrigin3D.new();viewport.add_child(rig)
	var controller=preload("res://graphics/xr_foveation.gd").new();root.add_child(controller)
	var preferences=preload("res://graphics/preferences.gd").new();preferences.foveation_level=3;preferences.fovea_size=2
	controller.configure(viewport,rig,preferences);controller._process(0.5)
	check(controller.state.mode=="inactive" and viewport.vrs_mode==Viewport.VRS_DISABLED,"Real controller safely stays inactive with --xr-mode off")
	controller.free()
	viewport.free()
	print(JSON.stringify({"test":"xr_foveation","checks":checks,"passed":failures.is_empty(),"failures":failures,"renderer":"dummy","hardware_tested":false}))
	quit(0 if failures.is_empty() else 1)
