extends "res://scripts/datapad_map.gd"
## Three projections of native XYZ space; no terrain-height or ground navigation.
var sector: Dictionary = {}
var contacts: Array = []
var projection := 0
var compact := false
var sector_ship := Vector3.ZERO
var sector_forward:=Vector3.BACK

func set_sector(value: Dictionary, ship: Dictionary, nearby: Array) -> void:
	if sector.get("source_zone", "") != value.get("source_zone", ""): center=Vector2.ZERO; zoom=1.0
	sector=value; contacts=nearby
	var p: Array = ship.get("position", [0,0,0]); sector_ship=Vector3(p[0],p[1],p[2])
	var q:Array=ship.get("quaternion",[0,0,0,1]);sector_forward=Basis(Quaternion(q[0],q[1],q[2],q[3]))*Vector3.BACK
	queue_redraw()
func axes(value: Vector3) -> Vector2:
	return Vector2(value.x,value.z) if projection==0 else Vector2(value.x,value.y) if projection==1 else Vector2(value.z,value.y)
func world_to_screen(value: Vector3) -> Vector2:
	if sector.is_empty(): return super.world_to_screen(value)
	var offset:=axes(value)-center
	return size*.5+Vector2(offset.x,-offset.y)*pixels_per_meter()
func center_on_player() -> void:
	if sector.is_empty(): super.center_on_player(); return
	center=axes(sector_ship); queue_redraw()
func cycle_projection() -> void:
	projection=(projection+1)%3; center=Vector2.ZERO; queue_redraw()
func _gui_input(event: InputEvent) -> void:
	if sector.is_empty(): super._gui_input(event); return
	# Pan and zoom only; space travel targets must be original native jump points.
	if event is InputEventMouseButton:
		if event.button_index==MOUSE_BUTTON_WHEEL_UP and event.pressed: zoom=clampf(zoom*1.25,1,32)
		elif event.button_index==MOUSE_BUTTON_WHEEL_DOWN and event.pressed: zoom=clampf(zoom*.8,1,32)
		elif event.button_index==MOUSE_BUTTON_LEFT: dragging=event.pressed
		queue_redraw(); accept_event()
	elif event is InputEventMouseMotion and dragging:
		center-=Vector2(event.relative.x,-event.relative.y)/maxf(.00001,pixels_per_meter()); queue_redraw(); accept_event()
func _draw() -> void:
	if sector.is_empty(): super._draw(); return
	var area:=Rect2(Vector2(12,12),size-Vector2(24,24))
	draw_style_box(preload("res://scripts/datapad_theme.gd").frame(12),Rect2(Vector2.ZERO,size))
	var cyan:=Color("67dcea"); var font:=get_theme_default_font()
	for index in range(1,8):
		var offset:=float(index)/8
		draw_line(Vector2(area.position.x+area.size.x*offset,area.position.y),Vector2(area.position.x+area.size.x*offset,area.end.y),Color(.1,.4,.5,.25))
		draw_line(Vector2(area.position.x,area.position.y+area.size.y*offset),Vector2(area.end.x,area.position.y+area.size.y*offset),Color(.1,.4,.5,.25))
	var rows: Array=sector.get("markers",[]).duplicate()
	for jump:Dictionary in sector.get("navigation",[]):
		var marker:=jump.duplicate();marker.kind="jump";rows.append(marker)
	rows.append_array(contacts)
	for row: Dictionary in rows:
		var p:=world_to_screen(position_of(row.get("position",[])))
		if not area.has_point(p):continue
		var color:=Color("ff755e") if row.get("hostile",false) else Color("b6e782") if row.get("kind","")=="jump" else cyan
		draw_circle(p,2 if compact else 3,color)
		if not compact and row.get("kind","") in ["station","jump","waypoint"]:
			draw_string(font,p+Vector2(5,-4),str(row.get("name","")),HORIZONTAL_ALIGNMENT_LEFT,180,12,color)
	var player_pixel:=world_to_screen(sector_ship)
	if area.has_point(player_pixel):
		var heading:=axes(sector_forward);heading.y=-heading.y
		var angle:=heading.angle()+PI/2;var arrow:=PackedVector2Array()
		for vertex:Vector2 in [Vector2(0,-6),Vector2(-4,4),Vector2(4,4)]:arrow.append(player_pixel+vertex.rotated(angle))
		draw_colored_polygon(arrow,Color.WHITE)
	var label:String="SECTOR  /  "+str(sector.get("name",""))+"  /  "+["X/Z","X/Y","Z/Y"][projection]
	draw_string(font,Vector2(16,28),label,HORIZONTAL_ALIGNMENT_LEFT,size.x-32,12 if compact else 16,cyan)
	if not compact:draw_string(font,Vector2(16,size.y-16),"X %.0f   Y %.0f   Z %.0f m"%[sector_ship.x,sector_ship.y,sector_ship.z],HORIZONTAL_ALIGNMENT_LEFT,size.x-32,14,cyan)
