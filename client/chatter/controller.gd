extends Node3D
## Presentation of recipient-specific, native-authoritative NPC speech only.
const Bubble=preload("res://chatter/bubble.gd")
const Heads=preload("res://chatter/head_anchor.gd")
const MAX_ACTIVE:=8
const MAX_EVENTS:=32
const MAX_DISTANCE:=32.0
const MAX_LIFETIME_MS:=6000
var app:Node
var active:Dictionary={}
var pool:Array=[]
var seen:Dictionary={}
var languages:Array=[]
var sequence:=-1
var created:=0
var culled:=0
var clock:=0.0
func setup(host:Node)->void:app=host
func clear()->void:
	for entry:Dictionary in active.values():release(entry)
	active.clear();seen.clear();languages=[];sequence=-1
func actor(id:String)->Node3D:
	var live:Variant=app.get("live_combat")
	if is_instance_valid(live) and live.get("live"):return live.actors.get(id)
	var sync:Variant=app.get("multiplayer_sync")
	if is_instance_valid(sync) and is_instance_valid(sync.entities):return sync.entities.actors.get(id)
	return null
func accept(value:Variant)->void:
	if not value is Dictionary:return
	var incoming:=int(value.get("sequence",-1));var events:Variant=value.get("events",[])
	if incoming<sequence or not events is Array or events.size()>MAX_EVENTS:return
	sequence=incoming
	if value.get("languages") is Array:languages=value.languages.slice(0,128).duplicate(true)
	var now:=Time.get_ticks_msec()
	for row in events:
		if not valid_event(row):continue
		var id:=str(row.id)
		if seen.has(id):continue
		seen[id]=now
		var age:=int(row.age_ms);var lifetime:=mini(MAX_LIFETIME_MS,int(row.lifetime_ms))
		if age>=lifetime or not context_matches(row):continue
		# One current sentence per speaker, replacing rather than stacking labels.
		var speaker:=str(row.actor_id)
		if active.has(speaker):release(active[speaker]);active.erase(speaker)
		if active.size()>=MAX_ACTIVE:continue
		var bubble:Node3D=pool.pop_back() if not pool.is_empty() else Bubble.new()
		if not bubble.is_inside_tree():add_child(bubble);created+=1
		bubble.present(row);bubble.hide()
		active[speaker]={"bubble":bubble,"event":row.duplicate(true),"expires":now+lifetime-age,"occlusion_due":0,"unoccluded":false}
	while seen.size()>128:seen.erase(seen.keys()[0])
func valid_event(row:Variant)->bool:
	if not row is Dictionary:return false
	for field in ["id","actor_id","zone","text"]:
		if not row.get(field) is String or str(row[field]).is_empty():return false
	if str(row.text).length()>2048:return false
	for field in ["age_ms","lifetime_ms"]:
		if not (row.get(field) is int or row.get(field) is float) or not is_finite(float(row[field])) or float(row[field])<0:return false
	return true
func context_matches(row:Dictionary)->bool:
	if not is_instance_valid(app) or not is_instance_valid(app.get("stage")):return false
	if str(row.zone)!=preload("res://scripts/planet_catalog.gd").current(app):return false
	var cell:Dictionary=app.stage.current_cell
	return str(row.get("building_id","0"))==str(cell.get("building_object_id","0")) and int(row.get("cell_index",0))==int(str(cell.get("cell_id","0:0")).get_slice(":",1))
func release(entry:Dictionary)->void:
	suppress_name(entry,null,false)
	entry.bubble.clear();pool.append(entry.bubble)
func suppress_name(entry:Dictionary,node:Node3D,show:bool)->void:
	var current:Variant=node.get("label") if is_instance_valid(node) else null
	if entry.has("name_label") and (not show or current!=entry.name_label):
		if is_instance_valid(entry.name_label):entry.name_label.visible=entry.name_visible
		entry.erase("name_label");entry.erase("name_visible")
	if show and is_instance_valid(current) and not entry.has("name_label"):
		entry.name_label=current;entry.name_visible=current.visible;current.hide()
func camera()->Camera3D:
	if not is_instance_valid(app) or not is_instance_valid(app.get("player")):return null
	return app.player.get_camera()
func visible_anchor(node:Node3D)->Variant:
	if not is_instance_valid(node) or not node.is_visible_in_tree() or node.get("record").get("dead",false):return null
	var anchor:Variant=Heads.crown(node)
	return anchor if anchor is Vector3 and anchor.is_finite() else null
func _process(delta:float)->void:
	clock+=delta
	var now:=Time.get_ticks_msec();var eye:=camera();culled=0
	for id in active.keys():
		var entry:Dictionary=active[id];var bubble:Node3D=entry.bubble
		if now>=int(entry.expires) or not context_matches(entry.event):release(entry);active.erase(id);continue
		var speaker:=actor(id);var anchor:Variant=visible_anchor(speaker);var show:bool=is_instance_valid(eye) and anchor is Vector3 and bool(app.get("world_ready")) and not bool(app.get("loading_stage")) and (not bool(app.get("xr_requested")) or bool(app.get("xr_focused")))
		if show:show=eye.global_position.distance_to(anchor)<=MAX_DISTANCE and not eye.is_position_behind(anchor) and eye.is_position_in_frustum(anchor+Vector3.UP*.35)
		if show:
			var tail:Vector3=anchor+Vector3.UP*.035
			var facing:=Basis.looking_at(eye.global_position-tail,Vector3.UP,true)
			var factor:=clampf(eye.global_position.distance_to(tail)/6.0,1.0,2.0)
			var center:Vector3=tail-facing*(Bubble.TAIL_TIP*factor)
			if now>=int(entry.occlusion_due):
				entry.occlusion_due=now+100
				entry.unoccluded=get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(eye.global_position,tail,7)).is_empty()
			show=entry.unoccluded
			if show:
				bubble.global_transform=Transform3D(facing.scaled(Vector3.ONE*factor),center)
		suppress_name(entry,speaker,show)
		bubble.visible=show
		if not show:culled+=1
func statistics()->Dictionary:return {"active":active.size(),"pooled":pool.size(),"created":created,"max_active":MAX_ACTIVE,"culled":culled,"viewports":0}

func _exit_tree()->void:
	for entry:Dictionary in active.values():suppress_name(entry,null,false)
