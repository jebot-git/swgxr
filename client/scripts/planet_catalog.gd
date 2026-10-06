extends RefCounted
## Converted source data availability is separate from native travel permission.
const ZONES=["tatooine","naboo","corellia","talus","rori","dantooine","dathomir","endor","lok","yavin4"]
const DEFAULT_PATH="res://../runtime/assets/planets/catalog.json"
var manifest:Dictionary={}
var path:=""
func configure(source:=DEFAULT_PATH)->void:
	path=ProjectSettings.globalize_path(source)
	manifest={}
	if FileAccess.file_exists(path):
		var parsed:Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary:manifest=parsed
static func current(app:Node)->String:
	var value:Variant=app.get("active_planet") if is_instance_valid(app) else null
	return str(value) if value is String and value in ZONES else "tatooine"
static func context_path(app:Node,key:String,fallback:String)->String:
	var value:Variant=app.get("planet_assets") if is_instance_valid(app) else null
	return str(value.get(key,ProjectSettings.globalize_path(fallback))) if value is Dictionary else ProjectSettings.globalize_path(fallback)
func descriptor(zone:String)->Dictionary:
	if zone not in ZONES:return {}
	if path.is_empty():configure()
	var row:Dictionary=manifest.get("planets",{}).get(zone,{}).duplicate(true)
	# Preserve existing local Tatooine installations until the catalog is built.
	if row.is_empty() and zone=="tatooine":
		row={"planet":zone,"label":"Tatooine","ready":true,"origin":[3618.98388671875,5,-4801.0859375],"stage":"res://../runtime/assets/mos_eisley/scene.json","world":"res://../runtime/assets/tatooine_world/world.json","terrain":"res://../runtime/assets/terrain/tatooine.json","terrain_context":"res://../runtime/assets/terrain/context.json","environment":"res://../runtime/assets/tatooine_environment/environment.json","services":"res://../runtime/assets/services/catalog.json","ambient_placements":"res://../runtime/assets/ambient_npcs/placements.json","ambient_npcs":"res://../runtime/assets/ambient_npcs/catalog.json","entities":"res://../runtime/assets/combat_population/native_current/catalog.json"}
	for key in ["stage","world","terrain","terrain_context","environment","services","ambient_placements","ambient_npcs","entities"]:
		var value:=str(row.get(key,""))
		if not value.is_empty():row[key]=ProjectSettings.globalize_path(value) if value.begins_with("res://") else value if value.is_absolute_path() else path.get_base_dir().path_join(value)
	return row
func readiness(zone:String)->Dictionary:
	var row:=descriptor(zone)
	if row.is_empty():return {"ok":false,"error":"Original planet assets are not prepared: "+zone}
	if not bool(row.get("ready",false)):return {"ok":false,"error":"Original planet assets are incomplete: "+zone,"failures":row.get("failures",[])}
	for key in ["world","terrain","terrain_context","environment","services","ambient_placements","ambient_npcs","entities"]:
		if str(row.get(key,"")).is_empty() or not FileAccess.file_exists(str(row[key])):return {"ok":false,"error":"Original %s assets are missing for %s"%[key,zone]}
	if not str(row.get("stage","")).is_empty() and not FileAccess.file_exists(str(row.stage)):return {"ok":false,"error":"Original entry stage is missing for "+zone}
	for catalog in row.get("entity_catalogs",[]):
		if not FileAccess.file_exists(str(catalog)):return {"ok":false,"error":"Original entity catalog missing for "+zone+": "+str(catalog)}
	return {"ok":true,"descriptor":row}
