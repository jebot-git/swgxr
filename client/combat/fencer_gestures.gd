extends RefCounted
var previous:=Vector3.INF
var start:=Vector3.ZERO
var head_start:=Vector3.ZERO
var phase:=""
var age:=0.0
var still_time:=0.0
var guard_time:=0.0
var jabs:=0
var extended:=false
var latched:=false
var capturing:=false
var chord=preload("res://combat/melee_ultimate_input.gd").new()
func clear()->void:
	previous=Vector3.INF;phase="";age=0;still_time=0;guard_time=0;jabs=0;extended=false;latched=false;capturing=false;chord.clear()
func sample(delta:float,p:Vector3,head:Vector3,axis:Vector3,main:float,support:float,permitted:bool,supported:bool,selected:bool,available:Array)->String:
	capturing=false
	if not permitted or not is_finite(delta) or delta<=0 or delta>.1 or not p.is_finite() or not head.is_finite() or not axis.is_finite() or not is_finite(main) or not is_finite(support):clear();return ""
	if previous.is_finite() and p.distance_to(previous)>.35:clear();return ""
	var still:bool=previous.is_finite() and p.distance_to(previous)<.012
	previous=p
	var ultimate:bool=chord.sample(delta,main,support,supported and selected)
	if chord.capturing:
		capturing=true;phase="";jabs=0;still_time=0
		return "flawless_assault" if ultimate and "flawless_assault" in available else ""
	if main>.25 or support>.25:phase="";jabs=0;still_time=0;latched=false;return ""
	var guard:bool=absf(p.x)<.55 and p.y>-.7 and p.y<.2 and p.z>-.8 and p.z<-.1 and absf(axis.z)<.65
	var neutral:bool=absf(p.x)<.55 and p.y>-.65 and p.y<.15 and p.z>-.6 and p.z<-.1
	still_time=still_time+delta if still and neutral else 0.0
	guard_time=guard_time+delta if still and guard else 0.0
	if latched:
		capturing=true
		if still_time>=.2:latched=false;phase="";still_time=0
		return ""
	if phase.is_empty():
		if still_time>=.12:phase="ready";start=p;head_start=head;age=0;jabs=0;extended=false
		return ""
	age+=delta
	if age>1.6 or head.distance_to(head_start)>.15:phase="";still_time=0;return ""
	if phase=="guard" and (absf(axis.z)>.75 or absf(p.x-start.x)>.18 or absf(p.y-start.y)>.18):phase="ready";start=p;age=0
	if phase=="ready" and guard_time>=.25:phase="guard";start=p;age=0
	if phase=="ready" and absf(p.x)>.3 and p.y>.05:phase="slash";start=p;age=0
	var move:Vector3=p-start
	var result:=""
	if phase=="guard" and -move.z>=.16 and absf(move.x)<.15 and absf(move.y)<.15 and age<=.7:result="guard_bash"
	elif phase=="slash" and move.x*start.x<0 and absf(move.x)>=.35 and -move.y>=.35 and absf(move.z)<.25 and absf(move.x)/maxf(.001,-move.y)>.5 and absf(move.x)/maxf(.001,-move.y)<2 and age<=.8:result="raking_slash"
	elif phase=="ready" and absf(axis.z)>.75:
		if extended:
			if move.z>-.07:extended=false
		elif -move.z>=.2 and absf(move.x)<.15 and absf(move.y)<.15:extended=true;jabs+=1
		if jabs>=2 and age<=1.2:result="probing_jabs"
	if result.is_empty():return ""
	latched=true;phase="";still_time=0;capturing=true
	return result if result in available else ""
