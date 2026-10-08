extends SceneTree
const Gesture=preload("res://combat/chest_taunt.gd")
const Rig=preload("res://combat/ranged_rig.gd")
class Menu extends Node3D:
	var menu_open:=false
	func close()->void:menu_open=false
var checks:=0
var calls:Array=[]
var failures:Array=[]
func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures.append(label);push_error(label)
func hand(z:float,changes:Dictionary={})->Dictionary:
	var h:Dictionary={"position":Vector3(.15,-.45,z),"free":true,"tracked":true,"grip":1.0,"trigger":0.0}
	h.merge(changes,true);return h
func beat(g:RefCounted,side:="right",changes:Dictionary={})->String:
	var out:=""
	for z:float in [-.45,-.4,-.35,-.3,-.25,-.2]:
		var value:String=g.sample(.05,{side:hand(z,changes)},true)
		if not value.is_empty():out=value
	return out
func _initialize()->void:
	var g=Gesture.new()
	check(beat(g).is_empty() and g.capturing,"One tap arms without taunting")
	check(beat(g)=="right","Two deliberate taps trigger once on that hand")
	var repeated:=0
	for i in range(20):
		if not g.sample(.05,{"right":hand(-.2)},true).is_empty():repeated+=1
	check(repeated==0,"Holding fist at chest cannot retrigger")
	g=Gesture.new();beat(g,"left")
	check(beat(g,"right")=="right","Alternating fists also qualify")
	for changes:Dictionary in [{"grip":0.0},{"trigger":1.0},{"tracked":false},{"free":false},{"position":Vector3(.8,-.45,-.2)},{"position":Vector3(0,-.05,-.2)},{"position":Vector3.INF}]:
		g=Gesture.new()
		check(beat(g,"left",changes).is_empty() and beat(g,"left",changes).is_empty(),"Invalid/open/occupied/punching hand stays silent: "+str(changes))
	g=Gesture.new();beat(g);g.sample(.05,{},false)
	check(beat(g).is_empty(),"UI/focus/skill gate clears partial gesture")
	g=Gesture.new();beat(g);g.sample(.05,{"right":hand(-.2,{"tracked":false})},true)
	check(beat(g).is_empty(),"Hand tracking loss clears partial gesture")
	g=Gesture.new();beat(g);g.sample(.2,{"right":hand(-.45)},true)
	check(beat(g).is_empty(),"Tracking sample gap clears partial gesture")
	g=Gesture.new();beat(g)
	for i in range(30):g.sample(.05,{"right":hand(-.45)},true)
	check(beat(g).is_empty(),"Widely separated chest taps do not combine")
	g=Gesture.new()
	for z:float in [-.45,-.4,-.35,-.3,-.25,-.2]:
		check(g.sample(.05,{"left":hand(z),"right":hand(z)},true).is_empty(),"Simultaneous fists count as one beat")
	g=Gesture.new()
	for i in range(40):g.sample(.05,{"left":hand(-.2)},true)
	check(not g.capturing,"Static chest pose is not a beat")
	call_deferred("routing")
func rig_beat(rig:Node3D,side:String)->void:
	var controller:XRController3D=rig.origin.get_node(side.capitalize()+"Hand")
	for z:float in [-.45,-.4,-.35,-.3,-.25,-.2]:
		controller.position=Vector3(.15,1.25,z)
		rig.sample_chest_taunt(.05,true)
func routing()->void:
	var origin:=XROrigin3D.new();root.add_child(origin)
	origin.position=Vector3(20,0,30);origin.rotation.y=.8
	var head:=Camera3D.new();origin.add_child(head);head.position=Vector3(0,1.7,0)
	var trackers:Array=[]
	for side:String in ["left","right"]:
		var t:=XRControllerTracker.new();t.type=XRServer.TRACKER_CONTROLLER;t.name=side+"_hand"
		t.set_pose("grip",Transform3D.IDENTITY,Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH)
		t.set_input("grip",1.0);t.set_input("trigger",0.0);XRServer.add_tracker(t);trackers.append(t)
		var controller:=XRController3D.new();controller.name=side.capitalize()+"Hand";controller.tracker=t.name;controller.pose="grip";origin.add_child(controller)
	var rig:=Rig.new();root.add_child(rig);rig.set_process(false);rig.set_physics_process(false)
	rig.origin=origin;rig.head=head;rig.allowed=true;rig.ability_ui=Menu.new();rig.add_child(rig.ability_ui)
	rig.configure_taunt({"learned":true},func(pose:Transform3D,side:String)->bool:calls.append({"pose":pose,"hand":side});return true)
	await process_frame
	rig_beat(rig,"right");rig_beat(rig,"right")
	check(calls.size()==1 and calls[0].hand=="right" and calls[0].pose==head.global_transform,"Production routing uses tracked free hand and head reticle after world translation/yaw")
	check(rig.taunt_input_captured and rig.physical_guard.current.mode=="none","Chest gesture consumes combat input and drops guard")
	for mode:String in ["occupied","menu","unlearned","cooldown","held_weapon","head_tracking"]:
		rig.chest_taunt=Gesture.new();calls.clear();rig.offhand_occupied=false;rig.ability_ui.menu_open=false;rig.selected=-1;rig.taunt_context={"learned":true}
		if mode=="occupied":rig.offhand_occupied=true
		elif mode=="menu":rig.ability_ui.menu_open=true
		elif mode=="unlearned":rig.taunt_context.learned=false
		elif mode=="cooldown":rig.taunt_context.cooldown_remaining_seconds=2
		elif mode=="held_weapon":rig.selected=0
		var side:="left" if mode=="occupied" else "right"
		if mode=="head_tracking":
			rig_beat(rig,side);rig.sample_chest_taunt(.05,false);rig_beat(rig,side)
		else:rig_beat(rig,side);rig_beat(rig,side)
		check(calls.is_empty(),"Production gesture gate: "+mode)
	rig.free();origin.free()
	for t in trackers:XRServer.remove_tracker(t)
	var report:Dictionary={"test":"chest_taunt","checks":checks,"failures":failures,"mocked_tracking":true,"headset_tested":false}
	FileAccess.open("res://../runtime/evidence/chest-taunt-client.json",FileAccess.WRITE).store_string(JSON.stringify(report))
	print(JSON.stringify(report));quit(0 if failures.is_empty() else 1)
