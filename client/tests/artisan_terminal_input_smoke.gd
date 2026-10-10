extends SceneTree
## Production discovery -> original screen transforms -> XR controller trigger -> UI.
## Original geometry and recorded native offers; mock tracking/network, no headset claim.
const Coordinator=preload("res://scripts/services_controller.gd")
const SceneWorld=preload("res://scripts/service_world.gd")
const Host=preload("res://tests/services_controller_smoke.gd").Host
const Stage=preload("res://tests/services_controller_smoke.gd").Stage
const UI=preload("res://scripts/xr_services.gd")
var failures:Array[String]=[]
var checks:=0
var trackers:Array=[]
var capture:=false
func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures.append(label);push_error(label)
func _initialize()->void:call_deferred("run")
func tracker(side:String)->XRControllerTracker:
	var value:=XRControllerTracker.new();value.name="/user/hand/"+side;value.type=XRServer.TRACKER_CONTROLLER;value.hand=XRPositionalTracker.TRACKER_HAND_LEFT if side=="left" else XRPositionalTracker.TRACKER_HAND_RIGHT
	XRServer.add_tracker(value);trackers.append(value);return value
func tracked(value:XRPositionalTracker,transform:Transform3D)->void:
	for name in ["grip","aim"]:value.set_pose(name,transform,Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH)
func frames()->void:
	for i in range(3):await process_frame
