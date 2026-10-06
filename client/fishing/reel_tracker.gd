extends RefCounted
# Adapted from jebot-git/raifslop a2912df; see server/FISHING_PROTOCOL.md.
## Measures the off-hand in the rod's local YZ crank plane.
## Regrabs reset the sample; discontinuities never produce free line retrieval.
var engaged := false
var previous_angle := 0.0
var angle := 0.0
var angular_delta := 0.0
func sample(local_hand: Vector3, grip: bool, delta: float, small_crank := false) -> float:
	angular_delta = 0.0
	var radial := Vector2(local_hand.y, local_hand.z)
	# Acquiring the handle requires proximity; once held, allow natural wrist drift.
	var valid := grip and absf(local_hand.x) < (.35 if engaged else .18) and radial.length() > (.012 if small_crank else .035) and radial.length() < (.4 if engaged else .13 if small_crank else .22)
	if not valid:
		engaged = false
		return 0.0
	var current := atan2(radial.y, radial.x)
	if not engaged:
		previous_angle = current
		engaged = true
		return 0.0
	var movement := wrapf(current - previous_angle, -PI, PI)
	previous_angle = current
	if delta <= 0.0 or absf(movement) > minf(1.2, 18.0 * delta):
		return 0.0
	angle += movement
	angular_delta = movement
	return clampf(absf(movement) / TAU / delta, 0.0, 2.0)
