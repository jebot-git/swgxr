extends RefCounted
## Opposite thumb/index L corners, held in front of the eyes.
const Hands = preload("res://scripts/tracked_hand_input.gd")
const HOLD_SECONDS := 0.8
var elapsed := 0.0
var latched := false

func reset() -> void:
	elapsed = 0.0; latched = false

func interrupt() -> void:
	elapsed = 0.0 # Losing tracking/focus must not rearm a completed frame.

static func optical_hand(optical: Dictionary, space: Transform3D) -> Dictionary:
	var joints: Dictionary = optical.joints
	var index: Vector3 = joints.index_tip - joints.index_proximal
	var thumb: Vector3 = joints.thumb_tip - joints.thumb_proximal
	var chain: float = joints.index_proximal.distance_to(joints.index_intermediate) + joints.index_intermediate.distance_to(joints.index_distal) + joints.index_distal.distance_to(joints.index_tip)
	if index.length() < .055 or thumb.length() < .03 or chain < .01 or index.length()/chain < .8: return {}
	if absf(index.normalized().dot(thumb.normalized())) > .5: return {}
	if joints.ring_tip.distance_to(joints.ring_proximal) > .065: return {}
	var wrist: Transform3D = space * optical.wrist
	return {"position":wrist * joints.index_proximal,"index":wrist.basis * index.normalized(),"thumb":wrist.basis * thumb.normalized()}

static func hand(controller: XRController3D, side: String) -> Dictionary:
	var optical := Hands.tracked_joints(side)
	if not optical.is_empty(): return optical_hand(optical,controller.get_parent().global_transform)
	if not Hands.controller_tracked(controller): return {}
	var state := Hands.controller_state(controller)
	# Runtime-neutral controller approximation: curl the grip fingers, extend
	# index and thumb off their controls, and orient the two grips as L corners.
	if state.grip < .65 or state.trigger > .15 or state.trigger_touch or state.thumb_touch: return {}
	return {"position":controller.global_position,"index":-controller.global_basis.z,"thumb":controller.global_basis.y}

static func frame_pose(head: Transform3D, left: Dictionary, right: Dictionary) -> bool:
	if left.is_empty() or right.is_empty() or not head.is_finite(): return false
	var inverse := head.affine_inverse()
	var l: Vector3 = inverse * left.position
	var r: Vector3 = inverse * right.position
	if not l.is_finite() or not r.is_finite(): return false
	if l.x > -.06 or r.x < .06 or r.x-l.x < .16 or r.x-l.x > .65: return false
	if absf(l.y-r.y) < .10 or absf(l.y-r.y) > .45 or absf(l.y) > .3 or absf(r.y) > .3: return false
	if l.z > -.18 or r.z > -.18 or l.z < -.7 or r.z < -.7 or absf(l.z-r.z) > .16: return false
	var up := head.basis.y * (1.0 if r.y > l.y else -1.0)
	return left.index.dot(up) > .7 and right.index.dot(-up) > .7 and left.thumb.dot(head.basis.x) > .7 and right.thumb.dot(-head.basis.x) > .7

func sample(delta: float, head: Transform3D, left: Dictionary, right: Dictionary, tracked: bool, permitted: bool) -> bool:
	if not tracked or not is_finite(delta) or delta <= 0 or delta > .12:
		interrupt(); return false
	if not frame_pose(head,left,right):
		reset(); return false
	if not permitted:
		interrupt(); return false
	if latched: return false
	elapsed += delta
	if elapsed + .00001 < HOLD_SECONDS: return false
	latched = true
	return true
