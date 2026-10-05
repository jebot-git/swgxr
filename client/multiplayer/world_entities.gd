extends Node3D
## Native scene projection for ordinary persistent play. Creation is bounded to
## two original-asset entities per frame; gameplay health never comes from art.
const FloorProjection=preload("res://combat/actor_floor_projection.gd")
const Actor=preload("res://combat/live_actor.gd")
const Bindings=preload("res://combat/live_ambient_bindings.gd")
const Assets=preload("res://scripts/inventory_assets.gd")
var app:Node
var actors:Dictionary={}
var desired:Dictionary={}
var bindings:=Bindings.new()
var floor_projection:=FloorProjection.new()
var assets:=Assets.new()
var dead_assets:=Assets.new()
var session_id:=""
var revision:=-1
var last_snapshot_ms:=0
var snapshot_seconds:=1.0
var ambient:Node
var suppressed:Dictionary={}
func setup(host:Node)->void:
	app=host;assets.configure();dead_assets.configure(ProjectSettings.globalize_path("res://../runtime/assets/corpses/catalog.json"))
	ambient=app.ambient_npcs
	if is_instance_valid(ambient):bindings.configure(ambient.manifest)
func clear()->void:
	for actor:Node in actors.values():actor.free()
	actors.clear();desired.clear();bindings.clear();suppressed.clear();revision=-1
	if is_instance_valid(ambient):ambient.set_live_suppressed({})
func accept(rows:Array,owner:String,world_revision:int)->void:
	if revision==world_revision:return
	snapshot_seconds=maxf(.1,(Time.get_ticks_msec()-last_snapshot_ms)/1000.0) if last_snapshot_ms>0 else 1.0
	last_snapshot_ms=Time.get_ticks_msec();revision=world_revision;session_id=owner
	bindings.update(rows);desired.clear()
	for row:Dictionary in rows:
		if not valid_actor(row):continue
		var value:=row.duplicate(true)
		var id:=str(value.id)
		if bindings.bindings.has(id) and is_instance_valid(ambient):
			var placement:Dictionary=bindings.placements[bindings.bindings[id]]
			value.source_placement_visual={"placement_id":str(placement.id),"appearance_id":str(placement.get("appearance_id",placement.template)),"catalog":ambient.catalog_path,"cell_id":str(placement.get("cell_id",""))}
		desired[id]=value
	for id in actors.keys():
		if not desired.has(id):actors[id].free();actors.erase(id)
		elif signature(actors[id].record)!=signature(desired[id]):actors[id].free();actors.erase(id)
		else:apply_actor(actors[id],desired[id],false)
func valid_actor(row:Dictionary)->bool:
	return not str(row.get("template","")).is_empty() and row.get("kind","") in ["creature","lair"] and row.get("dead") is bool and is_finite(float(row.get("health",NAN))) and is_finite(float(row.get("max_health",NAN))) and float(row.max_health)>0 and float(row.get("scale",1))>0 and float(row.get("scale",1))<=20
func signature(row:Dictionary)->Array:
	return [row.get("template"),row.get("dead"),row.get("scale",1),row.get("customization",{}),row.get("equipment",[]),row.get("source_placement_visual",{})]
func apply_actor(actor:Node3D,row:Dictionary,initial:bool)->void:
	var pose:=Transform3D(app.stage.global_basis*Basis(Vector3.UP,-float(row.heading_radians)),app.multiplayer_sync.world(row.position))
	actor.apply_record(row,pose,snapshot_seconds,initial)
	floor_projection.apply(actor,row,app.get("terrain"),app.stage)
	apply_cell_visibility(actor,row)
func apply_cell_visibility(actor:Node3D,row:Dictionary)->void:
	# The source cell is authoritative, including out-of-cell stale collision.
	var cell:Dictionary=app.stage.current_cell
	var same_cell:=str(row.get("building_id","0"))==str(cell.get("building_object_id","0")) and int(row.get("cell_index",0))==int(str(cell.get("cell_id","0:0")).get_slice(":",1))
	actor.visible=same_cell
	actor.collision_layer=8 if same_cell and actor.is_targetable() else 0
func _process(_delta:float)->void:
	if not is_instance_valid(app) or not is_instance_valid(app.stage):return
	for actor:Node3D in actors.values():apply_cell_visibility(actor,actor.record)
	var created:=0
	for id in desired:
		if actors.has(id):continue
		var actor:=Actor.new();add_child(actor)
		if actor.configure(desired[id],session_id,assets,dead_assets,ProjectSettings.globalize_path("res://../runtime/assets/combat_population/native_current/catalog.json")):
			actors[id]=actor;actor.add_to_group("swg_radar_contacts");apply_actor(actor,desired[id],true)
		else:actor.free()
		created+=1
		if created>=2:break
	if is_instance_valid(ambient):
		for id in actors:
			if bindings.bindings.has(id) and actors[id].report.get("source_variant_ready",false):suppressed[bindings.bindings[id]]=id
		ambient.set_live_suppressed(suppressed)
func _exit_tree()->void:
	if is_instance_valid(ambient):ambient.set_live_suppressed({})