func run()->void:
	capture="--capture" in OS.get_cmdline_user_args()
	var host:=Host.new();root.add_child(host)
	host.xr_origin=XROrigin3D.new();host.add_child(host.xr_origin)
	var head:=XRCamera3D.new();head.name="XRCamera3D";host.xr_origin.add_child(head)
	var head_tracker:=XRPositionalTracker.new();head_tracker.name="head";head_tracker.type=XRServer.TRACKER_HEAD;XRServer.add_tracker(head_tracker);trackers.append(head_tracker)
	var left:=tracker("left");var right:=tracker("right")
	for side in ["LeftHand","RightHand"]:
		var controller:=XRController3D.new();controller.name=side;controller.tracker="/user/hand/left" if side=="LeftHand" else "/user/hand/right";controller.pose="grip";host.xr_origin.add_child(controller)
	host.player=CharacterBody3D.new();host.add_child(host.player)
	host.stage=Stage.new();host.add_child(host.stage);host.stage.current_cell={};host.stage.set_meta("manifest",{"origin":[3500,5,-4800]})
	var coordinator:=Coordinator.new();host.add_child(coordinator);coordinator.app=host;coordinator.epoch=host.datapad_epoch;coordinator.set_process(false)
	var scenery:=SceneWorld.new();host.add_child(scenery);scenery.configure(Vector3(3500,5,-4800));scenery.set_process(false);coordinator.scenery=scenery
	var original:Dictionary=scenery.static_records["6076130"].duplicate(true)
	coordinator.state={"character_id":"1000","terminals":[original]};coordinator.state_age=0
	var records:Array=coordinator.terminal_records()
	check(records.size()==1,"Real artisan source record resolves through production world/cell filtering")
	var record:Dictionary=records[0];var screen:Transform3D=record.ui_anchors[0]
	var physical:=screen.origin-screen.basis.z*.055
	var head_pose:=Transform3D(Basis.IDENTITY,physical+screen.basis.z*.8+Vector3.UP*.25)
	head_tracker.set_pose("default",head_pose,Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	head.global_transform=head_pose
	host.player.global_position=Vector3(head_pose.origin.x,record.position.y,head_pose.origin.z)
	tracked(left,Transform3D(Basis.IDENTITY,head_pose.origin+Vector3(-.3,-.4,0)))
	# Fingertip/controller aim exactly touches original glass; hologram is 55mm ahead.
	tracked(right,Transform3D(screen.basis,physical))
	var ui:=UI.new();host.add_child(ui);ui.configure(host.xr_origin,host.player);ui.set_process(false);ui.set_allowed(true);ui.terminal_provider=coordinator.terminal_records
	coordinator.ui=ui;coordinator.set_allowed(true);ui.action_requested.connect(coordinator.request)
	var evidence:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/evidence/core2/native-interactions.json"))
	var reply:Dictionary={}
	for response:Dictionary in evidence.responses:
		if response.path=="/services/open" and response.response.get("state",{}).get("terminal",{}).get("terminal_type","")=="artisan":reply=response.response.duplicate(true);break
	reply.character_id="1000";reply.state.character_id="1000";reply.erase("live_response");host.next_response=reply
	if capture:
		root.size=Vector2i(1280,900)
		var environment:=WorldEnvironment.new();var settings:=Environment.new();settings.background_mode=Environment.BG_COLOR;settings.background_color=Color("09131c");environment.environment=settings;host.add_child(environment)
		var source_mesh:Dictionary=scenery.screens[original.template][0]
		var data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../"+str(source_mesh.source_path)))
		var mesh:ArrayMesh=SwgMeshBuilder.new().create_mesh(data.surfaces)
		var loader:=preload("res://scripts/stage_loader.gd").new()
		for i in range(mesh.get_surface_count()):mesh.surface_set_material(i,loader.make_material(data.surfaces[i],ProjectSettings.globalize_path("res://../runtime/assets/tatooine_world")))
		var model:=MeshInstance3D.new();model.mesh=mesh;model.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;host.add_child(model);model.global_transform=Transform3D(scenery.terminal_basis(original),record.position)
		var camera:=Camera3D.new();host.add_child(camera);camera.global_position=physical+screen.basis.z*1.7+screen.basis.x*.65+Vector3.UP*.35;camera.look_at(record.position+Vector3.UP*.95);camera.make_current()
		var title:=Label.new();root.add_child(title);title.position=Vector2(24,24);title.text="ARTISAN TERMINAL · ORIGINAL SOURCE MESH\nProduction input path · recorded Core3 offers · mocked tracking · XR disabled";title.add_theme_font_size_override("font_size",22)
	await frames();right.set_input("trigger",0.0);await frames();ui._process(.016)
	check(not record.get("pick_geometry",{}).is_empty(),"Actual artisan casing geometry is available for mesh picking")
	if capture:
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../runtime/evidence/core2/artisan-touch-hover.png"))
	right.set_input("trigger",.9);await frames();ui._process(.016);await frames()
	check(host.calls.size()==1 and host.calls[0].path=="/services/open" and host.calls[0].payload.terminal_id=="6076130","Touching real artisan glass and pressing tracked trigger opens exactly its native terminal")
	check(not ui.terminal.is_empty() and not ui.pending and ui.panel.rows.size()>0,"Recorded native artisan offers populate the actual holographic panel after input")
	if not ui.terminal.is_empty():check(ui.surface.global_transform.is_equal_approx(screen),"Panel retains original source screen tilt and offset")
	ui._process(.016);await frames();check(host.calls.size()==1,"Held trigger cannot duplicate open request")
	if capture:
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../runtime/evidence/core2/artisan-touch-open.png"))
	check(ui.pointed_terminal(records,host.player.global_position,physical-screen.basis.z*.10,-screen.basis.z,head_pose.origin).get("id")=="6076130","Small tracked fingertip penetration preserves front-view touch")
	check(ui.pointed_terminal(records,host.player.global_position,physical-screen.basis.z*.30,screen.basis.z,head_pose.origin).get("id")=="6076130","Original terminal casing is interactive from an intersecting ray")
	check(ui.pointed_terminal(records,host.player.global_position,physical-screen.basis.z*.1,screen.basis.z,physical-screen.basis.z).get("id")=="6076130","Whole terminal activation is independent of the screen facing the viewer")
	ui.close_interface();ui.set_pending(false);right.set_input("trigger",0);tracked(right,Transform3D(screen.basis,physical+screen.basis.x*2.0));await frames();ui._process(.016)
	check(not ui.pointer_visual.visible,"Looking away removes pre-click feedback")
	for t in trackers:XRServer.remove_tracker(t)
	host.queue_free();await frames()
	print(JSON.stringify({"passed":failures.is_empty(),"checks":checks,"failures":failures,"tracking":"mocked XR positional trackers","network":"recorded native reply","renderer":"headless dummy" if DisplayServer.get_name()=="headless" else RenderingServer.get_current_rendering_method()}))
	call_deferred("quit",0 if failures.is_empty() else 1)
