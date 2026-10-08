extends Control

signal cursor_selected(position: Vector3)
var map_data: Dictionary = {}
var texture: Texture2D
var icon_textures: Dictionary = {}
var world_bounds := Rect2(-8192, -8192, 16384, 16384)
var center := Vector2.ZERO
var zoom := 1.0
var player := Vector3.ZERO
var cursor := Vector3.ZERO
var has_cursor := false
var landmarks: Array = []
var registered_locations:Array=[]
var waypoints: Array = []
var source_services: Array = []
var native_services: Array = []
var service_points: Array = []
var filters: Dictionary={"city":true,"poi":true,"bazaar":true,"mission":true,"bank":true,"crafting":true,"travel":true,"trainer":true}
const SERVICE_KINDS=["bazaar","mission","bank","crafting","travel","trainer","underworld"]
var dragging := false
var drag_distance := 0.0
var top_positive_z := true
var right_positive_x := true

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	custom_minimum_size = Vector2(300, 260)
	focus_mode = Control.FOCUS_ALL
	resized.connect(queue_redraw)

func configure(data: Dictionary, directory: String) -> void:
	map_data = data
	var bounds: Array = data.get("world_bounds", [-8192, -8192, 8192, 8192])
	world_bounds = Rect2(float(bounds[0]), float(bounds[1]), float(bounds[2])-float(bounds[0]), float(bounds[3])-float(bounds[1]))
	center = world_bounds.get_center()
	landmarks = data.get("landmarks", [])
	top_positive_z = str(data.get("image_top", "+Z")).contains("+Z") or str(data.get("image_top", "north")).to_lower() == "north"
	right_positive_x = not str(data.get("image_right", "+X")).contains("-X")
	texture = null
	var path := directory.path_join(str(data.get("texture", "")))
	if FileAccess.file_exists(path):
		var image := Image.load_from_file(path)
		if image != null: texture = ImageTexture.create_from_image(image)
	icon_textures.clear()
	for key in data.get("icons",{}):
		var icon_path := directory.path_join(str(data.icons[key].get("texture","")))
		if FileAccess.file_exists(icon_path):
			var icon_image := Image.load_from_file(icon_path)
			if icon_image != null: icon_textures[key] = ImageTexture.create_from_image(icon_image)
	load_service_references(str(data.get("service_directory","res://../runtime/assets/services")))
	queue_redraw()

func set_player_position(value: Vector3) -> void:
	player = value
	queue_redraw()

func pixels_per_meter() -> float:
	return minf(size.x / world_bounds.size.x, size.y / world_bounds.size.y) * zoom

func world_to_screen(value: Vector3) -> Vector2:
	var delta := Vector2(value.x, value.z) - center
	return size * 0.5 + Vector2(delta.x * (1 if right_positive_x else -1), delta.y * (-1 if top_positive_z else 1)) * pixels_per_meter()

func screen_to_world(value: Vector2) -> Vector3:
	var delta := (value-size*0.5) / maxf(pixels_per_meter(), 0.00001)
	var point := center + Vector2(delta.x * (1 if right_positive_x else -1), delta.y * (-1 if top_positive_z else 1))
	return Vector3(clampf(point.x, world_bounds.position.x, world_bounds.end.x), 0, clampf(point.y, world_bounds.position.y, world_bounds.end.y))

func change_zoom(factor: float, anchor: Vector2) -> void:
	var before := screen_to_world(anchor)
	zoom = clampf(zoom*factor, 1, 32)
	var after := screen_to_world(anchor)
	center += Vector2(before.x-after.x, before.z-after.z)
	queue_redraw()

func center_on_player() -> void:
	center = Vector2(player.x, player.z)
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed: change_zoom(1.25, event.position)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed: change_zoom(0.8, event.position)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			dragging = event.pressed
			if event.pressed: drag_distance = 0
			elif drag_distance < 8:
				cursor = screen_to_world(event.position)
				has_cursor = true
				cursor_selected.emit(cursor)
				queue_redraw()
		accept_event()
	elif event is InputEventMouseMotion and dragging:
		drag_distance += event.relative.length()
		center -= Vector2(event.relative.x*(1 if right_positive_x else -1), event.relative.y*(-1 if top_positive_z else 1)) / maxf(pixels_per_meter(), 0.00001)
		queue_redraw()
		accept_event()

