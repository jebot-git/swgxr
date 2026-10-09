extends RefCounted
## Native crew IDs/appearance own presence. Authenticated, short-lived poses only
## decorate members of that exact ship and cell; they cannot add a passenger.
const State=preload("res://multiplayer/replication_state.gd")
func normalize(ship:Dictionary,poses:Array,owner:String,stage:Node3D)->Array:
	var rows:Array=[];var by_id:Dictionary={};var seen:Dictionary={}
	var ship_id:=str(ship.get("id",""))
	for pose:Variant in poses.slice(0,32):
		if not pose is Dictionary or str(pose.get("ship_id",""))!=ship_id:continue
		var age:=float(pose.get("age_ms",INF))
		if not is_finite(age) or age<0 or age>750:continue
		by_id[str(pose.get("id",pose.get("character_id","")))]=pose
	for native:Variant in ship.get("crew",[]).slice(0,32):
		if not native is Dictionary:continue
		var id:=str(native.get("id",""));var position:Variant=native.get("position")
		if not State.valid_id(id) or id==owner or seen.has(id) or not State.finite_point(position) or not native.get("appearance") is Dictionary:continue
		if str(native.get("ship_id",ship_id))!=ship_id or not is_finite(float(native.get("heading_radians",NAN))):continue
		seen[id]=true
		var row:Dictionary=native.duplicate(true);var body:Vector3=State.point(position)
		row.position=stage.to_global(Vector3(body.x,body.y,-body.z));row.tracking={}
		row.heading_radians=(stage.global_basis*Basis(Vector3.UP,-float(native.heading_radians))).get_euler().y
		row.cell_id=ship_id+":"+str(native.get("cell_index",0))
		var pose:Dictionary=by_id.get(id,{})
		if int(pose.get("cell_index",-1))==int(native.get("cell_index",0)) and State.finite_point(pose.get("position")) and State.point(pose.position).distance_to(body)<=3:
			row.pose_age_ms=pose.age_ms
			if is_finite(float(pose.get("heading_radians",NAN))):row.heading_radians=(stage.global_basis*Basis(Vector3.UP,-float(pose.heading_radians))).get_euler().y
			var tracking:Variant=pose.get("tracking",{})
			if tracking is Dictionary:
				for key in ["head","left_hand","right_hand"]:
					var target:Variant=tracking.get(key)
					if not target is Dictionary or not target.get("tracked",false) or not State.finite_point(target.get("position")) or not State.finite_rotation(target.get("rotation")):continue
					var p:Vector3=State.point(target.position)
					if p.distance_to(body)>3:continue
					row.tracking[key]=Transform3D(State.world_rotation(target.rotation,stage.global_basis),stage.to_global(Vector3(p.x,p.y,-p.z)))
			if int(native.get("posture",0))==0 and not row.tracking.is_empty():row.physical_posture=clampi(int(pose.get("physical_posture",0)),0,2)
		rows.append(row)
	return rows
