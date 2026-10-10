extends RefCounted
## ClientAsteroidManager uses distance to the field edge and an authored prefix.
static func distance_to_field(field:Dictionary,position:Vector3)->float:
	var distance:float
	if int(field.Type)==1:
		distance=position.distance_to(Vector3(field.CenterLocationX,field.CenterLocationY,-field.CenterLocationZ))
	else:
		distance=8000.0
		var points:Array[Vector3]=[]
		for point:String in str(field.SplineControlPoints).split(":"):
			var xyz:=point.split(",");xyz.resize(3)
			points.append(Vector3(float(xyz[0]),float(xyz[1]),-float(xyz[2])))
		for i in range(points.size()-1):
			var segment:=points[i+1]-points[i];var t:=clampf((position-points[i]).dot(segment)/maxf(segment.length_squared(),.000001),0,1)
			distance=minf(distance,position.distance_to(points[i]+segment*t))
	return maxf(0,distance-float(field.Radius))
static func fraction(field:Dictionary,position:Vector3)->float:
	var distance:=distance_to_field(field,position)
	var near:=float(field.ViewAllDistance);var far:=float(field.MaxViewableDistance)
	if distance<=near:return 1
	if distance>=far:return 0
	return 1-(distance-near)/maxf(.001,far-near)
static func prefix_count(indices:PackedInt32Array,limit:int)->int:
	# Mesh groups preserve their relative positions in the original field order.
	var low:=0;var high:=indices.size()
	while low<high:
		var mid:=int((low+high)/2)
		if indices[mid]<limit:low=mid+1
		else:high=mid
	return low
