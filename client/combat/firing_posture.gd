extends RefCounted
## Tracking-derived firing stance; this never drives a camera, body or animation.
## Low HMD height is a posture proxy without full-body tracking.
const STANDING := "standing"
const CROUCHED := "crouched"
const PRONE := "prone"
var standing_eye_height := 1.7
var state := STANDING

func set_standing_eye_height(height: float) -> bool:
	if not is_finite(height) or height < 0.8 or height > 2.5: return false
	standing_eye_height = height
	state = STANDING
	return true

func update_tracked(context: Dictionary) -> String:
	var height := float(context.get("eye_height",NAN))
	if not context.get("tracked",false) or not context.get("grounded",false) or not is_finite(height) or height < 0:
		state = STANDING
		return state
	var ratio := height / standing_eye_height
	# Match the tracked avatar's crouch hysteresis. Add a lower prone band.
	if ratio < 0.38 or (state == PRONE and ratio <= 0.46):
		state = PRONE
	elif ratio < 0.78 or (state != STANDING and ratio <= 0.86):
		state = CROUCHED
	else:
		state = STANDING
	return state

func update_desktop(posture: int, grounded: bool) -> String:
	state = STANDING
	if grounded:
		if posture == 1: state = CROUCHED
		elif posture == 2: state = PRONE
	return state
