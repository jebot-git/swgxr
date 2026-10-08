extends Control
## Integer credit slider shared by bank and local wallet payment panels.
## Dragging edits a proposal only; the owning panel confirms a server mutation.
signal amount_changed(value: int)
var currency_unit := "credits"
var minimum := 0
var maximum := 0
var amount := 0
var dragging := false
var enabled := true
const Holo=preload("res://scripts/datapad_theme.gd")
const HANDLE_SIZE:=Vector2(32,40)
const TRACK := Rect2(24,36,512,12)

func _ready() -> void:
	size=Vector2(560,86)
	mouse_filter=Control.MOUSE_FILTER_STOP

func configure(limit: int, initial: int = 0) -> void:
	configure_range(0,limit,initial)

func configure_range(lower: int, upper: int, initial: int=0) -> void:
	minimum=maxi(lower,0)
	maximum=maxi(upper,minimum)
	amount=clampi(initial,minimum,maximum)
	dragging=false
	queue_redraw()

func set_at(pixel: Vector2) -> void:
	if not enabled: return
	var next:=clampi(minimum+roundi(clampf((pixel.x-TRACK.position.x)/TRACK.size.x,0,1)*(maximum-minimum)),minimum,maximum)
	if amount!=next:
		amount=next
		amount_changed.emit(amount)
		queue_redraw()

func begin_drag(pixel: Vector2) -> bool:
	if not enabled or maximum<=0 or not Rect2(12,12,536,60).has_point(pixel): return false
	dragging=true
	set_at(pixel)
	return true

func drag_to(pixel: Vector2) -> void:
	if dragging: set_at(pixel)

func cancel_drag() -> void:
	dragging=false

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		if event.pressed: begin_drag(event.position)
		else: cancel_drag()
	elif event is InputEventMouseMotion: drag_to(event.position)

func _draw() -> void:
	var font:=preload("res://resources/fonts/Jupiteroid-Regular.ttf")
	draw_track()
	draw_string(font,Vector2(24,81),str(minimum),HORIZONTAL_ALIGNMENT_LEFT,140,16,Color("9ac7da"))
	draw_string(font,Vector2(200,81),"%d %s"%[amount,currency_unit],HORIZONTAL_ALIGNMENT_CENTER,160,19,Color("d2f6ff"))
	draw_string(font,Vector2(396,81),str(maximum),HORIZONTAL_ALIGNMENT_RIGHT,140,16,Color("9ac7da"))

func handle_rect() -> Rect2:
	var fraction:=float(amount-minimum)/(maximum-minimum) if maximum>minimum else 0.0
	return Rect2(Vector2(TRACK.position.x+fraction*TRACK.size.x,TRACK.get_center().y)-HANDLE_SIZE*.5,HANDLE_SIZE)

func draw_track() -> void:
	var handle:=handle_rect()
	draw_style_box(Holo.box("0b2638","285369",1,0),TRACK)
	draw_style_box(Holo.box("3e9fba","67dcff",0,0),Rect2(TRACK.position,Vector2(handle.get_center().x-TRACK.position.x,TRACK.size.y)))
	# Extended square grip is visible above and below the track; normal clicks
	# and the service surface's captured grip drag use the same value mapping.
	var grip:=Holo.cell(dragging,0)
	grip.set_corner_radius_all(1)
	grip.bg_color=Color("12384b") if enabled else Color("142b38")
	grip.border_color=Holo.ACCENT if enabled else Holo.MUTED
	grip.set_border_width_all(2)
	draw_style_box(grip,handle)
	for x in [-4,4]:draw_line(handle.get_center()+Vector2(x,-8),handle.get_center()+Vector2(x,8),Holo.INK if enabled else Holo.MUTED,2)