static func position_of(value: Variant) -> Vector3:
	if value is Vector3: return value
	if value is Dictionary: return Vector3(value.get("x",0),value.get("y",0),value.get("z",0))
	if value is Array and value.size() >= 3: return Vector3(value[0],value[1],value[2])
	return Vector3.ZERO

func _draw() -> void:
	var interior:=Rect2(Vector2(18,18),(size-Vector2(36,36)).max(Vector2.ONE))
	draw_style_box(preload("res://scripts/datapad_theme.gd").frame(12),Rect2(Vector2.ZERO,size))
	var low := world_to_screen(Vector3(world_bounds.position.x,0,world_bounds.position.y))
	var high := world_to_screen(Vector3(world_bounds.end.x,0,world_bounds.end.y))
	var rect := Rect2(low,high-low).abs()
	if texture != null and rect.intersects(interior):
		var clipped:=rect.intersection(interior)
		var source:=Rect2((clipped.position-rect.position)/rect.size*texture.get_size(),clipped.size/rect.size*texture.get_size())
		draw_texture_rect_region(texture,clipped,source,Color(0.43,0.67,0.78))
	for i in range(1,8):
		var x := size.x*i/8.0
		var y := size.y*i/8.0
		draw_line(Vector2(x,interior.position.y),Vector2(x,interior.end.y),Color(0.3,0.8,0.9,0.12))
		draw_line(Vector2(interior.position.x,y),Vector2(interior.end.x,y),Color(0.3,0.8,0.9,0.12))
	var font := get_theme_default_font()
	# Preserve all source markers, but prioritize readable navigation labels.
	var markers: Array = waypoints.duplicate()
	for kind in ["city", "poi"]:
		for landmark in landmarks:
			if str(landmark.get("type","")) == kind: markers.append(landmark)
	markers.append_array(service_points)
	markers.append_array(registered_locations)
	for landmark in landmarks:
		if str(landmark.get("type","")) not in ["city", "poi"]: markers.append(landmark)
	var occupied: Array[Rect2] = [Rect2(20,20,190,30)]
	for landmark in markers:
		if not marker_visible(landmark):continue
		var p := world_to_screen(position_of(landmark.get("position",[])))
		if not interior.grow(-10).has_point(p): continue
		var kind := str(landmark.get("type","waypoint"))
		var icon_key := str(landmark.get("icon","waypoint"))
		var major := kind in ["city", "poi", "waypoint"]
		if icon_textures.has(icon_key) and not (kind in SERVICE_KINDS and not landmark.has("icon")) and (major or zoom >= 8):
			draw_texture_rect(icon_textures[icon_key],Rect2(p-Vector2(9,9),Vector2(18,18)),false)
		elif kind in SERVICE_KINDS:
			var color:=Color("f2c976") if kind=="trainer" else Color("76e8df")
			draw_rect(Rect2(p-Vector2(4,4),Vector2(8,8)),color,false,1.5)
		else: draw_circle(p,2.5,Color("76d9e8"))
		if not major and zoom < 8: continue
		if kind == "poi" and zoom < 2: continue
		var label := str(landmark.get("name",""))
		if font.get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,17).x>190:
			while label.length()>1 and font.get_string_size(label+"…",HORIZONTAL_ALIGNMENT_LEFT,-1,17).x>190:label=label.left(-1)
			label+="…"
		var width := minf(font.get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,17).x,190)
		for offset in [Vector2(12,-7),Vector2(12,20),Vector2(-width-12,-7),Vector2(-width-12,20)]:
			var baseline: Vector2 = p + offset
			var box := Rect2(baseline-Vector2(3,18),Vector2(width+6,23))
			if not interior.encloses(box): continue
			var blocked := false
			for previous in occupied:
				if previous.intersects(box): blocked = true; break
			if blocked: continue
			occupied.append(box)
			draw_rect(box,Color(0.015,0.045,0.065,0.84))
			draw_string(font,baseline,label,HORIZONTAL_ALIGNMENT_LEFT,190,17,Color("c6f5fa"))
			break
	var pp := world_to_screen(player)
	if interior.grow(-10).has_point(pp):draw_colored_polygon(PackedVector2Array([pp+Vector2(0,-10),pp+Vector2(-7,7),pp+Vector2(7,7)]),Color("ffda83"))
	if has_cursor and interior.grow(-15).has_point(world_to_screen(cursor)):
		var p := world_to_screen(cursor)
		draw_arc(p,10,0,TAU,28,Color.WHITE,2)
		draw_line(p-Vector2(15,0),p+Vector2(15,0),Color.WHITE)
		draw_line(p-Vector2(0,15),p+Vector2(0,15),Color.WHITE)
	draw_string(font,Vector2(28,42),"N     TATOOINE",HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color("d2faff"))
	draw_line(Vector2(57,43),Vector2(57,28),Color("d2faff"),1.5)
	draw_polyline(PackedVector2Array([Vector2(52,33),Vector2(57,28),Vector2(62,33)]),Color("d2faff"),1.5)
	if texture == null: draw_string(font,Vector2(28,size.y-28),"Map image unavailable • coordinate view",HORIZONTAL_ALIGNMENT_LEFT,-1,17,Color("8cbdcb"))

	var border:=preload("res://scripts/datapad_theme.gd").frame(12)
	border.draw_center=false
	draw_style_box(border,Rect2(Vector2.ZERO,size))

