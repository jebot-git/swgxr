extends RefCounted
## Area gestures use closed grips with released triggers. No avatar/HMD animation.
var previous:Dictionary={}
var start:Dictionary={}
var age:=0.0
var volley:Array[String]=[]
var extended:Dictionary={"left":false,"right":false}
var punch_origins:Dictionary={}
var latched:=false
var neutral_time:=0.0
var capturing:=false
var ultimate=preload("res://combat/ultimate_input.gd").new()
func clear()->void:
	previous.clear();start.clear();punch_origins.clear();volley.clear();extended={"left":false,"right":false};age=0;latched=false;neutral_time=0;capturing=false;ultimate.reset()
func sample(delta:float,hands:Dictionary,permitted:bool,available:Array,focus_selected:bool)->String:
	capturing=false
	if not permitted or not is_finite(delta) or delta<=0 or delta>.1:clear();return ""
	for side:String in ["left","right"]:
		var h:Dictionary=hands.get(side,{})
		var p:Vector3=h.get("position",Vector3.INF)
		if not h.get("tracked",false) or not h.get("free",false) or not p.is_finite() or not is_finite(float(h.get("grip",NAN))) or not is_finite(float(h.get("trigger",NAN))):clear();return ""
		if previous.has(side) and p.distance_to(previous[side])>.5:clear();return ""
	var l:Dictionary=hands.left;var r:Dictionary=hands.right
	var fists:bool=l.grip>.75 and r.grip>.75
	var center:Vector3=(l.position+r.position)*.5
	var contact:bool=fists and l.position.distance_to(r.position)<.18 and absf(center.x)<.3 and center.y>-.65 and center.y<-.1 and center.z<-.15 and center.z>-.65
	var chord:Dictionary=ultimate.sample(delta,r.trigger,l.trigger,contact,focus_selected)
	if focus_selected and (contact or chord.reserved):
		capturing=true;start.clear();previous.clear();volley.clear();punch_origins.clear()
		if chord.ultimate and "indomitable_focus" in available:return "indomitable_focus"
		return ""
	if not fists or l.trigger>.25 or r.trigger>.25:
		start.clear();previous.clear();punch_origins.clear();volley.clear();age=0;latched=false;neutral_time=0;return ""
	var still:=true
	for side:String in ["left","right"]:
		var p:Vector3=hands[side].position
		if previous.has(side) and p.distance_to(previous[side])>.012:still=false
		previous[side]=p
	if latched:
		capturing=true
		var guard:bool=absf(l.position.x)<.4 and absf(r.position.x)<.4 and center.z>-.5 and center.z<-.1
		neutral_time=neutral_time+delta if still and guard else 0.0
		if neutral_time>=.2:latched=false;start.clear();previous.clear();punch_origins.clear();volley.clear();age=0;capturing=false
		return ""
	age+=delta
	if start.is_empty() or age>1.2:
		start={"left":l.position,"right":r.position};punch_origins=start.duplicate();extended={"left":false,"right":false};age=0;volley.clear();return ""
	var dl:Vector3=l.position-start.left;var dr:Vector3=r.position-start.right
	# Two hands travelling together takes priority over the one-hand sweep.
	var two:bool=absf(dl.x)>.15 and absf(dr.x)>.15 and dl.x*dr.x>0
	var result:=""
	if two and absf(dl.x)>=.55 and absf(dr.x)>=.55 and absf(dl.y)<.22 and absf(dr.y)<.22 and absf(dl.z)<.25 and absf(dr.z)<.25 and absf((start.left.x+start.right.x)*.5)>.3 and age<=1.0:
		result="tka_half_spin"
	elif not two and age<=.9:
		for side:String in ["left","right"]:
			var move:Vector3=hands[side].position-start[side]
			var other:Vector3=dr if side=="left" else dl
			if absf(move.x)>=.45 and absf(move.y)<.2 and absf(move.z)<.22 and other.length()<.15:result="tka_sweep"
	for side:String in ["left","right"]:
		var p:Vector3=hands[side].position
		var begin:Vector3=punch_origins[side]
		if not extended[side] and p.z>begin.z:punch_origins[side]=p;begin=p
		if extended[side]:
			if p.z>begin.z-.08:extended[side]=false;punch_origins[side]=p
		elif begin.z-p.z>=.22 and absf(p.x-begin.x)<.18 and absf(p.y-begin.y)<.2:
			extended[side]=true
			if volley.is_empty() or volley.back()!=side:volley.append(side)
			else:volley=[side]
	if volley.size()>=3 and age<=1.2:result="tka_volley"
	capturing=two or absf(dl.x)>.15 or absf(dr.x)>.15 or not volley.is_empty() or dl.z<-.1 or dr.z<-.1
	if result.is_empty() or result not in available:return ""
	latched=true;neutral_time=0;capturing=true;return result
