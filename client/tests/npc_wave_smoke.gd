extends SceneTree
const Wave=preload("res://scripts/npc_wave_gesture.gd")
var checks:=0
var failures:Array=[]
var head:=Transform3D(Basis.IDENTITY,Vector3(0,1.7,0))
var npc:Dictionary={"id":"12","kind":"trainer","position":Vector3(0,0,-2),"name":"Trainer"}
func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures.append(label);push_error(label)
func hands(x:float,side:="right",changes:Dictionary={})->Dictionary:
	var value:Dictionary={"position":Vector3(x,1.6,-.35),"tracked":true,"free":true,"open":true}
	value.merge(changes,true)
	return {side:value}
func perform(wave:RefCounted,side:="right",changes:Dictionary={},candidate:Dictionary=npc,permitted:=true)->int:
	var count:=0
	for i in range(121):
		if wave.sample(.01,head,hands(.3+.11*sin(i*.01*TAU*2),side,changes),candidate,permitted):count+=1
	return count
func _initialize()->void:call_deferred("run")
func run()->void:
	var visible:=func(_from,_to,_row):return true
	check(Wave.target([npc],Vector3.ZERO,head,visible).get("id")=="12","Look at a nearby NPC")
	for kind in Wave.NPC_KINDS:
		var row:=npc.duplicate();row.kind=kind
		check(not Wave.target([row],Vector3.ZERO,head,visible).is_empty(),"Existing NPC interaction supported: "+kind)
	for change in [{"position":Vector3(0,0,-3.01)},{"position":Vector3(2,0,-1)},{"position":Vector3(0,0,2)},{"dead":true},{"kind":"bank"},{"kind":"bazaar"},{"kind":"ticket_collector"}]:
		var row:=npc.duplicate();row.merge(change,true)
		check(Wave.target([row],Vector3.ZERO,head,visible).is_empty(),"Ineligible target ignored: "+str(change))
	check(Wave.target([npc],Vector3.ZERO,head,func(_a,_b,_c):return false).is_empty(),"Blocked sight line ignored")
	check(Wave.target([npc],Vector3.ZERO,head,Callable()).is_empty(),"Missing collision coverage fails closed")
	var other:=npc.duplicate();other.id="13";other.position.x=.02
	check(Wave.target([npc,other],Vector3.ZERO,head,visible).is_empty(),"Ambiguous adjacent NPCs require clearer gaze")
	check(Wave.target([npc,npc],Vector3.ZERO,head,visible).get("id")=="12","Duplicate service records retain one identity")
	for side in ["left","right"]:
		var wave:=Wave.new()
		check(perform(wave,side)==1,"Deliberate wave recognized once with "+side+" hand")
		check(perform(wave,side)==0,"Continuous wave stays latched after activation")
		wave.interrupt()
		check(perform(wave,side)==0,"Tracking loss cannot rearm completed wave")
		for i in range(40):wave.sample(.01,head,hands(.3,side,{"position":Vector3(.3,1.,-.3)}),npc,true)
		check(perform(wave,side)==1,"Lowering then waving rearms after cooldown")
	for change in [{"tracked":false},{"free":false},{"open":false},{"position":Vector3(.3,1.,-.3)}]:
		check(perform(Wave.new(),"right",change)==0,"Tracking, hand occupancy and height gate: "+str(change))
	check(perform(Wave.new(),"right",{},npc,false)==0,"Blocked UI does not collect a gesture")
	check(perform(Wave.new(),"right",{},{})==0,"Stale or missing discovery cannot trigger")
	var wave:=Wave.new();var fired:=false
	for i in range(160):fired=fired or wave.sample(.01,head,hands(.3+.01*sin(i*.3)),npc,true)
	check(not fired,"Hand tremor never forms a wave")
	wave.reset()
	for i in range(100):fired=fired or wave.sample(.01,head,hands(.2+i*.002),npc,true)
	check(not fired,"Single reach or sweep never forms a wave")
	wave.reset()
	for i in range(120):
		var row:=npc if i%20<10 else other
		fired=fired or wave.sample(.01,head,hands(.3+.11*sin(i*.01*TAU*2)),row,true)
	check(not fired,"Target changes cannot stitch a gesture together")
	wave.reset()
	for i in range(120):fired=fired or wave.sample(.2,head,hands(.3+.11*sin(i*.01*TAU*2)),npc,true)
	check(not fired,"Stalled tracking samples rejected")
	wave.reset();var rotation_events:=0
	for i in range(121):
		var angle:=deg_to_rad(35)*sin(i*.01*TAU*2)
		var point:=Vector3(.3,1.6,-.35)
		var tip:=point+Basis(Vector3.FORWARD,angle)*Vector3.UP*.18
		if wave.sample(.01,head,hands(.3,"right",{"wave_tip":tip}),npc,true):rotation_events+=1
	check(rotation_events==1,"Raised wrist rotation can wave without large arm translation")
	# Exercise the real service UI entry point and native request dispatch.
	var world:=Node3D.new();root.add_child(world)
	var rig:=XROrigin3D.new();world.add_child(rig)
	var camera:=XRCamera3D.new();camera.name="XRCamera3D";rig.add_child(camera);camera.transform=head
	var body:=CharacterBody3D.new();world.add_child(body)
	var ui:=preload("res://scripts/xr_services.gd").new();world.add_child(ui);ui.configure(rig,body);ui.set_process(false);ui.set_allowed(true)
	ui.terminal_provider=func():return [npc]
	ui.wave_visible=visible
	var calls:Array=[];ui.action_requested.connect(func(action,payload):calls.append({"action":action,"payload":payload}))
	for i in range(121):ui.wave_frame(.01,head,hands(.3+.11*sin(i*.01*TAU*2)))
	check(calls.size()==1 and calls[0].action=="open" and calls[0].payload.terminal_id=="12","Wave opens exactly one existing native trainer request")
	check(ui.pending and ui.terminal.id=="12" and ui.surface.visible,"Wave retains service pending latch and hologram")
	check(camera.transform==head,"Wave never moves tracked view")
	ui.close_interface();ui.set_pending(false)
	for i in range(121):ui.wave_frame(.01,head,hands(.3+.11*sin(i*.01*TAU*2)))
	check(calls.size()==1,"Closing panel while waving cannot reopen it")
	ui.npc_wave.reset();npc.kind="delivery";npc.mission_id="41"
	for i in range(121):ui.wave_frame(.01,head,hands(.3+.11*sin(i*.01*TAU*2)))
	check(calls.size()==2 and calls[-1].action=="delivery_open" and calls[-1].payload.mission_id=="41","Delivery wave preserves mission-specific NPC route")
	ui.close_interface();ui.set_pending(false);ui.npc_wave.reset()
	ui.wave_hand_free=func(_side):return true
	var trackers:Array=[]
	var head_tracker:=XRPositionalTracker.new();head_tracker.name="head";head_tracker.type=XRServer.TRACKER_HEAD
	head_tracker.set_pose("default",head,Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH);XRServer.add_tracker(head_tracker);trackers.append(head_tracker)
	for side in ["left","right"]:
		var tracker:=XRControllerTracker.new();tracker.type=XRServer.TRACKER_CONTROLLER;tracker.name=side+"_hand"
		tracker.set_pose("grip",Transform3D.IDENTITY,Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH)
		tracker.set_input("grip",0.0);tracker.set_input("trigger",0.0);XRServer.add_tracker(tracker);trackers.append(tracker)
		var controller:=XRController3D.new();controller.name="LeftHand" if side=="left" else "RightHand";controller.tracker=side+"_hand";controller.pose="grip";rig.add_child(controller)
		controller.position=Vector3(-.3,1.,-.3)
	for i in range(121):
		rig.get_node("RightHand").position=Vector3(.3+.11*sin(i*.01*TAU*2),1.6,-.35)
		ui._process(.01)
	check(calls.size()==3 and calls[-1].action=="delivery_open","Synthetic tracked controllers traverse actual XR process and open one NPC interaction")
	for tracker in trackers:XRServer.remove_tracker(tracker)
	world.free()
	var report:Dictionary={"passed":failures.is_empty(),"checks":checks,"failures":failures,"renderer":"dummy","tracking":"synthetic","native_transport":"mocked","headset_tested":false}
	print(JSON.stringify(report));FileAccess.open("res://../runtime/evidence/npc-wave-smoke.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	quit(0 if failures.is_empty() else 1)
