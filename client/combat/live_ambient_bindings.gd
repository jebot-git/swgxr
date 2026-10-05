extends RefCounted
## Exact source-placement ownership, never a same-race or nearest-NPC guess.
## Basic trainer alternatives require original variant membership and native cell.
## Bound native IDs persist for this session, including known-dead tombstones.
const MATCH_DISTANCE := 0.25
var by_template:Dictionary={}
var placements:Dictionary={}
var bindings:Dictionary={}
var suppressed:Dictionary={}
func configure(manifest:Dictionary,trainer_audit:Dictionary={})->void:
	by_template.clear();placements.clear();bindings.clear();suppressed.clear()
	if trainer_audit.is_empty():
		var path:="res://../runtime/assets/services/trainers.json"
		if FileAccess.file_exists(path):
			var parsed:Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
			if parsed is Dictionary:trainer_audit=parsed
	for entry:Dictionary in manifest.get("instances",[]):
		var values:Variant=entry.get("source_world_xyz")
		var template:=str(entry.get("template",""));var id:=str(entry.get("id",""))
		if template.is_empty() or id.is_empty() or not values is Array or values.size()!=3:continue
		var position:=Vector3(float(values[0]),float(values[1]),float(values[2]))
		if not position.is_finite():continue
		placements[id]=entry.duplicate(true)
		var variants:Array=[template]
		var trainer:Dictionary=trainer_audit.get("trainers",{}).get(str(entry.get("mobile","")),{})
		var basic_trainer:bool=not trainer.is_empty() and id in trainer.get("placement_ids",[]) and template in trainer.get("templates",[])
		if basic_trainer:variants=trainer.templates
		for variant:String in variants:
			if not by_template.has(variant):by_template[variant]=[]
			by_template[variant].append({"id":id,"position":position,"trainer":basic_trainer,
				"building_id":str(entry.get("building_object_id","0")),"cell_index":int(str(entry.get("cell_id","0:0")).get_slice(":",1))})
func update(actors:Array)->Dictionary:
	var candidates:Array=[]
	for actor:Dictionary in actors:
		var native_id:=str(actor.get("id",""))
		if native_id.is_empty() or bindings.has(native_id) or actor.get("kind","")!="creature":continue
		var values:Variant=actor.get("position")
		if not values is Array or values.size()!=3:continue
		var position:=Vector3(float(values[0]),float(values[1]),float(values[2]))
		for placement:Dictionary in by_template.get(str(actor.get("template","")),[]):
			if suppressed.has(placement.id):continue
			if bool(placement.trainer) and (not actor.has("building_id") or not actor.has("cell_index") or str(actor.building_id)!=placement.building_id or int(actor.cell_index)!=int(placement.cell_index)):continue
			var distance:=position.distance_to(placement.position)
			if distance<=MATCH_DISTANCE:candidates.append({"native_id":native_id,"placement_id":placement.id,"distance":distance})
	candidates.sort_custom(func(a,b):return a.distance<b.distance if a.distance!=b.distance else str(a.native_id)+str(a.placement_id)<str(b.native_id)+str(b.placement_id))
	for candidate:Dictionary in candidates:
		if bindings.has(candidate.native_id) or suppressed.has(candidate.placement_id):continue
		bindings[candidate.native_id]=candidate.placement_id;suppressed[candidate.placement_id]=candidate.native_id
	return suppressed.duplicate()
func clear()->void:
	bindings.clear();suppressed.clear()
