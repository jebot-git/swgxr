extends SceneTree
class Session extends Node:
	var live:=true
	var session_id:="owned"
class Stage extends Node3D:
	var current_cell:Dictionary={}
class Host extends Node:
	var live_combat:Node
	var gameplay_session:Node
	var multiplayer_sync:Node
	var ambient_npcs:Node
	var stage:Stage
	var player:Node3D
	var loader=preload("res://scripts/stage_loader.gd").new()
	var datapad_account:="fixture"
	var datapad_character_id:="101"
	var session_leaving:=false
	var world_ready:=true
	var loading_stage:=false
	var live_combat_reserved:=false
	var xr_requested:=false
	var xr_focused:=false
	var response:Dictionary={}
	var calls:Array=[]
	func source_position_at(p:Vector3)->Vector3:
		var origin:Vector3=loader.vec(loader.report.get("origin",[0,0,0]))
		var local:Vector3=stage.to_local(p)
		return origin+Vector3(local.x,local.y,-local.z)
	func api(_method:HTTPClient.Method,path:String,payload:Dictionary)->Dictionary:
		calls.append({"path":path,"payload":payload.duplicate(true)})
		await get_tree().process_frame
		var result:=response.duplicate(true);result.sequence=payload.sequence
		return result
var checks:=0
var errors:Array=[]
func check(value:bool,message:String)->void:
	checks+=1
	if not value:errors.append(message);push_error(message)
func _initialize()->void:
	create_timer(20).timeout.connect(func():quit(2))
	call_deferred("run")
func run()->void:
	var app:=Host.new();root.add_child(app)
	app.loader.report.origin=[100,0,200]
	app.stage=Stage.new();app.add_child(app.stage)
	app.player=Node3D.new();app.add_child(app.player)
	app.gameplay_session=Session.new();app.add_child(app.gameplay_session)
	app.response={"ok":true,"backend":"core3","source_kind":"core3_multiplayer_sync","character_id":"101","session_id":"owned","world_revision":1,"world":{"source_kind":"core3_world","full":true,"players":[{"id":"102","position":[102,0,200],"heading_radians":.5,"appearance":{},"posture":0}],"actors":[]},"poses":[]}
	var sync:=preload("res://multiplayer/client_sync.gd").new();app.multiplayer_sync=sync;app.add_child(sync);sync.setup(app);sync.set_process(false)
	sync.owner_character="101";sync.owner_session="owned"
	await sync.poll()
	check(app.calls.size()==1 and app.calls[0].path=="/session/sync","Normal persistent character polls cheap shared channel")
	check(app.calls[0].payload.position==[100.0,0.0,200.0] and app.calls[0].payload.tracking.is_empty(),"Desktop body pose uses original source coordinates and no invented XR tracking")
	var deadline:=Time.get_ticks_msec()+1500
	while not sync.players.peers.has("102") and Time.get_ticks_msec()<deadline:await process_frame
	check(sync.players.peers.has("102") and sync.players.peers["102"].global_position==Vector3(2,0,0),"Authenticated native peer enters actual scene at converted world point")
	var peer:Node=sync.players.peers["102"]
	check(is_equal_approx(peer.global_rotation.y,-.5),"Source yaw becomes correct Godot rendering orientation")
	app.loader.report.origin=[3528,5,-4800]
	app.stage.transform=Transform3D(Basis(Vector3.UP,.7),Vector3(13,2,-8))
	var source:Array=[3530,6,-4803]
	var expected:Vector3=app.stage.to_global(Vector3(2,1,3))
	check(sync.world(source).is_equal_approx(expected),"Production StageLoader report converts nonzero terrain origin, elevation and rotated stage")
	check(app.source_position_at(sync.world(source)).is_equal_approx(Vector3(3530,6,-4803)),"Native world position round trips the real loader report without invented loader properties")
	app.stage.transform=Transform3D.IDENTITY;app.loader.report.origin=[100,0,200]
	app.response.world=null
	await sync.poll()
	check(app.calls.back().payload.world_revision==1 and sync.players.peers.size()==1,"Subsequent request advertises accepted native revision for delta transport")
	sync.busy=true;sync._process(.5)
	check(app.calls.size()==2,"Only one presentation request may be in flight")
	sync.busy=false;sync.poll();var previous_sequence:int=sync.request_sequence;sync.reset()
	check(sync.request_sequence==previous_sequence and sync.request_sequence<9007199254740992,"Scene reset preserves strictly increasing safe JSON presentation sequence")
	await process_frame;await process_frame
	check(sync.state.sequence==-1 and sync.players.peers.is_empty() and sync.owner_session.is_empty(),"Late response after reset cannot resurrect logged-off character or peers")
	sync.owner_session="owned";sync.owner_character="101";app.response.world={"source_kind":"core3_world","full":true,"players":[],"actors":[]}
	await sync.poll()
	app.session_leaving=true;sync._process(.1)
	check(sync.owner_session.is_empty() and sync.state.sequence==-1,"Logoff stops sync and clears ownership before native closure")
	app.session_leaving=false;app.world_ready=false;sync._process(1)
	check(app.calls.size()==4,"Loading or offline stage never publishes character poses")
	app.loading_stage=true
	check(await sync.prime(),"Initial native snapshot can prime original scene presentation behind loading cover")
	sync._process(.1)
	check(sync.owner_session=="owned" and sync.priming,"Loading frames cannot erase the ownership being primed")
	app.world_ready=true;app.loading_stage=false;sync._process(0)
	check(not sync.priming and sync.owner_session=="owned","Entering world resumes periodic sync without another session or rebuild")
	app.free();await process_frame
	print(JSON.stringify({"checks":checks,"errors":errors,"mocked":true,"live_xr":false}));quit(0 if errors.is_empty() else 1)
