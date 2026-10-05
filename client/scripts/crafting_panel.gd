extends Control
## Holographic ingredient grid or paged schematic/experimentation readout.
signal chosen(index: int)
signal page_changed
var title := "CRAFTING"
var rows: Array = []
var selected := -1
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
	var step:=GRID_COLUMNS if grid_mode else 1
	var maximum:=maxi(0,ceili(float(rows.size()-page_size)/step)*step)
	var next:=clampi(offset+int(signf(amount))*step,0,maximum)
	if next!=offset: offset=next;queue_redraw();page_changed.emit()
func _gui_input(event: InputEvent) -> void:
	if not enabled: return
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed:
		var index:=row_at(event.position)
		if index>=0: selected=index; chosen.emit(index); queue_redraw()
func _draw() -> void:
	var font:=preload("res://resources/fonts/Jupiteroid-Regular.ttf")
	draw_style_box(preload("res://scripts/datapad_theme.gd").box("071c29","3ea8b9",2,14),Rect2(Vector2.ZERO,size))
	draw_string(font,Vector2(20,40),title,HORIZONTAL_ALIGNMENT_LEFT,size.x-40,25,Color("baffff"))
	for i in range(offset,mini(rows.size(),offset+page_size)):
		var row: Dictionary=rows[i]
		if grid_mode:
			var cell:=cell_rect(i)
			draw_rect(cell,Color(0.1,0.5,0.6,0.45) if selected==i else Color("10303e"))
			draw_rect(cell,Color("4c9ca9"),false,1)
			draw_string(font,cell.position+Vector2(8,20),"×%d"%int(row.get("quantity",0)),HORIZONTAL_ALIGNMENT_LEFT,cell.size.x-16,17,Color("baffff"))
			draw_multiline_string(font,cell.position+Vector2(8,125),str(row.get("name","")),HORIZONTAL_ALIGNMENT_LEFT,cell.size.x-16,16,2,Color("ddfbff"))
		else:
			var y:=TOP+(i-offset)*row_height
			if selected==i: draw_rect(Rect2(12,y,size.x-24,row_height-2),Color(0.1,0.5,0.6,0.45))
			var width:=size.x-130 if row_height>44 else size.x-45
			draw_string(font,Vector2(24,y+27),str(row.get("label",row.get("name",""))),HORIZONTAL_ALIGNMENT_LEFT,width,21,Color("ddfbff"))
			if row.has("bar"):
				draw_rect(Rect2(24,y+47,width,8),Color("163e4c"))
				draw_rect(Rect2(24,y+47,width*clampf(float(row.bar),0,1),8),Color("7ce3ba"))
	if rows.size()>page_size: draw_string(font,Vector2(20,586),"%d–%d / %d · stick scroll"%[offset+1,mini(rows.size(),offset+page_size),rows.size()],HORIZONTAL_ALIGNMENT_LEFT,size.x-40,16,Color("a7d5df"))
	draw_multiline_string(font,Vector2(20,610),footer,HORIZONTAL_ALIGNMENT_LEFT,size.x-40,18,3,Color("a7d5df"))
