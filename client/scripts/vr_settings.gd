extends RefCounted
## Application preferences; the pinned XR Tools provider remains unmodified.
var path := "user://swgxr_vr.cfg"
var turn_mode := "snap"
var turn_speed_degrees := 90.0
var standing_eye_height := 0.0
var offhand := "left"
var aim_assist := "subtle"

func load_preferences() -> void:
	var config := ConfigFile.new()
	if config.load(path) != OK:
		return
	aim_assist = "off" if str(config.get_value("combat", "aim_assist", "subtle")) == "off" else "subtle"
	set_turn_mode(str(config.get_value("locomotion", "turn_mode", "snap")))
	set_turn_speed(float(config.get_value("locomotion", "turn_speed_degrees", 90.0)))
	standing_eye_height = clampf(float(config.get_value("tracking", "standing_eye_height", 0.0)), 0.0, 2.5)
	offhand = "right" if str(config.get_value("datapad", "offhand", "left")) == "right" else "left"

func save_preferences() -> Error:
	var config := ConfigFile.new()
	config.set_value("combat", "aim_assist", aim_assist)
	config.set_value("locomotion", "turn_mode", turn_mode)
	config.set_value("locomotion", "turn_speed_degrees", turn_speed_degrees)
	config.set_value("tracking", "standing_eye_height", standing_eye_height)
	config.set_value("datapad", "offhand", offhand)
	return config.save(path)

func set_turn_mode(value: String) -> void:
	turn_mode = "smooth" if value == "smooth" else "snap"

func set_turn_speed(value: float) -> void:
	turn_speed_degrees = clampf(value, 30.0, 180.0) if is_finite(value) else 90.0

func apply(rig: XROrigin3D) -> void:
	if not is_instance_valid(rig):
		return
	var turning = rig.get_node("RightHand/MovementTurn")
	turning.turn_mode = turning.TurnMode.SMOOTH if turn_mode == "smooth" else turning.TurnMode.SNAP
	# XR Tools subtracts its fixed 0.1 smooth-turn deadzone without rescaling.
	# Compensate so the UI rate describes a full stick deflection accurately.
	turning.smooth_turn_speed = deg_to_rad(turn_speed_degrees) / 0.9
	turning.step_turn_angle = 30.0
	turning.step_turn_delay = 0.0
	turning._turn_step = 0.0
