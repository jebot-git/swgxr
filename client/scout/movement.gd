extends XRToolsMovementProvider
## Applies native scout modifiers to virtual movement, never tracking or gravity.
@export var order:=12
var state: Dictionary={}
var age:=100.0
func observe(value: Dictionary) -> void: state=value.duplicate(true);age=0
static func terrain_factor(angle: float, uphill: float, negotiation: float) -> float:
	return SwgScoutLocomotion.terrain_factor(angle,uphill,negotiation)
func physics_movement(delta: float, player: XRToolsPlayerBody, disabled: bool) -> bool:
	age+=delta
	if disabled or state.is_empty() or age>12: return false
	var input: Vector2=player.ground_control_velocity
	var camera: Basis=player.camera_node.global_basis
	var direction: Vector3=(camera.x*input.x-camera.z*input.y).slide(Vector3.UP).normalized()
	var uphill: Vector3=player.ground_vector.slide(Vector3.UP).normalized()
	var factor:=SwgScoutLocomotion.speed_factor(player.ground_angle if player.on_ground else 0.0,-direction.dot(uphill),float(state.get("slope_fraction",0)),bool(state.get("burst_active",false)),float(state.get("burst_remaining",0)),age)
	player.ground_control_velocity*=factor
	return false
