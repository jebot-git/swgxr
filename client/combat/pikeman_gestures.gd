extends RefCounted
## Two-handed polearm movement in a fixed starting yaw frame.
var previous:=Vector3.INF
var start:=Vector3.ZERO
var head_start:=Vector3.ZERO
var phase:=""
var age:=0.0
var still_time:=0.0
var jabs:=0
var extended:=false
var latched:=false
var capturing:=false
var circle_last:=0.0
var circle_turn:=0.0
var circle_sign:=0.0
var chord=preload("res://combat/melee_ultimate_input.gd").new()
func clear()->void:
	previous=Vector3.INF;phase="";age=0;still_time=0;jabs=0;extended=false;latched=false;capturing=false;circle_turn=0;circle_sign=0;chord.clear()
func sample(delta:float,p:Vector3,head:Vector3,main:float,support:float,permitted:bool,selected:bool,available:Array)->String:
	capturing=false
	if not permitted or not is_finite(delta) or delta<=0 or delta>.1 or not p.is_finite() or not head.is_finite() or not is_finite(main) or not is_finite(support):clear();return ""
	if previous.is_finite() and p.distance_to(previous)>.35:clear();return ""
	var still:bool=previous.is_finite() and p.distance_to(previous)<.012
	previous=p
	var ultimate:bool=chord.sample(delta,main,support,selected)
	if chord.capturing:
		capturing=true;phase="";jabs=0;still_time=0
		return "whirlwind" if ultimate and "whirlwind" in available else ""
	if main>.25 or support>.25:phase="";jabs=0;still_time=0;latched=false;return ""
	var neutral:bool=absf(p.x)<.5 and p.y>-.55 and p.y<.1 and p.z>-.65 and p.z<-.1
	still_time=still_time+delta if still and neutral else 0.0
	if latched:
		capturing=true
		if still_time>=.2:latched=false;phase="";still_time=0
		return ""
	if phase.is_empty():
		if still_time>=.12:phase="ready";start=p;head_start=head;age=0;jabs=0;extended=false
		return ""
	age+=delta
	if age>2.4 or head.distance_to(head_start)>.15:phase="";still_time=0;return ""
	var radial:=Vector2(p.x,p.z+.35)
	if phase=="ready":
		if p.y>.12 and radial.length()>=.12 and radial.length()<=.45:
			phase="circle";circle_last=radial.angle();circle_turn=0;circle_sign=0;age=0
		elif p.y<-.55 and absf(p.x)>.25:phase="sweep";start=p;age=0
	var move:=p-start
	var result:=""
	if phase=="circle":
		if p.y<.08 or radial.length()<.1 or radial.length()>.5:phase="";still_time=0;return ""
		var turn:=wrapf(radial.angle()-circle_last,-PI,PI);circle_last=radial.angle()
		if absf(turn)>.8:phase="";still_time=0;return ""
		if circle_sign==0:
			circle_turn+=turn
			if absf(circle_turn)>=.2:circle_sign=signf(circle_turn);circle_turn=absf(circle_turn)
		else:
			if turn*circle_sign<-.04:phase="";still_time=0;return ""
			circle_turn+=turn*circle_sign
		if circle_turn>=5.2 and age>=.3:result="overhead_whirl"
	elif phase=="sweep" and move.x*start.x<0 and absf(move.x)>=.55 and absf(move.y)<.2 and absf(move.z)<.3 and p.y<-.4 and age<=1.0:result="sweeping_trip"
	elif phase=="ready":
		if extended:
			if move.z>-.07:extended=false
		elif -move.z>=.2 and absf(move.x)<.15 and absf(move.y)<.15:extended=true;jabs+=1
		if jabs>=2 and age<=1.2:result="driving_jabs"
	if result.is_empty():return ""
	latched=true;phase="";still_time=0;capturing=true
	return result if result in available else ""
