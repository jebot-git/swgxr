extends RefCounted
## Presentation-only reconciliation of original terrain with native outdoor NPCs.
## Core3 static/patrol coordinates can remain below the client terrain surface.
## Only nonattackable passive citizens: combat projectile rays remain native.
## Never edits authority, raises interiors, or floor-snaps arbitrary creatures.
const MAX_LIFT:=1.5
const MIN_PENETRATION:=0.03
var samples:=0
func apply(actor:Node3D,row:Dictionary,terrain:Node,stage:Node3D)->void:
	var allowed:=eligible(actor,row) and is_instance_valid(terrain) and bool(terrain.get("configured")) and is_instance_valid(stage)
	if not allowed:
		actor.set_presentation_floor_offset(0.0)
		if actor.has_meta("terrain_projection_key"):actor.remove_meta("terrain_projection_key")
		return
	var cells:Variant=stage.get("definitions")
	var key:Array=[row.position,terrain.get_instance_id(),stage.global_transform,cells.size() if cells is Dictionary else 0]
	if actor.get_meta("terrain_projection_key",[])==key:return
	actor.set_meta("terrain_projection_key",key.duplicate(true))
	var source:Vector3=Vector3(float(row.position[0]),float(row.position[1]),float(row.position[2]))
	var native_point:Vector3=stage.to_global(Vector3(source.x-terrain.origin.x,source.y-terrain.origin.y,terrain.origin.z-source.z))
	# A native parent-cell mismatch must not pull basement/doorway residents
	# through the terrain. Retain their native pose until cell state is sound.
	if stage.has_method("classify_world") and not stage.classify_world(native_point).is_empty():
		actor.set_presentation_floor_offset(0.0);return
	var height:float=terrain.evaluator.sample_height(source.x,source.z);samples+=1
	var lift:float=height-source.y
	actor.report["terrain_projection"]={"native_y":source.y,"terrain_y":height,"penetration":lift,"bounded":lift<=MAX_LIFT,"sample_only_on_snapshot_change":true}
	actor.set_presentation_floor_offset(lift if is_finite(lift) and lift>=MIN_PENETRATION and lift<=MAX_LIFT else 0.0)
func eligible(actor:Node3D,row:Dictionary)->bool:
	if int(row.get("pvp_status",-1))!=0:return false
	if row.get("kind","")!="creature" or bool(row.get("dead",false)) or bool(row.get("incapacitated",false)) or int(row.get("posture",0))!=0:return false
	if str(row.get("building_id","0"))!="0" or int(row.get("cell_index",0))!=0:return false
	if str(row.get("mood","")).contains("sitting"):return false
	if not is_instance_valid(actor.visual) or not actor.visual.has_method("update_motion"):return false
	# Original humanoid rig only: no flyers, swimmers, vehicles or quadrupeds.
	var skeleton:Skeleton3D=actor.visual.get("skeleton")
	return skeleton!=null and skeleton.find_bone("lankle")>=0 and skeleton.find_bone("rankle")>=0 and skeleton.find_bone("lwrist")>=0 and skeleton.find_bone("rwrist")>=0
