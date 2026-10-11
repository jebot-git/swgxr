extends RefCounted
## Presentation/picking only. Selection and subsystem eligibility come from Core3.
static func vector(value:Array)->Vector3:return Vector3(float(value[0]),float(value[1]),-float(value[2]))
static func intercept(relative:Vector3,velocity:Vector3,speed:float,max_time:float)->Dictionary:
	if speed<=0 or not is_finite(speed) or not relative.is_finite() or not velocity.is_finite():return {}
	var a:=velocity.length_squared()-speed*speed
	var b:=2.0*relative.dot(velocity)
	var c:=relative.length_squared()
	var t:=-1.0
	if absf(a)<.000001:
		if absf(b)>.000001:t=-c/b
	else:
		var discriminant:=b*b-4.0*a*c
		if discriminant>=0:
			var first:=(-b-sqrt(discriminant))/(2.0*a);var second:=(-b+sqrt(discriminant))/(2.0*a)
			if first>0:t=first
			if second>0 and (t<0 or second<t):t=second
	if t<=0 or t>max_time:return {}
	return {"time":t,"offset":velocity*t}
static func cycle(rows:Array,current:String,reverse:=false,hostile_only:=true)->String:
	var ids:Array[String]=[]
	for row:Dictionary in rows:
		if not hostile_only or row.get("hostile",false):ids.append(str(row.id))
	ids.sort()
	if ids.is_empty():return ""
	var index:=ids.find(current)
	return ids[posmod(index+(-1 if reverse else 1),ids.size())] if index>=0 else ids[-1 if reverse else 0]
static func next_component(target:Dictionary)->int:
	var slots:Array[int]=[-1]
	for row:Dictionary in target.get("components",[]):
		if row.get("available",false):slots.append(int(row.slot))
	return slots[posmod(slots.find(int(target.get("component_slot",-1)))+1,slots.size())]
static func pick(rows:Array,origin:Vector3,direction:Vector3,positions:Dictionary,max_angle:=12.0)->String:
	var best:=cos(deg_to_rad(max_angle));var selected:=""
	for row:Dictionary in rows:
		var id:=str(row.id)
		if not positions.has(id):continue
		var offset:Vector3=positions[id]-origin
		if offset.length_squared()<.001:continue
		var dot:=direction.dot(offset.normalized())
		if dot>best:best=dot;selected=id
	return selected
