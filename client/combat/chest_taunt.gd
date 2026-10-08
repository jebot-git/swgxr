extends RefCounted
## Two deliberate inward chest taps. Positions are relative to head yaw.
const WINDOW:=1.25
const RELEASE_Z:=-.36
const CONTACT_Z:=-.23
var clock:=0.0
var last_beat:=-10.0
var beats:=0
var refractory:=0.0
var armed:Dictionary={}
var previous:Dictionary={}
var capturing:=false
func clear()->void:
	armed.clear();previous.clear();beats=0;capturing=false
static func chest(p:Vector3)->bool:
	return p.is_finite() and absf(p.x)<=.32 and p.y>=-.68 and p.y<=-.23 and p.z>=-.65 and p.z<=.02
func sample(delta:float,hands:Dictionary,permitted:bool)->String:
	if not is_finite(delta) or delta<=0 or delta>.1 or not permitted:clear();return ""
	clock+=delta;refractory=maxf(0,refractory-delta)
	if clock-last_beat>WINDOW:beats=0
	capturing=beats>0
	var hit:=""
	for side:String in ["left","right"]:
		var h:Dictionary=hands.get(side,{})
		if hands.has(side) and previous.has(side) and not h.get("tracked",false):
			clear();return ""
		var p:Vector3=h.get("position",Vector3.INF)
		# Grip closes the fist; trigger remains available for actual punches.
		if not h.get("free",false) or not h.get("tracked",false) or float(h.get("grip",0))<.55 or float(h.get("trigger",0))>=.5 or not chest(p):
			armed.erase(side);previous.erase(side);continue
		var old:Vector3=previous.get(side,p);previous[side]=p
		if p.z<=RELEASE_Z:armed[side]=true
		if refractory<=0 and hit.is_empty() and armed.get(side,false) and p.z>=CONTACT_Z and old.z<CONTACT_Z and (p.z-old.z)/delta>=.35:
			armed[side]=false;last_beat=clock;beats+=1;capturing=true
			# Simultaneous hands count once, never a two-beat gesture in one frame.
			hit=side
	if beats>=2:
		clear();refractory=.8;capturing=true;return hit
	if hands.is_empty() or previous.is_empty():clear()
	return ""