func marker_visible(marker: Dictionary) -> bool:
	var kind:=str(marker.get("type","waypoint"))
	if kind=="waypoint":return true
	if kind in ["starport","shuttleport"]:kind="travel"
	if kind=="underworld":kind="mission"
	if not filters.has(kind):kind="poi"
	return bool(filters.get(kind,true))
func set_filter(kind: String,enabled: bool) -> void:
	if not filters.has(kind):return
	filters[kind]=enabled;queue_redraw()
func set_service_points(values: Array) -> void:
	native_services=[]
	for value in values.slice(0,256):
		if not value is Dictionary or str(value.get("kind","")) not in SERVICE_KINDS:continue
		var position: Variant=value.get("position")
		if not position is Array or position.size()!=3 or not position_of(position).is_finite():continue
		native_services.append({"id":"native-service:"+str(value.get("id","")),"type":"mission" if value.kind=="underworld" else value.kind,"service_kind":value.kind,"name":str(value.get("name",str(value.kind).capitalize())),"position":position.duplicate(),"source":"Core3 discovery","building_id":value.get("building_id","0"),"cell_index":value.get("cell_index",0)})
	rebuild_service_points()
func load_service_references(directory:= "res://../runtime/assets/services") -> void:
	source_services=[]
	var path:=directory.path_join("catalog.json")
	if FileAccess.file_exists(path):
		var data: Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
		if data is Dictionary:
			for row in data.get("static_terminals",[]):
				if not row is Dictionary or str(row.get("kind","")) not in SERVICE_KINDS:continue
				source_services.append({"id":"source-service:"+str(row.id),"type":"mission" if row.kind=="underworld" else row.kind,"service_kind":row.kind,"name":str(row.get("name",str(row.kind).capitalize()+" terminal")),"position":row.get("position",[]),"source":"Original placement reference"})
	path=directory.path_join("trainers.json")
	if FileAccess.file_exists(path):
		var data: Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
		if data is Dictionary:
			for row in data.get("placements",[]):
				var definition: Dictionary=data.get("trainers",{}).get(row.get("mobile",""),{})
				source_services.append({"id":"source-trainer:"+str(row.get("id","")),"type":"trainer","name":str(definition.get("name","Trainer")),"position":row.get("source_world_xyz",[]),"source":"Original trainer placement reference"})
	rebuild_service_points()
func rebuild_service_points() -> void:
	service_points=native_services.duplicate(true)
	for row: Dictionary in source_services:
		var point:=position_of(row.position)
		if not row.position is Array or row.position.size()!=3 or not point.is_finite():continue
		var duplicate:=false
		for native: Dictionary in native_services:
			if native.type==row.type and position_of(native.position).distance_squared_to(point)<1.0:duplicate=true;break
		if not duplicate:service_points.append(row)
	queue_redraw()
func _get_tooltip(at_position: Vector2) -> String:
	for row: Dictionary in service_points:
		if marker_visible(row) and world_to_screen(position_of(row.position)).distance_to(at_position)<12:
			return str(row.name)+" · "+str(row.source)
	return ""
