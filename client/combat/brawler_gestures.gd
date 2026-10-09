extends RefCounted
## Controller approximation of an open upright meditation hand or two spread fists.
const HOLD:=.8
var candidate:=""
var elapsed:=0.0
var latched:=false
var previous:Dictionary={}
var capturing:=false
func clear()->void:
	candidate="";elapsed=0;latched=false;previous.clear();capturing=false
func sample(delta:float,hands:Dictionary,offhand:String,permitted:bool)->String:
	if not permitted or not is_finite(delta) or delta<=0 or delta>.1:clear();return ""
	for side:String in ["left","right"]:
		var h:Dictionary=hands.get(side,{})
		var p:Vector3=h.get("position",Vector3.INF)
		if not h.get("tracked",false) or not p.is_finite() or not is_finite(float(h.get("grip",NAN))) or not is_finite(float(h.get("trigger",NAN))):clear();return ""
		if previous.has(side) and p.distance_to(previous[side])>.06:
			candidate="";elapsed=0
		previous[side]=p
	var left:Dictionary=hands.left;var right:Dictionary=hands.right
	var off:Dictionary=hands[offhand];var main:Dictionary=hands["left" if offhand=="right" else "right"]
	var next:=""
	var released:bool=float(left.trigger)<.25 and float(right.trigger)<.25
	var p:Vector3=off.position
	if released and off.get("free",false) and float(off.grip)<.25 and float(off.get("upright",0))>.7 and absf(p.x)<.32 and p.y>=-.5 and p.y<=-.12 and p.z>=-.6 and p.z<=-.22 and main.position.y<-.5:
		next="center_of_being"
	elif released and off.get("free",false) and float(left.grip)>.75 and float(right.grip)>.75 and left.position.x<-.45 and left.position.x> -1.2 and right.position.x>.45 and right.position.x<1.2 and absf(left.position.z)<.5 and absf(right.position.z)<.5 and left.position.y>=-.3 and left.position.y<=.2 and right.position.y>=-.3 and right.position.y<=.2:
		next="berserk"
	capturing=not next.is_empty()
	if next.is_empty():candidate="";elapsed=0;latched=false;return ""
	if next!=candidate:candidate=next;elapsed=0
	if latched:return ""
	elapsed+=delta
	if elapsed>=HOLD:latched=true;return next
	return ""
