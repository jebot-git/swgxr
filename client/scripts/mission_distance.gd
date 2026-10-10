extends RefCounted
## World coordinates only: never compare destinations across planets or cells.
static func text(row:Dictionary,position:Vector3,planet:String)->String:
	var destination:Dictionary=row.get("waypoint",{})
	if destination.is_empty():destination=row
	var target_planet:=str(destination.get("planet",destination.get("zone","")))
	var point:Variant=destination.get("position")
	if target_planet.is_empty() or not point is Array or point.size()!=3 or not position.is_finite():return ""
	for component in point:
		if not (component is float or component is int) or not is_finite(float(component)):return ""
	if target_planet!=planet:return "Destination: "+target_planet.capitalize()+" (another planet)"
	if str(destination.get("cell_id","0")) not in ["","0"]:return ""
	var target:=Vector3(float(point[0]),float(point[1]),float(point[2]))
	var distance:=Vector2(position.x,position.z).distance_to(Vector2(target.x,target.z))
	return "Distance: "+("%.1f km"%(distance/1000.0) if distance>=1000 else "%d m"%roundi(distance))+" (straight line)"
