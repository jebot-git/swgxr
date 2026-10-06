extends Node3D
## Grip owns only a preview; the sole mutation is a fresh trigger press.
const HandInput=preload("res://scripts/tracked_hand_input.gd")
var app:Node
var vendors:Dictionary={}
var held:Dictionary={}
var mount:Node3D
var visual:MeshInstance3D
var label:Label3D
var hologram:StandardMaterial3D
var assets=preload("res://scripts/inventory_assets.gd").new()
var placed:Dictionary={}
var records:Dictionary={}
var busy:=false
var trigger_armed:=false
var valid_pose:=false
var pose:Dictionary={}
var epoch:=-1
var generation:=0
var native_sequence:=-1
var native_session:=""
var status:=""
var awaiting_refresh:Dictionary={}
# Injectable floor query for mocked tracking tests; production uses actual collision.
var floor_query:Callable
func setup(host:Node)->void:
	app=host;process_priority=124;assets.configure()
	mount=Node3D.new();add_child(mount);mount.top_level=true;mount.hide()
	hologram=StandardMaterial3D.new();hologram.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;hologram.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;hologram.albedo_color=Color(.15,.85,1,.32);hologram.cull_mode=BaseMaterial3D.CULL_DISABLED
	label=Label3D.new();mount.add_child(label);label.font=preload("res://resources/fonts/Jupiteroid-Regular.ttf");label.font_size=22;label.pixel_size=.0015;label.billboard=BaseMaterial3D.BILLBOARD_ENABLED
	if is_instance_valid(app.datapad):app.datapad.vendor_draw_requested.connect(draw_vendor)
	reset()
func reset()->void:
	generation+=1;epoch=int(app.datapad_epoch);busy=false;native_sequence=-1;native_session="";vendors.clear();awaiting_refresh.clear();cancel()
	for model:Node3D in placed.values():model.queue_free()
	placed.clear();records.clear()
	if is_instance_valid(app.datapad):app.datapad.ui.set_vendors([])
func observe(response:Dictionary)->void:
	if not response.get("ok",false) or response.get("source_kind")!="core3_services" or str(response.get("character_id",""))!=app.datapad_character_id:return
	var state:Variant=response.get("state")
	if not state is Dictionary or not state.get("vendors") is Array:return
	var live:Dictionary=response.get("live_response",{})
	if not live.is_empty():
		var session:=str(live.get("session_id",""));var sequence:=int(live.get("sequence",-1))
		if session!=preload("res://scripts/native_session_identity.gd").id(app) or sequence<0 or (session==native_session and sequence<native_sequence):return
		native_session=session;native_sequence=sequence
	var next:Dictionary={}
	for item:Dictionary in state.vendors:
		if not str(item.get("id","")).is_valid_int() or str(item.get("template","")).is_empty() or next.has(str(item.id)):return
		var row:=item.duplicate(true);row.category="vendors";row.type="vendor";row.deletable=false
		next[str(row.id)]=row
	vendors=next;awaiting_refresh.clear()
	if not held.is_empty() and not vendors.has(str(held.id)):cancel()
	app.datapad.ui.set_vendors(vendors.values())
	show_placed(state.get("placed_vendors",[]))
func show_placed(rows:Array)->void:
	var retained:Dictionary={}
	records.clear()
	for row:Dictionary in rows:
		var id:=str(row.get("id",""))
		if id.is_empty() or not row.get("position") is Array or row.position.size()!=3:continue
		records[id]=row.duplicate(true)
		var model:MeshInstance3D=placed.get(id)
		if not is_instance_valid(model):
			var mesh:ArrayMesh=assets.model(str(row.get("template","")),row.get("customization",{}))
			if mesh==null:continue
			model=MeshInstance3D.new();model.mesh=mesh;add_child(model);model.top_level=true
			placed[id]=model
		var mesh:ArrayMesh=assets.model(str(row.get("template","")),row.get("customization",{}))
		if mesh!=null:model.mesh=mesh;assets.apply_morphs(model,row.get("customization",{}))
		model.global_position=app.services.world(row.position)
		model.global_rotation=Vector3(0,-float(row.get("heading_radians",0)),0)
		retained[id]=true
	for id in placed.keys():
		if not retained.has(id):placed[id].queue_free();placed.erase(id)
func draw_vendor(entry:Dictionary,hand_pose:Transform3D)->bool:
	if busy or not held.is_empty() or not app.world_ready or app.session_leaving or not hand_pose.is_finite():return false
	var id:=str(entry.get("id",""))
	if not vendors.has(id) or not is_instance_valid(app.services):return false
	if awaiting_refresh.has(id):app.datapad.ui.set_status("Wait for Core3 to refresh the vendor list.");return false
	if is_instance_valid(app.inventory) and not app.inventory.held_item.is_empty():
		app.datapad.ui.set_status("Return the held item before placing a vendor.");return false
	var mesh:ArrayMesh=assets.model(str(vendors[id].template),vendors[id].get("customization",{}))
	if mesh==null:app.datapad.ui.set_status("The original vendor model is unavailable.");return false
	if is_instance_valid(app.combat_rig):app.combat_rig.stow()
	held=vendors[id].duplicate(true);trigger_armed=false
	visual=MeshInstance3D.new();visual.mesh=mesh;assets.apply_morphs(visual,held.get("customization",{}));visual.material_override=hologram;visual.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;mount.add_child(visual)
	label.position.y=mesh.get_aabb().end.y+.12;mount.show();update_pose(hand_pose)
	app.datapad.set_open(false)
	return true
