extends RefCounted
## Tracking evidence only: head-relative bounds, origin-relative rotations and
## both hands' own travel. Looking, locomotion and virtual turning add no sweep.
var armed:=false
var latched:=false
var capturing:=false
var neutral_time:=0.0
var phase:=""
var age:=0.0
var hold_time:=0.0
var settle_time:=0.0
var side:=0.0
var reference:=Transform3D.IDENTITY
var reference_support:=Vector3.ZERO
var previous_main:=Vector3.INF
var previous_support:=Vector3.INF
var previous_axis:=Vector3.ZERO

func clear()->void:
	armed=false;latched=false;capturing=false;neutral_time=0;phase="";age=0;hold_time=0;settle_time=0;previous_main=Vector3.INF;previous_support=Vector3.INF;previous_axis=Vector3.ZERO

func sample(delta:float,main:Transform3D,support:Transform3D,evidence:Transform3D,support_evidence:Vector3,main_trigger:float,support_trigger:float,permitted:bool,available:Array)->String:
	capturing=false
	if not permitted or not is_finite(delta) or delta<=0 or delta>.1 or not main.is_finite() or not support.is_finite() or not evidence.is_finite() or not support_evidence.is_finite() or not is_finite(main_trigger) or not is_finite(support_trigger) or main_trigger>=.2 or support_trigger>=.2:clear();return ""
	if previous_main.is_finite() and (main.origin.distance_to(previous_main)>.25 or support.origin.distance_to(previous_support)>.25):clear();return ""
	var axis:=-evidence.basis.z.normalized()
	if not previous_axis.is_zero_approx() and axis.dot(previous_axis)<.94:clear();return ""
	previous_main=main.origin;previous_support=support.origin;previous_axis=axis
	var forward:=-main.basis.z.normalized()
	var chest:bool=main.origin.y>-.8 and main.origin.y<-.12 and main.origin.z>-.75 and main.origin.z<.05 and absf(main.origin.x)<.65 and support.origin.distance_to(main.origin)>.12 and support.origin.distance_to(main.origin)<.65 and absf(forward.y)<.35 and forward.dot(Vector3.FORWARD)>.65
	if not chest:clear();return ""
	var roll:=atan2(main.basis.x.y,main.basis.y.y)
	var forward_yaw:=atan2(-forward.x,-forward.z)
	var neutral:bool=absf(roll)<deg_to_rad(15) and absf(forward_yaw)<deg_to_rad(10)
	neutral_time=neutral_time+delta if neutral else 0.
	if latched:
		if neutral_time>=.25:latched=false;armed=true;reference=evidence;reference_support=support_evidence
		return ""
	if not armed:
		if neutral_time>=.25:armed=true;reference=evidence;reference_support=support_evidence
		return ""
	var relative:Vector3=reference.basis.inverse()*axis
	var yaw:=atan2(-relative.x,-relative.z)
	var travel:Vector3=reference.basis.inverse()*(support_evidence-reference_support)
	if phase.is_empty():
		if absf(roll)>deg_to_rad(30) and "tactical_brace" in available:phase="brace";age=0;hold_time=0
		elif absf(yaw)>deg_to_rad(8) and absf(roll)<deg_to_rad(20) and "full_auto_sweep" in available:phase="out";side=signf(yaw);age=0
		else:return ""
	capturing=true;age+=delta
	if age>2.8 or evidence.origin.distance_to(reference.origin)>.22:clear();return ""
	if phase=="brace":
		if absf(yaw)>deg_to_rad(15):clear();return ""
		var canted:bool=absf(roll)>=deg_to_rad(50) and absf(roll)<=deg_to_rad(100)
		hold_time=hold_time+delta if canted else 0.
		if hold_time>=.8:phase="brace_return"
	elif phase=="brace_return":
		if absf(yaw)>deg_to_rad(15):clear();return ""
		if neutral:return finish("tactical_brace",available)
	else:
		if absf(roll)>deg_to_rad(25) or age>2.2 or absf(yaw)>deg_to_rad(38):clear();return ""
		if phase=="out" and yaw*side>=deg_to_rad(14) and forward_yaw*side>=deg_to_rad(10) and travel.x*side<=-.05:phase="reverse"
		elif phase=="reverse" and yaw*side<=-deg_to_rad(14) and forward_yaw*side<=-deg_to_rad(10) and travel.x*side>=.05:phase="return"
		elif phase=="return":
			var settled:bool=absf(yaw)<deg_to_rad(5) and absf(travel.x)<.045 and neutral
			settle_time=settle_time+delta if settled else 0.
			if settle_time>=.12:return finish("full_auto_sweep",available)
	return ""

func finish(id:String,available:Array)->String:
	latched=true;armed=false;phase="";neutral_time=0;capturing=true
	return id if id in available else ""
