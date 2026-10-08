extends XRToolsMovementProvider
## Applies native scout modifiers to virtual movement, never tracking or gravity.
@export var order:=12
var state: Dictionary={}
var age:=100.0
var source_speed:=0.0
var source_direction:=Vector2.ZERO
var source_character:=""
func observe(value: Dictionary) -> void: state=value.duplicate(true);age=0
static func terrain_factor(angle: float, uphill: float, negotiation: float) -> float:
	return SwgScoutLocomotion.terrain_factor(angle,uphill,negotiation)
func physics_movement(delta: float, player: XRToolsPlayerBody, disabled: bool) -> bool:
	age+=delta
	player.source_movement_active=false
	var profile:Dictionary=player.feedback.locomotion
	if disabled or (is_instance_valid(player.vehicles) and player.vehicles.seated()):
		source_speed=0;source_direction=Vector2.ZERO
		if disabled and not profile.is_empty():
			player.source_movement_active=true;player.source_movement_velocity=Vector2.ZERO
		return false
	if not profile.is_empty():
		if source_character!=player.feedback.character_id:
			source_character=player.feedback.character_id;source_speed=0;source_direction=Vector2.ZERO
		var input:Vector2=player.ground_control_velocity
		var direct:Node=player.origin_node.get_node_or_null("LeftHand/MovementDirect")
		var input_scale:float=maxf(.001,float(direct.max_speed)) if direct!=null else 1.0
		if input.length_squared()>0:source_direction=input.normalized()
		var support:Dictionary=player.support_state
		var forward:Vector3=-player.camera_node.global_basis.z.slide(Vector3.UP).normalized()
		var environment:Dictionary={"terrain":bool(support.get("terrain",false)),"swimming":bool(support.get("swimming",profile.get("swimming",false))),"below_water":bool(support.get("below_water",false)),"normal_dot_forward":player.ground_vector.dot(forward)}
		var result:Dictionary=SwgScoutLocomotion.source_movement(profile,source_speed,input.length()/input_scale,false,environment,delta)
		player.source_movement_active=true
		source_speed=float(result.speed) if result.get("valid",false) else 0.0
		player.source_movement_velocity=source_direction*source_speed
		player.ground_control_velocity=player.source_movement_velocity
		return false
	source_speed=0;source_direction=Vector2.ZERO
	# Legacy scout-only fixtures remain an explicit offline movement harness.
	# Live snapshots use complete native locomotion above, including BurstRun.
	if disabled or state.is_empty() or age>12: return false
	var input: Vector2=player.ground_control_velocity
	var camera: Basis=player.camera_node.global_basis
	var direction: Vector3=(camera.x*input.x-camera.z*input.y).slide(Vector3.UP).normalized()
	var uphill: Vector3=player.ground_vector.slide(Vector3.UP).normalized()
	var factor:=SwgScoutLocomotion.speed_factor(player.ground_angle if player.on_ground else 0.0,-direction.dot(uphill),float(state.get("slope_fraction",0)),bool(state.get("burst_active",false)),float(state.get("burst_remaining",0)),age)
	player.ground_control_velocity*=factor
	return false
