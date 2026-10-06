extends RefCounted
const Hands = preload("res://scripts/tracked_hand_input.gd")
var join_time := 0.0
var join_latched := false

func reset() -> void:
	join_time = 0
	join_latched = false

func thumbs_up(controller: XRController3D, side: String) -> bool:
	var optical: Dictionary = Hands.tracked_joints(side)
	if not optical.is_empty():
		var joints: Dictionary = optical.joints
		var extension: Vector3 = joints.thumb_tip - joints.thumb_proximal
		var wrist: Transform3D = optical.wrist
		# Thumb must extend upward, while index/ring fingertips curl toward palm.
		return extension.length() > 0.035 and (controller.get_parent().global_basis * wrist.basis * extension.normalized()).dot(Vector3.UP) > 0.55 and joints.index_tip.distance_to(joints.index_proximal) < 0.07 and joints.ring_tip.distance_to(joints.ring_proximal) < 0.065
	if not Hands.controller_tracked(controller): return false
	var state := Hands.controller_state(controller)
	# Controller approximation: curled fingers, released capacitive thumb and
	# an upright grip. Both hands must hold this deliberately for 0.7 seconds.
	return state.grip > 0.75 and state.trigger > 0.7 and not state.thumb_touch and controller.global_basis.y.dot(Vector3.UP) > 0.65

func join_sample(delta: float, inside: bool, left: bool, right: bool, tracked: bool) -> bool:
	if not tracked or not inside or not left or not right or not is_finite(delta) or delta <= 0 or delta > 0.12:
		reset()
		return false
	join_time += delta
	if join_time >= 0.7 and not join_latched:
		join_latched = true
		return true
	return false

func dance_hands(main: XRController3D, off: XRController3D) -> Dictionary:
	var result := {}
	for pair in [["main",main],["off",off]]:
		var controller: XRController3D = pair[1]
		var side := "left" if str(controller.tracker).contains("left") else "right"
		var optical := Hands.tracked_joints(side)
		var opened := false
		var basis := controller.global_basis
		if not optical.is_empty():
			opened = true
			for finger in ["index","ring"]:
				var joints: Dictionary = optical.joints
				var chain: float = joints[finger+"_proximal"].distance_to(joints[finger+"_intermediate"]) + joints[finger+"_intermediate"].distance_to(joints[finger+"_distal"]) + joints[finger+"_distal"].distance_to(joints[finger+"_tip"])
				opened = opened and chain > 0.01 and joints[finger+"_proximal"].distance_to(joints[finger+"_tip"]) / chain > 0.85
			basis = controller.get_parent().global_basis * optical.grip.basis
		else:
			var state := Hands.controller_state(controller)
			opened = Hands.controller_tracked(controller) and state.grip < 0.25 and state.trigger < 0.25
		var palm := basis.x * (1.0 if side == "left" else -1.0)
		result[str(pair[0])+"_open"] = opened
		result[str(pair[0])+"_down"] = palm.normalized().dot(Vector3.DOWN) > 0.55
	return result
