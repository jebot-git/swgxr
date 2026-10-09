extends RefCounted
## Head-relative evidence only; tracked hands and head are never animated.
var capturing:=false
var phase:=""
var elapsed:=0.
var dwell:=0.
var taps:=0
var tap_ready:=false
var previous:=Vector3.INF
var previous_main:=Vector3.INF
var previous_head:=Vector3.INF
var refractory:=0.
func clear()->void:
	capturing=false;phase="";elapsed=0;dwell=0;taps=0;tap_ready=false;previous=Vector3.INF;previous_main=Vector3.INF;previous_head=Vector3.INF
func sample(delta:float,main:Transform3D,support:Transform3D,head_position:Vector3,main_trigger:float,support_trigger:float,main_grip:float,support_grip:float,supported:bool,permitted:bool,available:Array)->String:
	capturing=false
	if not permitted or not is_finite(delta) or delta<=0 or delta>.1 or not main.is_finite() or not support.is_finite() or not head_position.is_finite() or not is_finite(main_grip) or not is_finite(support_grip) or not is_finite(main_trigger) or not is_finite(support_trigger) or main_grip<.65 or main_trigger>=.2 or support_trigger>=.2:clear();return ""
	refractory=maxf(0,refractory-delta)
	var p:=support.origin;var gun:=main.origin;var axis:=-main.basis.z.normalized()
	if previous.is_finite() and (p.distance_to(previous)>.17 or gun.distance_to(previous_main)>.14 or head_position.distance_to(previous_head)>.12):clear();return ""
	var old:=previous;var old_main:=previous_main;previous=p;previous_main=gun;previous_head=head_position
	elapsed+=delta
	if elapsed>2.2:clear();return ""
	var forward:bool=axis.z<-.75 and absf(axis.x)<.45
	# Open-palm offhand taps explicitly exclude Brawler's clenched-fist Taunt.
	var chest:bool=absf(p.x)<.22 and p.y>-.52 and p.y<-.23 and p.z>-.65 and p.z<.03
	if "duelist_stance" in available and not supported and support_grip<.25 and chest and forward and absf(axis.y)<.4 and gun.z<-.22:
		if phase not in ["","taps"]:clear();return ""
		phase="taps"
		if taps==0:elapsed=0
		if p.z<-.36:tap_ready=true
		if refractory<=0 and tap_ready and old.is_finite() and old.z<-.23 and p.z>=-.23 and ((p-old)-(gun-old_main)).z/delta>=.3:
			tap_ready=false;taps+=1;capturing=true
		if taps>0:capturing=true
		if taps>=2:clear();refractory=.8;capturing=true;return "duelist_stance"
		return ""
	if phase=="taps":clear();return ""
	if "underhand_shot" not in available or not supported or support_grip<.65 or absf(axis.x)>.35 or axis.z>-.65:clear();return ""
	if phase.is_empty():
		if gun.y<-.58 and gun.y>-.95 and gun.z<-.18 and axis.y<-.20 and axis.y>-.65:
			dwell+=delta;capturing=true
			if dwell>=.2:phase="arc";elapsed=0
		else:dwell=0;elapsed=0
	elif phase=="arc":
		capturing=true
		if axis.y>.38 and gun.y>-.72:phase="aim"
	elif phase=="aim":
		capturing=true
		if forward and absf(axis.y)<.16 and gun.y>-.65 and elapsed>=.25:clear();capturing=true;return "underhand_shot"
	return ""