func cancel()->void:
	held.clear();pose.clear();valid_pose=false;trigger_armed=false
	if is_instance_valid(visual):visual.queue_free()
	visual=null
	if is_instance_valid(mount):mount.hide()
func blocks_interactions()->bool:return busy or not held.is_empty()
func floor_at(hand_pose:Transform3D)->Dictionary:
	if floor_query.is_valid():return floor_query.call(hand_pose)
	var query:=PhysicsRayQueryParameters3D.create(hand_pose.origin+Vector3.UP*.15,hand_pose.origin-Vector3.UP*3.5,1,[app.player.get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(query)
func unobstructed(point:Vector3)->bool:
	if floor_query.is_valid():return true
	var start:Vector3=app.player.global_position+Vector3.UP*.1
	var end:=point+Vector3.UP*.1
	if start.distance_squared_to(end)<.0001:return true
	var query:=PhysicsRayQueryParameters3D.create(start,end,1,[app.player.get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()
func update_pose(hand_pose:Transform3D)->void:
	valid_pose=false;pose.clear()
	var hit:=floor_at(hand_pose)
	var point:Vector3=hit.get("position",hand_pose.origin)
	# Keep the source model's authored origin and metre scale. Only yaw follows hand.
	mount.global_transform=Transform3D(Basis(Vector3.UP,hand_pose.basis.get_euler().y),point)
	var identity:Dictionary=app.services.identity_payload()
	var eligibility:Dictionary=app.services.state.get("vendor_placement",{})
	var reason:="Move the hologram onto a nearby floor"
	if app.services.state_age>8:reason="Waiting for current Core3 placement permissions"
	elif not eligibility.get("eligible",false):reason=str(eligibility.get("reason","Enter an authorized public building"))
	elif str(eligibility.get("building_id","0"))!=str(identity.building_id) or int(eligibility.get("cell_index",0))!=int(identity.cell_index):reason="Waiting for this room's placement permissions"
	elif not hit.is_empty() and hit.get("normal",Vector3.ZERO).dot(Vector3.UP)>.75 and point.distance_to(app.player.global_position)<=minf(4,float(eligibility.get("max_distance",4))) and unobstructed(point):
		valid_pose=true;reason="Trigger: place · Release grip: cancel"
		pose={"vendor_id":str(held.id),"placement_position":app.services.source(point),"placement_heading":wrapf(-mount.global_rotation.y,-PI,PI),"building_id":identity.building_id,"cell_index":identity.cell_index}
	hologram.albedo_color=Color(.15,.85,1,.32) if valid_pose else Color(1,.35,.15,.25)
	label.text=reason
func placement_frame(tracked:bool,hand_pose:Transform3D,grip:float,trigger:float)->void:
	if held.is_empty():return
	# Releasing while a confirmed press is in flight hides the preview; it cannot
	# undo a submitted mutation. Busy remains until that receipt resolves.
	if not tracked or not hand_pose.is_finite() or grip<.35:cancel();return
	if busy:return
	update_pose(hand_pose)
	if trigger<.3:trigger_armed=true
	if trigger<.55 or not trigger_armed:return
	trigger_armed=false
	if not valid_pose:return
	if app.services.busy or not app.services.allowed:label.text="Wait for Core3, then press trigger again";return
	commit()
func commit()->void:
	if busy or held.is_empty() or not valid_pose or app.services.busy or not app.services.allowed:return
	busy=true
	var version:=generation
	var request:=pose.duplicate(true)
	request.request_id="vendor-"+Crypto.new().generate_random_bytes(16).hex_encode()
	label.text="Placing vendor…"
	var response:Dictionary=await app.services.request("vendor_place",request)
	if version!=generation:return
	busy=false;cancel()
	awaiting_refresh[str(request.vendor_id)]=true
	var confirmed:bool=response.get("ok",false) and response.get("mutation",{}).get("success",false) and response.get("mutation",{}).get("placed",false) and str(response.get("mutation",{}).get("vendor_id",""))==str(request.vendor_id)
	status="Vendor placed." if confirmed else str(response.get("error","Placement was not confirmed. Refresh the datapad before retrying."))
	app.datapad.ui.set_status(status)
	# Refresh authority; never retry an uncertain placement with a new request.
	app.services.poll_clock=0.0
func _process(_delta:float)->void:
	if not is_instance_valid(app):return
	if epoch!=app.datapad_epoch:reset()
	if held.is_empty():return
	if not app.world_ready or app.loading_stage or app.session_leaving or app.menu.visible or not app.xr_requested:cancel();return
	var hand:XRController3D=app.xr_origin.get_node("RightHand" if app.vr_settings.offhand=="left" else "LeftHand")
	var head=XRServer.get_tracker("head")
	var head_pose:XRPose=head.get_pose("default") if head!=null else null
	placement_frame(app.xr_focused and head_pose!=null and head_pose.has_tracking_data and HandInput.controller_tracked(hand),hand.global_transform,hand.get_float("grip"),hand.get_float("trigger"))
