extends Node3D
const Hands=preload("res://scripts/tracked_hand_input.gd")
var app:Node
var bag:Node3D
var scenery:Node3D
var allowed:=false
var busy:=false
var generation:=0
var poll:=0.0
var preview_poll:=0.0
var deed:Dictionary={}
var preview:Node3D
var preview_pose:=Transform3D.IDENTITY
var approved:Dictionary={}
var trigger_ready:=false
var arm:Dictionary={}
var arm_until:=0
var recover_ready:=true
var status:Label3D
var state:Dictionary={}
var error:=""
var factory_panel:Node3D
var harvester_panel:Node3D
var harvester_click_ready:=false
var harvester_requests:Dictionary={}
func setup(host:Node,inventory:Node3D)->void:
	app=host;bag=inventory;scenery=preload("res://housing/world.gd").new();add_child(scenery);scenery.setup(app)
	status=Label3D.new();status.font=preload("res://resources/fonts/Jupiteroid-Regular.ttf");status.font_size=22;status.pixel_size=.0006;status.billboard=BaseMaterial3D.BILLBOARD_ENABLED;add_child(status);status.hide()
	bag.item_held_changed.connect(held_changed)
	harvester_panel=preload("res://housing/harvester_panel.gd").new();add_child(harvester_panel);harvester_panel.setup(self)
	factory_panel=preload("res://housing/factory_panel.gd").new();add_child(factory_panel);factory_panel.setup(self)
	if is_instance_valid(app.get("datapad")):
		app.datapad.harvester_draw_requested.connect(draw_harvester)
		app.datapad.factory_blueprint_draw_requested.connect(draw_blueprint)
func set_allowed(value:bool)->void:
	allowed=value
	if is_instance_valid(preview):preview.visible=value and not bag.is_open
	if not value:trigger_ready=false;recover_ready=false;status.hide()
func reset()->void:
	if is_instance_valid(harvester_panel):harvester_panel.close()
	if is_instance_valid(factory_panel):factory_panel.close()
	if is_instance_valid(app.get("datapad")):app.datapad.ui.set_harvesting_deeds([]);app.datapad.ui.set_factory_blueprints([])
	harvester_requests.clear()
	generation+=1;busy=false;deed={};approved={};arm={};state={};poll=0
	if is_instance_valid(preview):preview.queue_free();preview=null
	if is_instance_valid(scenery):scenery.clear()
	if is_instance_valid(status):status.hide()
func held_changed(item:Dictionary)->void:
	deed=item.duplicate(true) if not str(item.get("structure_template","")).is_empty() else {}
	approved={};trigger_ready=false;preview_poll=0
	if is_instance_valid(preview):preview.queue_free();preview=null
	if deed.is_empty():return
	preview=scenery.model(str(deed.structure_template),"1",true)
	if preview==null:error="Original structure model unavailable; placement disabled.";return
	add_child(preview);scenery.color_preview(preview,false)
func candidate(pose:Transform3D)->Dictionary:
	return {"deed_id":str(deed.get("id","")),"placement_position":app.services.source(pose.origin),"rotation":posmod(roundi(-pose.basis.get_euler().y/(PI*.5)),4)}
func same_candidate(a:Dictionary,b:Dictionary)->bool:
	if a.get("deed_id","")!=b.get("deed_id","") or a.get("rotation",-1)!=b.get("rotation",-2):return false
	var p:Array=a.get("placement_position",[]);var q:Array=b.get("placement_position",[])
	return p.size()==3 and q.size()==3 and Vector3(p[0],p[1],p[2]).distance_to(Vector3(q[0],q[1],q[2]))<.15
func observe(response:Dictionary)->bool:
	if not response.get("ok",false) or response.get("source_kind","")!="core3_services" or str(response.get("character_id",""))!=app.datapad_character_id:return false
	var native:Dictionary=response.get("state",{})
	if str(native.get("character_id",""))!=app.datapad_character_id:return false
	if native.has("housing"):
		state=native.housing.duplicate(true);scenery.apply(state)
		if is_instance_valid(app.get("datapad")):app.datapad.ui.set_harvesting_deeds(state.get("deeds",[]));app.datapad.ui.set_factory_blueprints(state.get("blueprints",[]))
	var result:Dictionary=response.get("mutation",{})
	if result.has("arm") and result.get("success",false):arm=result.arm.duplicate(true);arm_until=Time.get_ticks_msec()+60000;status.text="Shake hands with the target within 60 seconds"
	return true
