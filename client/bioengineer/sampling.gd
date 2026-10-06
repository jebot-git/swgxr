extends RefCounted
## Physical contact and click edges only; Core3 owns the sampling attempt.
const CONTACT_MARGIN := 0.18
var down := {"left":true,"right":true}
var captured := {"left":false,"right":false}

func reset() -> void:
	# Reacquiring tracking with a held trigger must not manufacture a click.
	down={"left":true,"right":true};captured={"left":false,"right":false}

func sample(side: String, trigger: float, tracked: bool, permitted: bool, armed: bool) -> Dictionary:
	if not down.has(side): return {"attempt":false,"capture":false}
	if not tracked or not is_finite(trigger):
		down[side]=true
		return {"attempt":false,"capture":bool(captured[side]) or armed}
	var pressed: bool=bool(down[side])
	if trigger<0.25: pressed=false;captured[side]=false
	elif trigger>=0.65: pressed=true
	var edge: bool=pressed and not down[side]
	down[side]=pressed
	if pressed and armed: captured[side]=true
	return {"attempt":edge and permitted and armed,"capture":armed or bool(captured[side])}

static func touches(pose: Transform3D, bounds: AABB, hand: Vector3) -> bool:
	return hand.is_finite() and bounds.size.length_squared()>0.0001 and bounds.grow(CONTACT_MARGIN).has_point(pose.affine_inverse()*hand)
