extends RefCounted
## A wrapping arc around a limb, distinct from Mask Scent's lengthwise strokes.
var target := ""
var previous := Vector3.ZERO
var axis := Vector3.ZERO
var sweep := 0.0
var elapsed := 0.0
var direction := 0
var latched := false
func reset() -> void:
	target=""; previous=Vector3.ZERO; sweep=0; elapsed=0; direction=0; latched=false
func sample(delta: float, key: String, hand: Vector3, wrist: Vector3, elbow: Vector3, permitted: bool) -> bool:
	if not permitted or delta<=0 or delta>0.15:
		target=""; sweep=0; elapsed=0; return false
	var along := elbow-wrist
	var length := along.length()
	if not hand.is_finite() or not along.is_finite() or length<.15: reset(); return false
	along/=length
	var offset:=hand-wrist
	var height:=offset.dot(along)
	var radial:=offset-along*height
	if key.is_empty() or height<.02 or height>length+.04 or radial.length()<.065 or radial.length()>.30:
		reset(); return false
	var point:=radial.normalized()
	if target!=key:
		target=key; previous=point; axis=along; sweep=0; elapsed=0; direction=0
		return false
	if latched: return false
	elapsed+=delta
	var angle:=atan2(along.dot(previous.cross(point)),previous.dot(point))
	previous=point
	if axis.dot(along)<.85 or absf(angle)>delta*12 or elapsed>3:
		target=""; sweep=0; elapsed=0; return false
	axis=along
	if absf(angle)<.008:return false
	var sign_value:=1 if angle>0 else -1
	if direction!=0 and sign_value!=direction:sweep=maxf(0,sweep-absf(angle));return false
	direction=sign_value;sweep+=absf(angle)
	if sweep>=TAU*.8 and elapsed>=.6:
		latched=true;return true
	return false
