extends SceneTree
const Avatar=preload("res://scripts/avatar.gd")
const Forearm=preload("res://scripts/forearm_mount.gd")
const Voice=preload("res://scripts/xr_voice_controls.gd")
const Ham=preload("res://combat/wrist_ham.gd")
const World=preload("res://scripts/service_world.gd")
const Services=preload("res://scripts/xr_services.gd")
const Map=preload("res://scripts/datapad_map.gd")
var checks:=0
var failures: Array[String]=[]
func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures.append(message);push_error(message)
func _initialize() -> void:call_deferred("run")
func settle() -> void:
	for i in range(4):await process_frame
func run() -> void:
	var world:=Node3D.new();root.add_child(world)
	var avatar:=Avatar.new();world.add_child(avatar)
	var loaded: Dictionary=avatar.configure("human_male");avatar.set_tracking_mode(true)
	check(loaded.get("error","")=="","Original SWG body loads for attachment regression")
	var skeleton: Skeleton3D=avatar.skeleton
	var rig:=XROrigin3D.new();world.add_child(rig)
	var voice:=Voice.new();world.add_child(voice);voice.configure(rig);voice.avatar=avatar;voice.set_process(false)
	voice.apply_state({"granted_channels":["proximity","planet"],"active_channel":"proximity","mic_mode":"muted","connected":true})
	voice.set_allowed(true);voice.update_tracking(true,true,true)
	var ham:=Ham.new();world.add_child(ham);ham.avatar=avatar;ham.pools=preload("res://combat/ability_state.gd").new()
	for side in ["left","right"]:
		var mount:=Forearm.new();var before: Transform3D=mount.resolve(skeleton,side,Transform3D.IDENTITY)
		var prefix:="l" if side=="left" else "r";var wrist:=skeleton.find_bone(prefix+"wrist")
		check(mount.bone>=0 and mount.bone!=wrist,"%s attachment resolves forearm ancestor"%side)
		var rest_wrist:=skeleton.get_bone_global_rest(wrist).origin
		var rest_arm:=skeleton.get_bone_global_rest(mount.bone)
		var length_axis: Vector3=(rest_arm.origin-rest_wrist).normalized()
		var restored_frame: Transform3D=rest_arm*mount.local_frame
		check(restored_frame.basis.x.dot(length_axis)*(-1 if side=="left" else 1)>.99,"%s panel horizontal edge follows wearer-readable lengthwise direction"%side)
		var rotation:=skeleton.get_bone_pose_rotation(wrist)
		var flex_basis:=Basis(restored_frame.basis.y,.8)*skeleton.get_bone_global_rest(wrist).basis
		var parent_basis:=skeleton.get_bone_global_pose(skeleton.get_bone_parent(wrist)).basis
		skeleton.set_bone_pose_rotation(wrist,(parent_basis.inverse()*flex_basis).get_rotation_quaternion());skeleton.force_update_all_bone_transforms()
		var after: Transform3D=mount.resolve(skeleton,side,Transform3D(Basis(Vector3.RIGHT,.9),Vector3(9,8,7)))
		check(before.is_equal_approx(after),"%s wrist flexion/controller movement cannot rotate or move forearm overlay"%side)
		var arm_pose: Transform3D=skeleton.global_transform*skeleton.get_bone_global_pose(mount.bone)
		var anchor: Vector3=(arm_pose*mount.local_frame).origin
		check(absf((after.origin-anchor).dot(after.basis.z)-.085)<.0001,"%s entire display clears forearm by 85mm"%side)
		voice.set_offhand(side);voice.global_transform=voice.underside_mount(Transform3D.IDENTITY)
		ham.side=side;ham.update_readout(Transform3D.IDENTITY,Vector3(2,2,2),true)
		check(voice.global_transform.is_equal_approx(ham.global_transform),"%s voice and HAM share identical bone-mounted frame"%side)
		skeleton.set_bone_pose_rotation(wrist,rotation);skeleton.force_update_all_bone_transforms()
	await settle()
	var pixel: Vector2=voice.panel.mode_buttons.vox.get_global_rect().get_center()
	voice.pointer_frame({"pixel":pixel},0)
	check(voice.cursor.visible and voice.cursor.position.z>0,"Finger target has visible cursor in front of panel")
	voice.pointer_frame({},0);check(not voice.cursor.visible,"Pointer leaving wrist hides cursor")
	voice.pointer_frame({"pixel":pixel},0);voice.update_tracking(false,true,true)
	check(not voice.cursor.visible and not voice.visible,"Tracking loss clears cursor and display")
	var scenery:=World.new();world.add_child(scenery);scenery.configure(Vector3.ZERO)
	var record: Dictionary={"id":"fixture","kind":"bank","template":"object/tangible/terminal/terminal_bank.iff","position":[0,0,0],"heading_radians":.7}
	var offsets: Array=scenery.screen_offsets(record)
	check(offsets.size()>=1 and offsets[0].origin.y>1.4,"Bank UI origin is derived from original screen mesh centroid")
	check(offsets[0].basis.z.y>.2 and offsets[0].basis.z.y<.4,"Bank screen original upward tilt preserved")
	var object_pose:=Transform3D(Basis(Vector3.UP,.7)*Basis(Vector3.RIGHT,.2),Vector3(3,1,4))
	var ui:=Services.new();world.add_child(ui)
	var anchors: Array=[]
	for offset: Transform3D in offsets:anchors.append(object_pose*offset)
	var head: Vector3=anchors[0].origin+anchors[0].basis.z*2
	var fixed: Transform3D=ui.terminal_pose({"ui_anchors":anchors},Vector3.ZERO,head)
	check(fixed.is_equal_approx(anchors[0]),"Terminal panel follows transformed original screen position and orientation")
	check(ui.terminal_pose({"ui_anchors":[anchors[0]]},Vector3.ZERO,head+Vector3(.7,.4,.2)).is_equal_approx(fixed),"Terminal panel does not billboard toward moving head")
	var map:=Map.new();root.add_child(map);map.size=Vector2(1100,650);map.load_service_references()
	var trainer_source:Dictionary=Avatar.read_json(ProjectSettings.globalize_path("res://../runtime/assets/services/trainers.json"))
	check(map.source_services.size()==scenery.catalog.static_terminals.size()+trainer_source.get("placements",[]).size(),"Map includes original global terminal/trainer placement references")
	var trainer_count:=map.source_services.filter(func(row):return row.type=="trainer").size()
	check(trainer_count>=50,"Original basic-profession trainers appear as navigation POIs")
	var original: Dictionary=map.source_services.filter(func(row):return row.type=="bank")[0]
	var total:=map.service_points.size()
	map.set_service_points([{"id":"live_bank","kind":"bank","name":"Live bank","position":original.position}])
	check(map.service_points.size()==total and map.service_points[0].name=="Live bank","Native discovery replaces matching source POI instead of duplicating it")
	map.set_filter("bank",false)
	check(not map.marker_visible(map.service_points[0]) and map.marker_visible({"type":"trainer"}),"Terminal and trainer filters operate independently")
	map.set_filter("trainer",false);check(not map.marker_visible({"type":"trainer"}) and map.marker_visible({"type":"waypoint"}),"Trainer filtering preserves personal waypoints")
	map.set_service_points([{"id":"barak","kind":"underworld","name":"Barak · Underworld broker","position":[3500,5,-4800]}])
	check(map.native_services.size()==1 and map.native_services[0].type=="mission" and map.native_services[0].service_kind=="underworld" and map.native_services[0].name=="Barak · Underworld broker","Native Underworld broker appears on map under existing mission category")
	map.set_filter("mission",false)
	check(not map.marker_visible(map.native_services[0]) and not map.marker_visible({"type":"underworld"}),"Mission filter hides both projected and direct broker markers")
	map.set_filter("mission",true)
	check(map.marker_visible(map.native_services[0]),"Mission filter restores broker navigation without adding a new filter")
	scenery.apply_snapshot({"terminals":[{"id":"barak","kind":"underworld","template":"object/tangible/terminal/terminal_bank.iff","position":[0,0,0]}]},Vector3.ZERO)
	check(not scenery.terminals.has("barak"),"Broker NPC cannot spawn a duplicate machine terminal even when a terminal mesh is available")
	map.set_service_points([]);check(map.native_services.is_empty() and map.service_points.size()==total,"Account reset clears native discoveries but retains source navigation references")
	var datapad:=preload("res://scripts/datapad_ui.gd").new();root.add_child(datapad);datapad.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT);datapad.size=Vector2(1100,760)
	datapad.show_map(true)
	check(datapad.map_filters.visible and datapad.filter_buttons.size()==8,"Datapad exposes readable map category filter controls")
	datapad.filter_buttons.trainer.set_pressed_no_signal(false);datapad.filter_buttons.trainer.toggled.emit(false)
	check(not datapad.map.filters.trainer,"Datapad trainer toggle drives map filter")
	datapad.show_map(false);check(not datapad.map_filters.visible,"Map filters are hidden on entry list")
	datapad.queue_free();map.queue_free();world.queue_free();await settle()
	print(JSON.stringify({"passed":failures.is_empty(),"checks":checks,"failures":failures,"original_assets":true,"xr":"off; mocked tracking","server_requests":0}))
	quit(0 if failures.is_empty() else 1)