func request(action:String,extra:Dictionary={})->Dictionary:
	if busy or not allowed:return {}
	var version:=generation;var epoch:int=app.datapad_epoch
	var data:Dictionary=app.services.identity_payload();data.merge(extra,true)
	data.request_id="house-%d-%d"%[Time.get_unix_time_from_system()*1000000,Time.get_ticks_usec()]
	var mutation:=(action.begins_with("harvester_") or action.begins_with("factory_")) and not action.ends_with("_status")
	var request_key:=action+JSON.stringify(extra)
	if mutation:
		if harvester_requests.has(request_key):data=harvester_requests[request_key].duplicate(true)
		else:
			if harvester_requests.size()>=128:error="Resolve unconfirmed installation requests before starting another.";return {}
			harvester_requests[request_key]=data.duplicate(true)
	busy=true
	var response:Dictionary=await app.api(HTTPClient.METHOD_POST,"/services/house_"+action,data)
	if version!=generation or epoch!=app.datapad_epoch:return {}
	busy=false;poll=3.0
	if not observe(response):
		error=str(response.get("error","Core3 did not confirm housing operation. Refresh before retrying."));bag.set_busy(false,error)
		return {"ok":false,"error":error}
	if mutation:harvester_requests.erase(request_key)
	error=""
	var inv:Dictionary=response.get("state",{}).get("inventory",{})
	if inv.get("source_kind","")=="core3_inventory" and str(inv.get("character_id",""))==app.datapad_character_id:
		app.inventory_snapshot=inv.duplicate(true);app.reconcile_inventory_presentations();app.update_inventory_presentation()
	return response
func place()->void:
	if busy or deed.is_empty() or not is_instance_valid(preview):return
	var desired:=candidate(preview_pose)
	if not same_candidate(desired,approved) or not approved.get("valid",false):return
	bag.begin_mutation("Starting construction…")
	var result:=await request("place",desired)
	var success:bool=result.get("ok",false) and result.get("mutation",{}).get("success",false)
	bag.finish_item_action(success)
	if success:status.text="Core3 construction started";poll=.1
func try_drop(item:Dictionary,pose:Transform3D)->bool:
	if is_instance_valid(factory_panel) and factory_panel.try_drop(item,pose):return true
	if item.get("type","")=="manufacturing_blueprint":bag.finish_item_action(true);return true
	if is_instance_valid(harvester_panel) and harvester_panel.try_drop(item,pose):return true
	if not str(item.get("structure_template","")).is_empty():bag.finish_item_action(true);return true
	var cell:Dictionary=app.stage.current_cell if is_instance_valid(app.stage) else {}
	if str(cell.get("building_object_id","0")) in ["0","-1"]:return false
	# Inside a house never fall back to session-local drops when the server rejects.
	if busy or not allowed:bag.finish_item_action(false);return true
	var right:XRController3D=app.xr_origin.get_node("RightHand")
	var suspended:=Hands.controller_tracked(right) and right.is_button_pressed("ax_button")
	var actual:=pose
	if is_instance_valid(bag.held_model) and bag.held_model.get_child_count()>0:
		actual=bag.held_model.get_child(0).global_transform
		actual.basis=actual.basis.orthonormalized()
	var building:=str(cell.get("building_object_id","0"));var basis:=Basis.IDENTITY
	if scenery.structures.has(building):basis=scenery.structures[building].global_basis
	var q:Quaternion=(basis.inverse()*actual.basis).get_rotation_quaternion()
	var extra:Dictionary={"item_id":str(item.id),"placement_position":app.services.source(actual.origin),"local_quaternion":[-q.x,-q.y,q.z,q.w],"suspended":suspended}
	if not suspended:scenery.fall[str(item.id)]=actual.origin
	finish_drop(extra)
	return true
