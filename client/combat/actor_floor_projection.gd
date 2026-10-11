extends RefCounted
## Presentation-only reconciliation of passive citizens with original floors.
## Core3 patrol coordinates can cut through interpolated stairs and ramps.
## Only nonattackable passive citizens: combat projectile rays remain native.
## Never edits authority or floor-snaps arbitrary creatures.
const MAX_LIFT:=1.5
const MIN_PENETRATION:=0.03
var samples:=0
func bind(actor:Node3D,row:Dictionary,terrain:Node,stage:Node3D)->void:
	if not eligible(actor,row):
		actor.presentation_floor_update=Callable()
		apply(actor,row,terrain,stage)
		return
	actor.presentation_floor_update=update_frame.bind(actor,terrain,stage)
	update_frame(actor,terrain,stage)
func update_frame(actor:Node3D,terrain:Node,stage:Node3D)->void:
	if not is_instance_valid(stage) or not is_instance_valid(terrain):actor.set_presentation_floor_offset(0);return
	# Motion interpolation advances between snapshots. Support must follow that
	# rendered position, not the newest packet's destination on another step.
	var point:Vector3=stage.to_local(actor.global_position)
	var row:Dictionary=actor.record.duplicate()
	row.position=[point.x+terrain.origin.x,point.y+terrain.origin.y,terrain.origin.z-point.z]
	apply(actor,row,terrain,stage)
func apply(actor:Node3D,row:Dictionary,terrain:Node,stage:Node3D)->void:
	var allowed:=eligible(actor,row) and is_instance_valid(terrain) and bool(terrain.get("configured")) and is_instance_valid(stage)
	if not allowed:
		actor.set_presentation_floor_offset(0.0)
		if actor.has_meta("terrain_projection_key"):actor.remove_meta("terrain_projection_key")
		if actor.has_meta("citizen_floor_support"):actor.remove_meta("citizen_floor_support")
		return
	var cells:Variant=stage.get("definitions")
	var cell_id:=str(row.get("building_id","0"))+":"+str(row.get("cell_index",0))
	var key:Array=[row.position,cell_id,terrain.get_instance_id(),stage.global_transform,cells.size() if cells is Dictionary else 0]
	if actor.get_meta("terrain_projection_key",[])==key:return
	actor.set_meta("terrain_projection_key",key.duplicate(true))
	var source:Vector3=Vector3(float(row.position[0]),float(row.position[1]),float(row.position[2]))
	var native_point:Vector3=stage.to_global(Vector3(source.x-terrain.origin.x,source.y-terrain.origin.y,terrain.origin.z-source.z))
	if int(row.get("cell_index",0))>0 and str(row.get("building_id","0"))!="0":
		var support:Variant=stage.get("ground_support")
		if support==null or not cells is Dictionary or not cells.has(cell_id):actor.set_presentation_floor_offset(0);return
		var previous:Dictionary=actor.get_meta("citizen_floor_support",{})
		var hit:Dictionary=support.sample_support(native_point,[cell_id],MAX_LIFT,MAX_LIFT,previous)
		samples+=1
		var lift:=float(hit.get("height",native_point.y))-native_point.y
		var valid:bool=hit.get("valid",false) and Vector3(hit.get("normal",Vector3.ZERO)).y>=.65 and absf(lift)<=MAX_LIFT
		actor.set_meta("citizen_floor_support",hit if valid else {})
		actor.report["terrain_projection"]={"kind":"authored_cell_floor","cell_id":cell_id,"penetration":lift,"valid":valid}
		actor.set_presentation_floor_offset(lift if valid else 0.0);return
	if actor.has_meta("citizen_floor_support"):actor.remove_meta("citizen_floor_support")
	# A native parent-cell mismatch must not pull basement/doorway residents
	# through the terrain. Retain their native pose until cell state is sound.
	if stage.has_method("classify_world") and not stage.classify_world(native_point).is_empty():
		actor.set_presentation_floor_offset(0.0);return
	var height:float=terrain.evaluator.sample_height(source.x,source.z);samples+=1
	var support:Variant=stage.get("ground_support")
	var exterior:Variant=stage.get("exterior_ids")
	if support!=null and exterior is Array and not exterior.is_empty():
		var hit:Dictionary=support.sample_support(native_point,exterior,MAX_LIFT,MAX_LIFT,{})
		if hit.get("valid",false) and Vector3(hit.get("normal",Vector3.ZERO)).y>=.65:
			var floor_point:Vector3=stage.to_local(Vector3(native_point.x,float(hit.height),native_point.z))
			height=maxf(height,floor_point.y+terrain.origin.y)
	var lift:float=height-source.y
	actor.report["terrain_projection"]={"native_y":source.y,"terrain_y":height,"penetration":lift,"bounded":lift<=MAX_LIFT,"sample_only_on_position_or_floor_change":true}
	actor.set_presentation_floor_offset(lift if is_finite(lift) and lift>=MIN_PENETRATION and lift<=MAX_LIFT else 0.0)
func eligible(actor:Node3D,row:Dictionary)->bool:
	if int(row.get("pvp_status",-1))!=0:return false
	if row.get("kind","")!="creature" or bool(row.get("dead",false)) or bool(row.get("incapacitated",false)) or int(row.get("posture",0))!=0:return false
	if str(row.get("mood","")).contains("sitting"):return false
	if not is_instance_valid(actor.visual) or not actor.visual.has_method("update_motion"):return false
	# Original humanoid rig only: no flyers, swimmers, vehicles or quadrupeds.
	var skeleton:Skeleton3D=actor.visual.get("skeleton")
	return skeleton!=null and skeleton.find_bone("lankle")>=0 and skeleton.find_bone("rankle")>=0 and skeleton.find_bone("lwrist")>=0 and skeleton.find_bone("rwrist")>=0
