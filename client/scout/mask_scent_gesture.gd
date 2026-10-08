extends RefCounted
## Repeated strokes along the opposite rendered forearm. All distances are in
## metres, relative to that arm, so locomotion and turning cannot count as rubs.
const STROKE := 0.085
const CONTACT_RADIUS := 0.12 # Allows controller grips to clear the physical arm.
var arms: Dictionary = {}
var latched := false
var release_time := 0.0

func reset() -> void:
	arms.clear(); latched = false; release_time = 0.0

static func forearm(skeleton: Skeleton3D, side: String) -> Dictionary:
	if not is_instance_valid(skeleton): return {}
	var prefix := "l" if side == "left" else "r"
	var wrist := skeleton.find_bone(prefix + "wrist")
	var elbow := skeleton.find_bone(prefix + "forearm")
	if elbow < 0: elbow = skeleton.find_bone(prefix + "elbow")
	if wrist < 0 or elbow < 0: return {}
	return {"wrist":skeleton.global_transform * skeleton.get_bone_global_pose(wrist).origin,
		"elbow":skeleton.global_transform * skeleton.get_bone_global_pose(elbow).origin}

static func contact(hand: Vector3, arm: Dictionary) -> float:
	if arm.is_empty() or not hand.is_finite(): return INF
	var wrist: Vector3 = arm.wrist
	var axis: Vector3 = arm.elbow - wrist
	var length := axis.length()
	if not wrist.is_finite() or not axis.is_finite() or length < 0.15 or length > 0.6: return INF
	axis /= length
	var along := (hand - wrist).dot(axis)
	# Exclude hand-to-hand rubbing, wrist tapping and reaching past the elbow.
	if along < 0.035 or along > length - 0.015: return INF
	if hand.distance_to(wrist + axis * along) > CONTACT_RADIUS: return INF
	return along

func sample(delta: float, left: Vector3, right: Vector3, left_arm: Dictionary, right_arm: Dictionary, permitted: bool) -> bool:
	if not permitted or delta <= 0 or delta > 0.15:
		arms.clear(); release_time = 0.0
		return false # Tracking loss cannot rearm an already fired gesture.
	var contacts := {"left":contact(right,left_arm), "right":contact(left,right_arm)}
	if is_inf(contacts.left) and is_inf(contacts.right):
		arms.clear(); release_time += delta
		if release_time >= 0.35: latched = false
		return false
	release_time = 0.0
	if latched: return false
	for side: String in contacts:
		var position: float = contacts[side]
		if is_inf(position): arms.erase(side); continue
		if not arms.has(side):
			arms[side] = {"extreme":position,"previous":position,"direction":0,"strokes":0,"time":0.0,"idle":0.0}
			continue
		var arm: Dictionary = arms[side]
		arm.time += delta; arm.idle += delta
		if absf(position - float(arm.previous)) / delta > 3.0 or arm.idle > 1.2:
			arms.erase(side); continue
		arm.previous = position
		var travel: float = position - float(arm.extreme)
		if int(arm.direction) != 0 and travel * int(arm.direction) > 0:
			arm.extreme = position
		elif absf(travel) >= STROKE:
			arm.direction = 1 if travel > 0 else -1
			arm.extreme = position; arm.strokes += 1; arm.idle = 0.0
			if arm.strokes >= 3 and arm.time >= 0.65:
				latched = true; arms.clear(); return true
	return false