func finish_drop(extra:Dictionary)->void:
	var result:=await request("drop",extra)
	bag.finish_item_action(result.get("ok",false) and result.get("mutation",{}).get("success",false))
	if not result.get("ok",false):scenery.fall.erase(str(extra.item_id))
func recover(left:XRController3D,right:XRController3D)->void:
	if not bag.held_item.is_empty() or bag.is_open:return
	for row:Dictionary in state.get("structures",[]):
		if (row.get("harvester",false) or row.get("factory",false)) and str(row.owner_id)==app.datapad_character_id and scenery.touches_structure(str(row.id),left.global_position) and scenery.touches_structure(str(row.id),right.global_position):
			if row.get("factory",false):recover_factory(row,left.global_position,right.global_position)
			else:recover_harvester(row,left.global_position,right.global_position)
			return
	if not state.get("can_furnish",false):return
	for node:MeshInstance3D in scenery.items.values():
		var row:Dictionary=node.get_meta("native",{})
		if not row.get("recoverable",false):continue
		var bounds:AABB=node.mesh.get_aabb().grow(.10)
		if bounds.has_point(node.to_local(left.global_position)) and bounds.has_point(node.to_local(right.global_position)) and left.global_position.distance_to(node.global_position)<=1 and right.global_position.distance_to(node.global_position)<=1:
			request("recover",{"item_id":str(row.id),"left_hand":app.services.source(left.global_position),"right_hand":app.services.source(right.global_position)});return
func _process(dt:float)->void:
	if not allowed or not is_instance_valid(app.services):return
	if is_instance_valid(app.get("datapad")) and app.datapad.is_open:trigger_ready=false;recover_ready=false;harvester_click_ready=false;return
	poll-=dt;preview_poll-=dt
	var left:XRController3D=app.xr_origin.get_node("LeftHand");var right:XRController3D=app.xr_origin.get_node("RightHand")
	var tracked:=Hands.controller_tracked(left) and Hands.controller_tracked(right)
	if not tracked:trigger_ready=false;recover_ready=false;harvester_click_ready=false
	if tracked and minf(left.get_float("grip"),right.get_float("grip"))<.35:recover_ready=true
	if tracked and recover_ready and minf(left.get_float("grip"),right.get_float("grip"))>.65 and not busy:recover_ready=false;recover(left,right)
	if tracked and deed.is_empty() and bag.held_item.is_empty() and not bag.is_open and not harvester_panel.is_open and not factory_panel.is_open:
		var hand:XRController3D=right if bag.offhand=="left" else left
		if hand.get_float("trigger")<.35:harvester_click_ready=true
		elif hand.get_float("trigger")>.65 and harvester_click_ready:
			harvester_click_ready=false
			var finger:Dictionary=harvester_panel.pointing_pose(hand)
			var start:Vector3=finger.get("ray_origin",hand.global_position)
			var direction:Vector3=finger.get("direction",-hand.global_basis.z)
			var query:=PhysicsRayQueryParameters3D.create(start,start+direction*20,7,[app.player.get_rid()])
			var hit:Dictionary=get_world_3d().direct_space_state.intersect_ray(query)
			var id:String=scenery.structure_from_collider(hit.get("collider"))
			for row:Dictionary in state.get("structures",[]):
				if str(row.id)==id and row.get("admin",false):
					if row.get("factory",false):factory_panel.open_structure(row)
					elif row.get("harvester",false):harvester_panel.open_structure(row)
					break
	if not arm.is_empty():
		status.visible=true;status.global_position=right.global_position+Vector3(0,.2,0)
		var remaining:=maxi(0,ceili((arm_until-Time.get_ticks_msec())/1000.0));status.text="Shake hands · %ds"%remaining
		if remaining==0:arm={};status.hide()
		elif not busy:
			for peer:Dictionary in app.services.peers:
				if peer.get("house_permission_ready",false):
					var payload:Dictionary={"arm_id":str(arm.arm_id),"target_id":str(peer.id)};arm={};request("permission",payload);break
	if not deed.is_empty() and is_instance_valid(preview) and not bag.is_open:
		var hand:XRController3D=bag.held_controller()
		if not Hands.controller_tracked(hand):preview.hide();status.hide();approved={};trigger_ready=false;return
		preview.show()
		var pose:Transform3D=bag.item_hand_pose(hand,hand.global_transform)
		var from:=pose.origin;var direction:Vector3=-pose.basis.z
		var query:=PhysicsRayQueryParameters3D.create(from,from+direction*60,7);query.exclude=[app.player.get_rid()]
		var hit:Dictionary=get_world_3d().direct_space_state.intersect_ray(query)
		var valid_floor:=not hit.is_empty() and Vector3(hit.get("normal",Vector3.ZERO)).y>=.55
		preview_pose=Transform3D(Basis(Vector3.UP,roundf(pose.basis.get_euler().y/(PI*.5))*PI*.5),hit.get("position",from+direction*8))
		preview.global_transform=preview_pose
		var desired:=candidate(preview_pose);var fresh:bool=same_candidate(desired,approved) and approved.get("valid",false) and Time.get_ticks_msec()-int(approved.get("received",0))<1500
		scenery.color_preview(preview,fresh and valid_floor)
		status.show();status.global_position=pose.origin+Vector3(0,.15,0);status.text="Trigger: build · release: cancel" if fresh else error if not error.is_empty() else "Checking Core3 placement…"
		var trigger:=hand.get_float("trigger")
		if trigger<.35:trigger_ready=true
		if trigger>.65 and trigger_ready:trigger_ready=false;if_ready_place(fresh and valid_floor)
		if preview_poll<=0 and not busy and valid_floor:
			preview_poll=.5;check_preview(desired)
	elif arm.is_empty():
		status.visible=bool(state.get("construction_active",false)) or not error.is_empty()
		if status.visible:status.global_position=right.global_position+Vector3(0,.2,0);status.text=error if not error.is_empty() else "Core3 construction in progress"
	if poll<=0 and not busy and deed.is_empty() and not harvester_panel.is_open and not factory_panel.is_open and (not app.has_method("try_background_poll") or app.try_background_poll("housing")):request("status")
