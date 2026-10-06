extends SceneTree
var errors: Array[String] = []
var checks := 0
class ControlHost extends Node:
	var inventory: Node
	var datapad: Node
	var combat_rig: Node

class NativeStub extends Node:
	var calls:Array=[]
	var design_ui:Node
	func image_eligible()->bool:return false
	func group_available()->bool:return false
	func request(action:String,detail:Dictionary={})->Dictionary:
		calls.append({"action":action,"detail":detail});return {}
	func reset()->void:calls.clear()

class GroundedFeedback extends "res://combat/player_feedback.gd":
	func physical() -> Dictionary:
		return {"posture":0,"eye_height":1.7,"grounded":true,"tracked":true}

class ControlBody extends CharacterBody3D:
	var combat_pools=preload("res://combat/ability_state.gd").new()
	var active := true
	var feedback: RefCounted
	func set_combat_capture(_hand: String, _prime: bool) -> void: pass

func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	checks+=1
	if not value: errors.append(message); push_error(message)
func pose(point: Vector3) -> Transform3D: return Transform3D(Basis.IDENTITY,point)
func check_performance_controls() -> void:
	var host := ControlHost.new(); root.add_child(host)
	var body := ControlBody.new(); host.add_child(body)
	var camera := Camera3D.new(); body.add_child(camera)
	body.feedback = GroundedFeedback.new()
	body.feedback.configure(body,camera)
	var performer := preload("res://entertainment/controller.gd").new()
	host.add_child(performer)
	performer.set_physics_process(false); performer.set_process(false)
	performer.native.free();performer.native=NativeStub.new();performer.add_child(performer.native)
	performer.host=host; performer.body=body; performer.head=camera
	performer.token="test-session"; performer.context={"entertainer":true}
	performer.active_performance={"id":"dance:basic:dance"}; performer.since_reply=0
	body.feedback.performer=performer
	performer.sample_menu(false,Vector2.ZERO,true,true)
	check(performer.native.calls.size()==1 and performer.native.calls[0].action=="flourish","A starts a flourish while performing")
	for frame in range(90): performer.sample_menu(false,Vector2.ZERO,true,true)
	check(performer.native.calls.size()==1,"Holding A does not repeat flourish requests")
	performer.sample_menu(false,Vector2.ZERO,false,true)
	performer.sample_menu(false,Vector2.ZERO,true,true)
	check(performer.native.calls.size()==2,"A release and fresh press requests another flourish")
	performer.native.calls.clear()
	check(body.feedback.request_jump().action=="jump" and performer.native.calls.is_empty(),"Jump during performance remains cosmetic jump, not flourish")
	body.feedback.motion.reset()
	body.feedback.receive_knockdown()
	body.feedback.motion.advance(0.5,0,1.7,true)
	check(body.feedback.request_jump().action=="recover" and performer.native.calls.is_empty(),"Jump still recovers from knockdown without requesting flourish")
	performer.sample_menu(false,Vector2.ZERO,false,true)
	performer.ui.open([{"id":"stop","label":"Stop","source_command":"stopmusic"}],Transform3D.IDENTITY)
	performer.sample_menu(false,Vector2.ZERO,true,true)
	check(performer.native.calls.is_empty(),"A cannot flourish through an open radial menu")
	performer.ui.close()
	performer.sample_menu(false,Vector2.ZERO,false,true)
	performer.sample_menu(false,Vector2.ZERO,true,false)
	performer.sample_menu(false,Vector2.ZERO,true,true)
	check(performer.native.calls.is_empty(),"Tracking recovery does not replay a held A press")
	performer.active_performance={}
	performer.selected={"id":"dance:basic:dance"}
	performer.sample_menu(false,Vector2.ZERO,false,true)
	performer.sample_menu(false,Vector2.ZERO,true,true)
	check(performer.primed and performer.native.calls.is_empty(),"Outside performance A still primes the selected ability")
	host.free()

