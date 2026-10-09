extends Node3D
## Original command icons on a small, translucent radial selector.
var panel: Node3D
var badge: Sprite3D
var halo: Sprite3D
var status: Label3D
var icons: Dictionary = {}
var entries: Array = []
var menu_open := false
var neutral_seen := false
var all_entries: Array = []
var page := 0
var follow_hand: Node3D
var follow_head: Node3D

func _ready() -> void:
	RenderingServer.frame_pre_draw.connect(follow_controller)
	panel = Node3D.new()
	add_child(panel)
	panel.visible = false
	badge = Sprite3D.new()
	badge.pixel_size = 0.003
	badge.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	badge.no_depth_test = false
	add_child(badge)
	halo = Sprite3D.new()
	halo.pixel_size = 0.0038
	halo.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	halo.modulate = Color(0.2, 1.0, 1.0, 0.22)
	# A translucent enlarged copy gives a visible halo without requiring a
	# fullscreen bloom pass in the VR environment.
	add_child(halo)
	halo.visible = false
	status = label("", Vector3.ZERO)
	add_child(status)
	badge.visible = false
	status.visible = false

func label(text: String, offset: Vector3) -> Label3D:
	var item := Label3D.new(); item.font = preload("res://resources/fonts/Jupiteroid-Regular.ttf")
	item.text = text
	item.position = offset
	item.font_size = 24
	item.pixel_size = 0.0006
	item.modulate = Color(0.59, 0.96, 0.99, 0.8)
	item.outline_size = 2
	return item

func texture(command: String) -> Texture2D:
	if not icons.has(command):
		var path := ProjectSettings.globalize_path("res://../runtime/assets/combat/abilities/" + command + ".png")
		if not FileAccess.file_exists(path): path = ProjectSettings.globalize_path("res://../runtime/assets/entertainment/" + command + ".png")
		var image := Image.load_from_file(path) if FileAccess.file_exists(path) else null
		icons[command] = ImageTexture.create_from_image(image) if image != null else null
	return icons[command]

func open_on_hand(abilities: Array, hand: Node3D, head: Node3D) -> void:
	follow_hand=hand;follow_head=head
	open(abilities,hand.global_transform)
	follow_controller()

func follow_controller() -> void:
	if not menu_open or not is_instance_valid(follow_hand) or not is_instance_valid(follow_head): return
	var point:=follow_hand.global_position+Vector3.UP*0.16
	var facing: Vector3=(follow_head.global_position-point).normalized()
	if absf(facing.dot(Vector3.UP))>0.98: facing=follow_head.global_basis.z
	var right:=Vector3.UP.cross(facing).normalized()
	panel.global_transform=Transform3D(Basis(right,facing.cross(right),facing),point)

func _exit_tree() -> void:
	if RenderingServer.frame_pre_draw.is_connected(follow_controller): RenderingServer.frame_pre_draw.disconnect(follow_controller)

func open(abilities: Array, pose: Transform3D) -> void:
	all_entries = abilities.duplicate(true)
	page = 0
	show_page(pose)

func show_page(pose: Transform3D) -> void:
	close()
	entries = all_entries.slice(page * 5, page * 5 + 5) if all_entries.size() > 6 else all_entries.duplicate()
	if all_entries.size() > 6: entries.append({"id":"__page", "label":"More · %d/%d" % [page+1, ceili(all_entries.size()/5.0)], "source_command":"startband"})
	menu_open = true
	neutral_seen = false
	for child in panel.get_children(): child.free()
	panel.global_transform = pose
	panel.visible = true
	var ring := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.108
	mesh.outer_radius = 0.112
	mesh.rings = 48
	mesh.ring_segments = 8
	ring.mesh = mesh
	ring.rotation.x = PI / 2
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.1, 0.9, 1, 0.3)
	ring.material_override = material
	panel.add_child(ring)
	panel.add_child(label("No eligible abilities" if entries.is_empty() else "Select ability", Vector3(0, -0.16, 0)))
	for index in range(entries.size()):
		var angle := TAU * index / entries.size()
		var point := Vector3(sin(angle), cos(angle), 0) * 0.075
		var icon := Sprite3D.new()
		# Some native options (notably pet command training) have text but no
		# original command icon. Keep the complete selectable page in that case.
		icon.texture = texture(str(entries[index].get("source_command", "")))
		icon.pixel_size = 0.0025
		icon.position = point
		icon.modulate = Color(0.59, 0.96, 0.99, 0.8)
		panel.add_child(icon)
		panel.add_child(label(str(entries[index].label), point + Vector3(0, -0.044, 0)))

func close() -> void:
	menu_open = false
	if is_instance_valid(panel): panel.visible = false

func sample_stick(stick: Vector2) -> String:
	if not menu_open or not stick.is_finite(): return ""
	if stick.length() < 0.25: neutral_seen = true
	if not neutral_seen or stick.length() < 0.6 or entries.is_empty(): return ""
	var angle := fposmod(atan2(stick.x, stick.y), TAU)
	var index := int(round(angle / TAU * entries.size())) % entries.size()
	var id := str(entries[index].id)
	if id == "__page":
		page = (page+1) % ceili(all_entries.size()/5.0)
		show_page(panel.global_transform)
		return ""
	close()
	return id

func update_badge(ability: Dictionary, primed: bool, remaining: float, position: Vector3, enabled: bool, message := "") -> void:
	badge.visible = enabled and not ability.is_empty()
	halo.visible = badge.visible and primed
	status.visible = badge.visible
	if not badge.visible: return
	badge.texture = texture(str(ability.get("source_command", "")))
	halo.texture = badge.texture
	badge.global_position = position
	halo.global_position = position
	badge.modulate = Color(1.8, 3.0, 3.0, 1) if primed else Color(0.59, 0.96, 0.99, 0.5 if remaining > 0 else 0.85)
	status.global_position = position + Vector3.DOWN * 0.045
	status.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	status.text = "%.1fs" % remaining if remaining > 0 else ("Primed" if primed else message)
