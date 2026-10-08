extends RefCounted
## Resolve only original authored layers for native placed objects.
static func resolve(rows:Array,catalog:Dictionary)->Array:
	var result:Array=[]
	for row:Dictionary in rows:
		var template:=str(row.get("template",""))
		var record:Dictionary=catalog.get("templates",{}).get(template,{})
		var source:Dictionary=catalog.get("sources",{}).get(str(record.get("source","")),{})
		var p:Variant=row.get("position")
		if source.is_empty() or not p is Array or p.size()!=3:continue
		if not p.all(func(v):return (v is int or v is float) and is_finite(float(v))):continue
		var heading:=float(row.get("heading_radians",0))
		if not row.has("heading_radians") and row.get("quaternion") is Array and row.quaternion.size()==4:
			var q:Array=row.quaternion
			heading=Quaternion(float(q[0]),float(q[1]),float(q[2]),float(q[3])).normalized().get_euler().y
		if not is_finite(heading):continue
		var bounds:Array=source.bounds
		var world_bounds:=Rect2()
		var first:=true
		for corner:Vector2 in [Vector2(bounds[0],bounds[1]),Vector2(bounds[0],bounds[3]),Vector2(bounds[2],bounds[1]),Vector2(bounds[2],bounds[3])]:
			var point:=Vector2(corner.x*cos(heading)+corner.y*sin(heading),-corner.x*sin(heading)+corner.y*cos(heading))+Vector2(p[0],p[2])
			if first:world_bounds=Rect2(point,Vector2.ZERO);first=false
			else:world_bounds=world_bounds.expand(point)
		result.append({"id":str(row.id),"position":p.duplicate(),"heading_radians":heading,"layers":source.layers,"bounds":world_bounds})
	result.sort_custom(func(a,b):return str(a.id)<str(b.id))
	return result
