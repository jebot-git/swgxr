extends RefCounted
## Controller-safe clap: observed separation, two converging hands and inward
## palms. Works from tracked poses even while an instrument constrains visuals.
var armed := false
var previous_distance := 0.0
var start_left := Vector3.ZERO
var start_right := Vector3.ZERO
var elapsed := 0.0
var recovery := 0.0

func reset() -> void:
	armed=false; elapsed=0.0; previous_distance=0.0; recovery=0.0

func sample(delta: float, head: Transform3D, left: Transform3D, right: Transform3D, permitted: bool) -> bool:
	recovery=maxf(0.0,recovery-maxf(0.0,delta))
	if not permitted or not is_finite(delta) or delta<=0 or delta>0.15:
		armed=false; return false
	var inverse:=head.affine_inverse()
	var l:=inverse*left.origin; var r:=inverse*right.origin
	var distance:=l.distance_to(r)
	if not l.is_finite() or not r.is_finite(): armed=false; return false
	# A clap in front of the torso, not behind the back or overhead.
	if l.y>0.15 or r.y>0.15 or l.y< -0.85 or r.y< -0.85 or l.z> -0.08 or r.z> -0.08:
		armed=false; return false
	if distance>=0.32:
		armed=true; start_left=l; start_right=r; elapsed=0.0; previous_distance=distance
		return false
	if not armed: return false
	elapsed+=delta
	var closing: float=(previous_distance-distance)/delta
	previous_distance=distance
	if elapsed>1.0 or absf(closing)>6.0: armed=false; return false
	if distance>0.16: return false
	armed=false # Holding together and contact jitter never repeat a flourish.
	var across: Vector3=(start_right-start_left).normalized()
	var both_moved: bool=(l-start_left).dot(across)>=0.04 and (start_right-r).dot(across)>=0.04
	var direction: Vector3=(right.origin-left.origin).normalized()
	var palms_in: bool=left.basis.x.normalized().dot(direction)>0.4 and (-right.basis.x.normalized()).dot(-direction)>0.4
	if closing<0.45 or not both_moved or not palms_in or recovery>0: return false
	recovery=0.65
	return true
