extends Node
## Opaque desktop overlay plus camera-attached 3D cover/panel for both OpenXR eyes.
## Head tracking stays active; only presentation is covered while entry is gated.
const XR_LOADING_LAYER := 1 << 19
var head: Camera3D
var previous_cull_mask := 0
var isolated := false
var desktop_layer: CanvasLayer
var desktop_title: Label
var desktop_status: Label
var xr_cover: Node3D
var xr_title: Label
var xr_status: Label
var xr_viewport: SubViewport
var active := false
var failed := false
var message := ""
var history: Array[String] = []

func _ready() -> void:
	desktop_layer = CanvasLayer.new()
	desktop_layer.layer = 100
	add_child(desktop_layer)
	var content := make_content()
	desktop_layer.add_child(content)
	desktop_title = content.get_node("Center/Box/Title")
	desktop_status = content.get_node("Center/Box/Status")
	desktop_layer.hide()

func make_content() -> Control:
	var background := ColorRect.new()
	background.color = Color("08121a")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_STOP
	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.add_child(center)
	var box := VBoxContainer.new()
	box.name = "Box"
	box.custom_minimum_size = Vector2(620,180)
	box.add_theme_constant_override("separation",24)
	center.add_child(box)
	var title := Label.new()
	title.name = "Title"
	title.text = "SWG XR"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size",42)
	title.add_theme_font_override("font",preload("res://resources/fonts/Jupiteroid-Bold.ttf"))
	title.add_theme_color_override("font_color",Color("79e3f2"))
	box.add_child(title)
	var status := Label.new()
	status.name = "Status"
	status.text = "Loading…"
	status.custom_minimum_size = Vector2(620,100)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.add_theme_font_size_override("font_size",26)
	status.add_theme_color_override("font_color",Color("dbeaf0"))
	box.add_child(status)
	return background

func attach_head(camera: Camera3D) -> void:
	restore_camera()
	head = camera
	if is_instance_valid(xr_cover): xr_cover.queue_free()
	xr_cover = Node3D.new()
	xr_cover.name = "LoadingCover"
	camera.add_child(xr_cover)
	var shell := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 3.0
	sphere.height = 6.0
	sphere.radial_segments = 16
	sphere.rings = 8
	shell.mesh = sphere
	shell.layers = XR_LOADING_LAYER
	var dark := StandardMaterial3D.new()
	dark.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dark.cull_mode = BaseMaterial3D.CULL_FRONT
	dark.albedo_color = Color("08121a")
	dark.disable_fog = true
	shell.material_override = dark
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	xr_cover.add_child(shell)
	xr_viewport = SubViewport.new()
	xr_viewport.name = "LoadingText"
	xr_viewport.size = Vector2i(1024,512)
	xr_viewport.disable_3d = true
	xr_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	xr_cover.add_child(xr_viewport)
	var content := make_content()
	xr_viewport.add_child(content)
	xr_title = content.get_node("Center/Box/Title")
	xr_status = content.get_node("Center/Box/Status")
	var panel := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(1.5,0.75)
	panel.mesh = quad
	panel.layers = XR_LOADING_LAYER
	panel.position = Vector3(0,0,-1.5)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_texture = xr_viewport.get_texture()
	material.no_depth_test = true
	material.disable_fog = true
	material.render_priority = 127
	panel.material_override = material
	panel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	xr_cover.add_child(panel)
	xr_cover.visible = active
	if active: isolate_camera()
	sync_text()

func begin(text: String) -> void:
	active = true
	failed = false
	desktop_layer.show()
	if is_instance_valid(xr_cover):
		isolate_camera()
		xr_cover.show()
		xr_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	set_status(text)

func set_status(text: String) -> void:
	message = text
	if history.is_empty() or history.back()!=text:
		if history.size()>=32: history.pop_front()
		history.append(text)
	sync_text()

func sync_text() -> void:
	for title in [desktop_title,xr_title]:
		if is_instance_valid(title): title.text = "Loading stopped" if failed else "SWG XR"
	for label in [desktop_status,xr_status]:
		if is_instance_valid(label): label.text = message + ("\n\nPress Menu / Esc to return." if failed else "")

func fail(text: String) -> void:
	begin(text)
	failed = true
	sync_text()

func isolate_camera() -> void:
	if not is_instance_valid(head) or isolated: return
	previous_cull_mask = head.cull_mask
	head.cull_mask = XR_LOADING_LAYER
	isolated = true

func restore_camera() -> void:
	if isolated and is_instance_valid(head): head.cull_mask = previous_cull_mask
	isolated = false

func finish() -> void:
	active = false
	restore_camera()
	desktop_layer.hide()
	if is_instance_valid(xr_cover):
		xr_cover.hide()
		xr_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED

func _exit_tree() -> void:
	restore_camera()
	if is_instance_valid(xr_cover): xr_cover.queue_free()
