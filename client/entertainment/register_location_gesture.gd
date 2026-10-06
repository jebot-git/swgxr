extends RefCounted
## Deliberate continuous tracked standing V-pose. This only requests Core3;
## it never registers a POI or changes learned skills locally.
const HOLD_SECONDS:=10.0
var held_seconds:=0.0
var latched:=false
var progress:=0.0
func reset()->void:
	held_seconds=0;progress=0;latched=false
func interrupt()->void:
	# Loss of focus/tracking cancels progress but cannot rearm a fired hold.
	held_seconds=0;progress=0
func raised_pose(head:Transform3D,left:Transform3D,right:Transform3D)->bool:
	if not head.origin.is_finite() or not left.origin.is_finite() or not right.origin.is_finite():return false
	var lateral:=head.basis.x.slide(Vector3.UP).normalized()
	if lateral.length_squared()<.9:return false
	var forward:=Vector3.UP.cross(lateral)
	var l:=left.origin-head.origin;var r:=right.origin-head.origin
	return l.y>=.08 and r.y>=.08 and l.y<=.85 and r.y<=.85 and l.dot(lateral)<=-.28 and r.dot(lateral)>=.28 and left.origin.distance_to(right.origin)>=.75 and l.length()<=1.2 and r.length()<=1.2 and absf(l.dot(forward))<=.65 and absf(r.dot(forward))<=.65
func sample(delta:float,head:Transform3D,left:Transform3D,right:Transform3D,tracked:bool,standing:bool,allowed:bool)->bool:
	if not tracked or not is_finite(delta) or delta<=0 or delta>.12:
		interrupt();return false
	var raised:=raised_pose(head,left,right)
	if not raised:
		reset();return false
	if not standing or not allowed:
		interrupt();return false
	if latched:return false
	held_seconds+=delta;progress=clampf(held_seconds/HOLD_SECONDS,0,1)
	if held_seconds+0.00001<HOLD_SECONDS:return false
	latched=true;progress=1
	return true