func if_ready_place(valid:bool)->void:
	if valid:place()
func check_preview(desired:Dictionary)->void:
	var result:=await request("preview",desired)
	if result.get("ok",false):
		approved=result.get("mutation",{}).duplicate(true);approved.received=Time.get_ticks_msec()
		if not approved.get("valid",false):error=str(approved.get("reason","Core3 rejected this placement"))

func draw_harvester(entry:Dictionary,_pose:Transform3D)->void:
	if busy or not bag.held_item.is_empty() or not app.world_ready:return
	var item:Dictionary=app.owned_inventory_item(str(entry.get("id","")))
	if item.is_empty() or not state.get("deeds",[]).any(func(row):return str(row.id)==str(item.id)):return
	app.datapad.set_open(false);bag.take_item(item)
func recover_harvester(row:Dictionary,left:Vector3,right:Vector3)->void:
	var result:=await request("harvester_recover",{"structure_id":str(row.id),"left_hand":app.services.source(left),"right_hand":app.services.source(right)})
	if result.get("ok",false) and str(harvester_panel.structure_id)==str(row.id):harvester_panel.close()

func owned_blueprint(id:String)->Dictionary:
	for row:Dictionary in state.get("blueprints",[]):
		if str(row.get("id",""))==id:return row
	return {}
func draw_blueprint(entry:Dictionary,_pose:Transform3D)->void:
	if busy or not bag.held_item.is_empty() or not app.world_ready:return
	var item:=owned_blueprint(str(entry.get("id","")))
	if item.is_empty():return
	app.datapad.set_open(false);bag.take_item(item)
func recover_factory(row:Dictionary,left:Vector3,right:Vector3)->void:
	var result:=await request("factory_recover",{"structure_id":str(row.id),"left_hand":app.services.source(left),"right_hand":app.services.source(right)})
	if result.get("ok",false) and result.get("mutation",{}).get("success",false) and str(factory_panel.structure_id)==str(row.id):factory_panel.close()
