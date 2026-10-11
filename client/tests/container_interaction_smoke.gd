extends SceneTree
var failed:Array=[]
var count:=0
func check(value:bool,label:String)->void:
	count+=1
	if not value:failed.append(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	var world:=Node3D.new();root.add_child(world)
	var rig:=XROrigin3D.new();world.add_child(rig)
	var camera:=XRCamera3D.new();camera.name="XRCamera3D";rig.add_child(camera);camera.position.y=1.7
	for side in ["LeftHand","RightHand"]:
		var hand:=XRController3D.new();hand.name=side;rig.add_child(hand)
	var body:=CharacterBody3D.new();world.add_child(body)
	var view=preload("res://scripts/xr_services.gd").new();world.add_child(view);view.configure(rig,body);view.set_process(false);view.set_allowed(true)
	var requests:Array=[];var grabs:Array=[]
	view.action_requested.connect(func(action,payload):requests.append([action,payload]))
	view.container_grab_requested.connect(func(item):grabs.append(item))
	view.open_terminal({"id":"20","kind":"container","name":"Storage crate","position":Vector3(0,0,-1)})
	var item:Dictionary={"id":"21","container_id":"20","external_container_id":"20","external_anchor_id":"20","name":"Supply","template":"object/tangible/droid_battery/battery.iff","quantity":1,"is_container":false}
	var state:Dictionary={"inventory":{"id":"20","parent_id":"20","capacity":10,"occupied":1},"containers":[{"id":"20","parent_id":"20","capacity":10,"occupied":1}],"items":[item],"external":true,"anchor_id":"20","root_id":"20"}
	view.apply_response({"terminal":{"id":"20","kind":"container","storage":state}})
	check(view.panel.grid.items.size()==1,"Standard inventory grid receives native storage")
	var pixel:Vector2=view.panel.GRID_POSITION+(Vector2(50,150)*view.panel.GRID_SCALE)
	view.set_inventory_focus(true)
	view.pointer_frame({"pixel":pixel},0,0)
	view.pointer_frame({"pixel":pixel},0,1)
	view.pointer_frame({"pixel":pixel},0,1)
	check(grabs.size()==1 and grabs[0].id=="21","Grip works with backpack focus and does not repeat while held")
	view.set_pending(true);view.pointer_frame({"pixel":pixel},0,0);view.pointer_frame({"pixel":pixel},0,1)
	check(grabs.size()==1,"Pending native transfer prevents duplicate grab")
	view.set_pending(false);view.panel.pointer_begin(Vector2(680,580));view.panel.pointer_end(Vector2(680,580))
	check(requests.back()[0]=="open" and requests.back()[1].container_id=="20","Refresh retains native container identity")
	view.close_interface();view.apply_response({"terminal":{"id":"20","kind":"container","storage":state}})
	check(view.terminal.is_empty() and not view.surface.visible,"Late response cannot reopen closed storage")
	print("CONTAINER_INTERACTION_SMOKE=",JSON.stringify({"passed":failed.is_empty(),"checks":count,"failures":failed,"renderer":"dummy","mocked_tracking":true}))
	world.free();quit(0 if failed.is_empty() else 1)
