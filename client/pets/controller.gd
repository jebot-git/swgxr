extends Node
## Interaction only: the shared native world renders called droids exactly once.
const Hands=preload("res://scripts/tracked_hand_input.gd")
var app:Node
var vehicles:Node3D
var commands:Node3D
var creature_handler:Node3D
var released:=false
var allowed:=false
var generation:=-1
var pending_until:=0.0
var poll_at:=0.0
var pending_device:=""
var pending_spawned:=true
func setup(host:Node,vehicle_controller:Node3D)->void:
	app=host;vehicles=vehicle_controller;process_priority=-119
	if is_instance_valid(vehicles.get("head")):
		commands=preload("res://pets/commands.gd").new();add_child(commands);commands.setup(self)
		creature_handler=preload("res://pets/creature_handler.gd").new();add_child(creature_handler);creature_handler.setup(self)
func reset()->void:
	if is_instance_valid(creature_handler):creature_handler.reset()
	if is_instance_valid(commands):commands.reset()
	released=false;generation=app.datapad_epoch;pending_until=0;poll_at=0;pending_device=""
func set_allowed(value:bool)->void:
	if value!=allowed:released=false
	allowed=value
func request_entry(entry:Dictionary)->void:
	if vehicles.busy:
		app.datapad.ui.set_status("Another native request is in progress. Try again shortly.");return
	var epoch:int=app.datapad_epoch
	if vehicles.native_session()==null:
		if not app.has_method("ensure_gameplay_session") or not await app.ensure_gameplay_session():
			app.datapad.ui.set_status("Pet controls need a connected gameplay session.");return
	if epoch!=app.datapad_epoch:return
	var action:="pet_recall" if entry.get("spawned",false) else "pet_call"
	await vehicles.request(action,{"device_id":str(entry.id)})
	if epoch==app.datapad_epoch:
		pending_spawned=action=="pet_call";pending_device=str(entry.id);pending_until=Time.get_ticks_msec()/1000.0+20.0;poll_at=0
func merge_datapad()->void:
	if not is_instance_valid(app.datapad) or not vehicles.state.has("pet_datapad"):return
	var authoritative:Dictionary={};var current:Dictionary={}
	for row:Dictionary in vehicles.state.pet_datapad:authoritative[str(row.id)]=[row.template,row.spawned,row.get("pet_kind","droid")]
	for row:Dictionary in app.datapad.ui.entries:
		if (row.get("native_droid",false) or row.get("native_pet",false)):current[str(row.id)]=[row.template,row.spawned,row.get("pet_kind","droid")]
	if authoritative==current:return
	var selected_id:=str(app.datapad.ui.selected_entry.get("id",""))
	var entries:Array=app.datapad.ui.entries.filter(func(row):return not (row.get("native_droid",false) or row.get("native_pet",false)) and not authoritative.has(str(row.get("id",""))))
	for row:Dictionary in vehicles.state.pet_datapad:
		var entry:=row.duplicate(true);entry.category="pets";entry.native_droid=row.get("pet_kind","droid")=="droid";entry.native_pet=true;entry.deletable=false
		entry.description="Called into the world. Offhand trigger over pet opens commands. Both grips recover." if entry.spawned else "Stored in datapad. CoreCU call limits and cooldowns apply."
		entries.append(entry)
	app.datapad.ui.set_entries(entries)
	for i in range(app.datapad.ui.filtered_entries.size()):
		if str(app.datapad.ui.filtered_entries[i].id)==selected_id:app.datapad.ui.list.select(i);app.datapad.ui.select_entry(i);break
func touches(row:Dictionary,point:Vector3)->bool:
	if is_instance_valid(commands):return commands.touches(row,point)
	var offset:Vector3=point-vehicles.world(row.position)
	return Vector2(offset.x,offset.z).length()<=float(row.radius)+.15 and offset.y>=-.15 and offset.y<=float(row.height)+.15
func gesture_claimed()->bool:
	var scout:Variant=app.get("scout")
	return (is_instance_valid(scout) and is_instance_valid(scout.get("ranger")) and scout.ranger.claims) or (is_instance_valid(creature_handler) and creature_handler.claims)
func _process(_delta:float)->void:
	if not is_instance_valid(app) or not is_instance_valid(vehicles):return
	if generation!=app.datapad_epoch:reset()
	merge_datapad()
	var now:=Time.get_ticks_msec()/1000.0
	if pending_until>now:
		if vehicles.state.get("pet_datapad",[]).any(func(row):return str(row.id)==pending_device and row.spawned==pending_spawned):pending_until=0
		elif now>=poll_at and not vehicles.busy and (not app.has_method("try_background_poll") or app.try_background_poll("vehicles")):
			poll_at=now+1;vehicles.request("status")
	var left:XRController3D=vehicles.left;var right:XRController3D=vehicles.right
	var tracked:bool=vehicles.body.active and bool(vehicles.body.combat_tracking_context().tracked) and Hands.controller_tracked(left) and Hands.controller_tracked(right)
	if not allowed or not tracked or vehicles.body.feedback.combat_blocked() or vehicles.seated() or vehicles.age>8 or app.datapad_character_id.is_empty():released=false;return
	if gesture_claimed():released=false;return
	var left_grip:float=left.get_float("grip");var right_grip:float=right.get_float("grip")
	if left_grip<.35 and right_grip<.35:released=true;return
	if left_grip<=.65 or right_grip<=.65:return
	if not released or vehicles.busy or not vehicles.available("left") or not vehicles.available("right"):return
	released=false
	for row:Dictionary in vehicles.state.get("pets",[]):
		if not row.get("owned",false) or row.get("in_combat",false):continue
		if touches(row,left.global_position) and touches(row,right.global_position):
			if is_instance_valid(commands):commands.reset()
			pending_device=str(row.device_id);pending_spawned=false;pending_until=now+10;poll_at=now+1
			vehicles.request("pet_store",{"device_id":str(row.device_id),"left":vehicles.source(left.global_position),"right":vehicles.source(right.global_position)});return