func run() -> void:
	check_performance_controls()
	var gesture := SwgPerformanceGesture.new()
	var head := pose(Vector3(0,1.7,0))
	for kind in ["wind","percussion","strings","keyboard","dance"]:
		gesture.reset()
		var triggered := false
		for frame in range(270):
			var t := frame/90.0
			var main := Vector3(0.2,1.25,-0.4)
			var off := Vector3(-0.2,1.25,-0.4)
			match kind:
				"wind": main=Vector3(0,1.60,-0.14)
				"percussion": off=main+Vector3(0,0.28+0.15*cos(t*TAU*2),0)
				"strings": off=main+Vector3(-0.10,0.14*sin(t*TAU*2),0)
				"keyboard": main.y+=0.08*sin(t*TAU*2); off.y-=0.08*sin(t*TAU*2)
				"dance": main=Vector3(.5,1.25+.12*sin(t*TAU*1.5),-.4);off=Vector3(-.5,1.25-.12*sin(t*TAU*1.5),-.4)
			triggered = gesture.sample(1.0/90,kind,head,pose(main),pose(off),true,{"main_open":true,"off_open":true,"main_down":true,"off_down":true}) or triggered
		check(triggered,"Deliberate "+kind+" motion starts performance")
	for kind in ["percussion","strings","keyboard","dance"]:
		gesture.reset()
		var triggered := false
		for frame in range(180):
			var translation := Vector3(frame/180.0,0,0)
			triggered=gesture.sample(1.0/90,kind,pose(head.origin+translation),pose(Vector3(0.2,1.2,-0.4)+translation),pose(Vector3(-0.2,1.2,-0.4)+translation),true) or triggered
		check(not triggered,"Whole-player locomotion is not a "+kind+" gesture")
	gesture.reset()
	var jitter := false
	for frame in range(180):
		var y := sin(frame*0.7)*0.004
		jitter=gesture.sample(1.0/90,"keyboard",head,pose(Vector3(0.2,1.2+y,-0.4)),pose(Vector3(-0.2,1.2-y,-0.4)),true) or jitter
	check(not jitter,"Sub-centimetre piano jitter is rejected")
	check(not gesture.sample(0.5,"wind",head,pose(Vector3(0,1.6,-0.1)),Transform3D.IDENTITY,true),"Frame gaps cannot trigger an action")
	check(not gesture.sample(0.01,"wind",head,pose(Vector3(0,1.6,-0.1)),Transform3D.IDENTITY,false),"Tracking loss resets gesture")
	var hands := preload("res://entertainment/gestures.gd").new()
	var joins := 0
	for frame in range(180):
		if hands.join_sample(1.0/90,true,true,true,true): joins+=1
	check(joins==1,"Sustained double thumbs up joins once, not every frame")
	check(not hands.join_sample(0.1,false,true,true,true),"Outside circle cannot join")
	var assets := preload("res://entertainment/assets.gd").new()
	check(assets.load_catalog() and assets.catalog.performances.size()==154,"Original music and dance catalog loads")
	check(assets.catalog.failures.is_empty(),"All original performance clips, samples and icons exported")
	var context := {"complete":true,"commands":["startdance+basic","startdance+rhythmic","startmusic+starwars1","slitherhorn"]}
	check(assets.performances(context,{}).size()==2,"Empty hands expose exactly the novice's learned dances")
	check(assets.performances(context,{"template":"object/tangible/instrument/nalargon.iff"}).is_empty(),"Unlearned instrument has no songs")
	var menu := preload("res://combat/ability_hologram.gd").new()
	root.add_child(menu)
	var choices: Array = []
	for i in range(14): choices.append({"id":str(i),"label":"Song "+str(i),"source_command":"startmusic"})
	menu.open(choices,Transform3D.IDENTITY)
	check(menu.entries.size()==6,"Large performance menu is paginated")
	menu.sample_stick(Vector2.ZERO)
	var angle := TAU*5/6
	check(menu.sample_stick(Vector2(sin(angle),cos(angle))).is_empty() and menu.menu_open and menu.page==1,"More opens next radial page without selecting a song")
	menu.sample_stick(Vector2.ZERO)
	check(menu.sample_stick(Vector2(0,1))=="5","Next page selects the correct song")
	menu.free()
	var model_catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/assets/characters/catalog.json"))
	var world := Node3D.new(); root.add_child(world)
	var origin := XROrigin3D.new(); world.add_child(origin)
	var body := CharacterBody3D.new(); body.name="PlayerBody"; origin.add_child(body)
	var camera := XRCamera3D.new(); camera.name="XRCamera3D"; origin.add_child(camera)
	for side in ["LeftHand","RightHand"]:
		var hand := XRController3D.new(); hand.name=side; origin.add_child(hand)
	for race in model_catalog.races:
		var driver := preload("res://scripts/tracked_avatar.gd").new(); world.add_child(driver); driver.set_process(false)
		var avatar := preload("res://scripts/avatar.gd").new(); driver.add_child(avatar)
		check(avatar.configure(race,{"height":1.0,"profession":"social_entertainer"},[]).error=="" and driver.configure(avatar,origin),"Original entertainer rig "+race)
		driver.set_standing_eye_height(1.7)
		for clip in ["perform_dance_1","perform_dance_9","perform_dance_10_1","perform_music_3","perform_music_5_4"]:
			var left := pose(Vector3(-0.2,1.3,-0.4)); var right := pose(Vector3(0.2,1.3,-0.4))
			for frame in range(30): driver.update_tracking(1.0/90,head,left,right,0,{"grounded":true,"presentation":{"performance_clip":clip,"performance_time":0.6}})
			check(driver.last_report.motion.state==clip,"Source performance selected "+race+" "+clip)
			var skeleton: Skeleton3D = avatar.skeleton
			var eyes: Vector3=skeleton.global_transform*(skeleton.get_bone_global_pose(skeleton.find_bone("head"))*driver.eye_in_head)
			check(eyes.distance_to(head.origin)<0.001,"Performance never drives tracked eyes "+race+" "+clip)
			for prefix in ["l","r"]:
				for pair in [["arm","forearm"],["forearm","wrist"]]:
					var a := skeleton.find_bone(prefix+pair[0]); var b := skeleton.find_bone(prefix+pair[1])
					var length := skeleton.get_bone_global_rest(a).origin.distance_to(skeleton.get_bone_global_rest(b).origin)
					check(absf(skeleton.get_bone_global_pose(a).origin.distance_to(skeleton.get_bone_global_pose(b).origin)-length)<0.0001,"Performance preserves arm bone lengths")
			check(origin.transform==Transform3D.IDENTITY and camera.transform==Transform3D.IDENTITY and body.transform==Transform3D.IDENTITY,"Performance does not animate tracking or physics nodes")
		driver.free()
	world.free()
	var report := {"test":"entertainer_client","checks":checks,"passed":errors.is_empty(),"errors":errors,"mocked_tracking":true,"live_core3":false,"gpu_validation":false}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://../runtime/evidence/entertainment"))
	FileAccess.open("res://../runtime/evidence/entertainment/client.json",FileAccess.WRITE).store_string(JSON.stringify(report))
	print(JSON.stringify(report)); quit(0 if errors.is_empty() else 1)
