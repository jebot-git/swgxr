extends Control
## Holographic ingredient grid or paged schematic/experimentation readout.
const Holo=preload("res://scripts/datapad_theme.gd")
signal chosen(index: int)
signal page_changed
var title := "CRAFTING"
var rows: Array = []
var selected := -1
var navigation_selected:=false
var navigation_anchor:=Vector2.ZERO
var pointer_pixel:=Vector2.ZERO
var offset := 0
var footer := ""
var enabled := true
var grid_mode := false
var row_height := 44.0
var page_size := 11
const TOP := 74.0
const GRID_COLUMNS := 4
const GRID_CELL := Vector2(156,164)
const GRID_ORIGIN := Vector2(18,74)
func _ready() -> void:
	custom_minimum_size=Vector2(660,660); size=custom_minimum_size
	mouse_filter=Control.MOUSE_FILTER_STOP
func layout(grid: bool, experiment: bool=false) -> void:
	var changed:=grid_mode!=grid or (row_height>44)!=experiment
	grid_mode=grid;row_height=120.0 if experiment else 44.0;page_size=12 if grid else (4 if experiment else 11)
	if changed: offset=0;selected=-1
func configure(heading: String, values: Array, message: String="") -> void:
	title=heading; rows=values.duplicate(true); footer=message
	var step:=GRID_COLUMNS if grid_mode else 1
	var maximum:=maxi(0,ceili(float(rows.size()-page_size)/step)*step)
	offset=clampi(offset,0,maximum);queue_redraw()
func cell_rect(index: int) -> Rect2:
	var cell:=index-offset
	return Rect2(GRID_ORIGIN+Vector2(cell%GRID_COLUMNS,cell/GRID_COLUMNS)*GRID_CELL,GRID_CELL-Vector2(6,6))
func row_at(pixel: Vector2) -> int:
	if grid_mode:
		for index in range(offset,mini(rows.size(),offset+page_size)):
			if cell_rect(index).has_point(pixel): return index
		return -1
	if pixel.y<TOP or pixel.y>=TOP+page_size*row_height or pixel.x<15 or pixel.x>size.x-15: return -1
	var index:=int((pixel.y-TOP)/row_height)+offset
	return index if index>=offset and index<mini(rows.size(),offset+page_size) else -1
func scroll(amount: float) -> void:
	if rows.is_empty() or is_zero_approx(amount) or not enabled:return
	selected=clampi(offset if selected<0 else selected+int(signf(amount)),0,rows.size()-1)
	navigation_selected=true;navigation_anchor=pointer_pixel
	var previous:=offset
	var step:=GRID_COLUMNS if grid_mode else 1
	if selected<offset:offset=(selected/step)*step
	elif selected>=offset+page_size:offset=(selected/step)*step-page_size+step
	queue_redraw()
	if previous!=offset:page_changed.emit()
func confirm_navigation() -> bool:
	if not enabled or not navigation_selected or selected<0 or selected>=rows.size():return false
	chosen.emit(selected);queue_redraw();return true

func _gui_input(event: InputEvent) -> void:
	if not enabled: return
	if event is InputEventMouseMotion:
		pointer_pixel=event.position
		if navigation_selected and pointer_pixel.distance_to(navigation_anchor)>12:navigation_selected=false
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed:
		var index:=selected if navigation_selected else row_at(event.position)
		if index>=0: selected=index; chosen.emit(index); queue_redraw()
func _draw() -> void:
	var font:=preload("res://resources/fonts/Jupiteroid-Regular.ttf")
	draw_style_box(Holo.frame(24),Rect2(Vector2.ZERO,size))
	draw_line(Vector2(28,58),Vector2(size.x-28,58),Color("29544e"),1)
	draw_string(font,Vector2(28,42),title,HORIZONTAL_ALIGNMENT_LEFT,size.x-40,25,Holo.INK)
	for i in range(offset,mini(rows.size(),offset+page_size)):
		var row: Dictionary=rows[i]
		if grid_mode:
			var cell:=cell_rect(i)
			draw_style_box(Holo.cell(selected==i),cell.grow(-3))
			draw_string(font,cell.position+Vector2(8,20),"×%d"%int(row.get("quantity",0)),HORIZONTAL_ALIGNMENT_LEFT,cell.size.x-16,17,Holo.INK)
			draw_multiline_string(font,cell.position+Vector2(8,125),str(row.get("name","")),HORIZONTAL_ALIGNMENT_LEFT,cell.size.x-16,16,2,Holo.INK)
		else:
			var y:=TOP+(i-offset)*row_height
			if selected==i: draw_style_box(Holo.cell(true),Rect2(20,y,size.x-40,row_height-2))
			var width:=size.x-130 if row_height>44 else size.x-45
			draw_string(font,Vector2(28,y+27),str(row.get("label",row.get("name",""))),HORIZONTAL_ALIGNMENT_LEFT,width,21,Holo.INK)
			if row.has("bar"):
				draw_rect(Rect2(24,y+47,width,8),Color("163e4c"))
				draw_rect(Rect2(24,y+47,width*clampf(float(row.bar),0,1),8),Color("7ce3ba"))
	if rows.size()>page_size: draw_string(font,Vector2(28,582),"%d–%d / %d · stick select"%[offset+1,mini(rows.size(),offset+page_size),rows.size()],HORIZONTAL_ALIGNMENT_LEFT,size.x-40,16,Holo.MUTED)
	draw_multiline_string(font,Vector2(28,609),footer,HORIZONTAL_ALIGNMENT_LEFT,size.x-56,17,2,Holo.MUTED)
