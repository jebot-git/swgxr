extends CanvasLayer
## Mono desktop observer. Its viewport never becomes an XR render target.
## Main owns the separate XR viewport and keeps the headset camera current there.
@export var resolution := Vector2i(960, 540)
@export_range(1, 30) var frame_rate := 30
@export_range(1.0, 6.0) var follow_distance := 3.2
@export var orbit_yaw := 0.0
@export var enabled := true:
	set(value):
		enabled = value
		visible = value
		if is_instance_valid(viewport):
			viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
var viewport: SubViewport
var camera: Camera3D
var display: TextureRect
var rig: XROrigin3D
var body: CharacterBody3D
var head: XRCamera3D
var render_requests := 0
var collision_limited := false
var elapsed := 0.0
var positioned := false
var camera_radius := 0.14
var probe := SphereShape3D.new()

func configure(origin: XROrigin3D, player: CharacterBody3D) -> bool:
	if not is_inside_tree() or not is_instance_valid(origin) or not is_instance_valid(player):
		return false
	rig = origin
	body = player
	head = rig.get_node_or_null("XRCamera3D")
	if head == null:
		return false
	layer = -10
	viewport = SubViewport.new()
	viewport.name = "SpectatorViewport"
	viewport.size = Vector2i(clampi(resolution.x, 320, 1280), clampi(resolution.y, 180, 720))
	viewport.world_3d = body.get_world_3d()
	viewport.use_xr = false
	viewport.audio_listener_enable_3d = false
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	viewport.positional_shadow_atlas_size = 0
	viewport.gui_disable_input = true
	add_child(viewport)
	camera = Camera3D.new()
	camera.name = "SpectatorCamera"
	camera.cull_mask = 3 # Full original body and observer-only head/hair.
	camera.near = 0.05
	camera.far = 20000.0
	camera.fov = 55
	viewport.add_child(camera)
	camera.make_current()
	var backdrop := ColorRect.new()
	backdrop.color = Color.BLACK
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	display = TextureRect.new()
	display.name = "DesktopMirror"
	display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	display.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	display.texture = viewport.get_texture()
	display.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(display)
	probe.radius = camera_radius
	visible = enabled
	process_physics_priority = 200
	return true

func _physics_process(delta: float) -> void:
	if enabled and is_instance_valid(body) and is_instance_valid(head):
		update_camera(delta)

func update_camera(delta: float) -> void:
	var forward := -head.global_basis.z
	forward.y = 0
	if forward.length_squared() < 0.01:
		forward = -rig.global_basis.z
	forward = forward.normalized().rotated(Vector3.UP, orbit_yaw)
	var height := clampf(head.global_position.y - body.global_position.y, 0.5, 2.7)
	var focus := Vector3(head.global_position.x, body.global_position.y + height * 0.60, head.global_position.z)
	var desired := focus - forward * clampf(follow_distance, 1.0, 6.0) + Vector3.UP * 0.45
	var target := camera.global_position.lerp(desired, 1.0 - exp(-8.0 * maxf(delta, 0.0))) if positioned else desired
	var motion := target - focus
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = probe
	query.transform = Transform3D(Basis.IDENTITY, focus)
	query.motion = motion
	query.collision_mask = body.collision_mask
	query.exclude = [body.get_rid()]
	var fractions := body.get_world_3d().direct_space_state.cast_motion(query)
	var fraction := float(fractions[0]) if fractions.size() == 2 else 0.0
	collision_limited = fraction < 1.0
	if collision_limited and motion.length() > 0.001:
		target = focus + motion.normalized() * maxf(0.0, motion.length() * fraction - 0.04)
	camera.global_position = target
	if target.distance_squared_to(focus) > 0.00001:
		camera.look_at(focus, Vector3.UP)
	positioned = true

func _process(delta: float) -> void:
	request_render(delta)

func request_render(delta: float) -> void:
	if not enabled or not is_instance_valid(viewport):
		return
	elapsed += maxf(delta, 0.0)
	var interval := 1.0 / clampi(frame_rate, 1, 30)
	if elapsed + 0.000001 >= interval:
		# Never queue catch-up renders after a stall.
		elapsed = fmod(elapsed, interval)
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		render_requests += 1
