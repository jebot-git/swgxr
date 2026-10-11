extends SceneTree
const Services=preload("res://scripts/xr_services.gd")
var errors:Array=[]
var requests:Array=[]
var checks:=0
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:errors.append(message);push_error(message)
func _initialize()->void:call_deferred("run")
func run()->void:
	var world:=Node3D.new();root.add_child(world)
	var rig:=XROrigin3D.new();world.add_child(rig)
	var camera:=XRCamera3D.new();camera.name="XRCamera3D";rig.add_child(camera);camera.position.y=1.7
	for side in ["LeftHand","RightHand"]:
		var hand:=XRController3D.new();hand.name=side;rig.add_child(hand)
	var body:=CharacterBody3D.new();world.add_child(body)
	var ui:=Services.new();world.add_child(ui);ui.configure(rig,body);ui.set_process(false);ui.set_allowed(true)
	ui.action_requested.connect(func(action,payload):requests.append({"action":action,"payload":payload}))
	for kind:String in ["herald","pilot_trainer"]:
		ui.open_terminal({"id":"123","kind":kind,"name":"Original NPC","position":Vector3(0,0,-1)})
		check(requests.back().action==("herald_begin" if kind=="herald" else "open"),"Herald starts conversation directly; pilot retains native entry screen")
		ui.apply_response({"terminal":{"id":"123","kind":kind,"dialogue":"Ask about local destinations.","options":[{"name":"Speak","begin":true}]},"wallet":{"cash":100,"bank":0}})
		check(ui.panel.delivery_dialogue.visible and ui.panel.delivery_dialogue.text=="Ask about local destinations.","Existing scrollable dialogue area displays herald/pilot text")
		ui.panel.selected=0;ui.panel.confirm()
		var prefix:="herald_" if kind=="herald" else "pilot_"
		check(requests.back().action==prefix+"begin" and requests.back().payload.terminal_id=="123","Begin retains native NPC identity")
		var count:=requests.size();ui.panel.confirm();check(requests.size()==count,"Pending begin cannot repeat")
		ui.apply_response({"terminal":{"id":"123","kind":kind,"dialogue":"Choose a destination.","screen_token":"native_screen_2","options":[{"name":"Mark it on my map — 60 credits","option":2},{"name":"No thanks","option":0}]}})
		ui.panel.selected=0;ui.panel.confirm()
		check(requests.back().action==prefix+"choose" and requests.back().payload.option==2 and requests.back().payload.screen_token=="native_screen_2","Reply uses native option ID rather than row index and current screen token")
		check(ui.wallet.cash==100,"Choice cannot locally deduct credits or grant a waypoint")
		ui.close_interface();ui.apply_response({"terminal":{"id":"123","kind":kind,"dialogue":"Late reply","options":[]}})
		check(ui.terminal.is_empty() and not ui.surface.visible,"Late conversation response does not reopen closed panel")
	print(JSON.stringify({"passed":errors.is_empty(),"checks":checks,"errors":errors,"native_server":false,"headset_tested":false}))
	world.queue_free();await process_frame;quit(0 if errors.is_empty() else 1)
