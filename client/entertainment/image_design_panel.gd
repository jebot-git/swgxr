extends "res://scripts/service_panel.gd"
## Source-table controls edit a proposal; native mutual consent alone commits it.
class ValueSlider extends "res://scripts/service_amount_slider.gd":
	var value_scale:=1.0
	var unit:=""
	func _draw()->void:
		var font:=preload("res://resources/fonts/Jupiteroid-Regular.ttf")
		draw_track()
		draw_string(font,Vector2(24,81),str(minimum/value_scale),HORIZONTAL_ALIGNMENT_LEFT,140,16,Color("9ac7da"))
		draw_string(font,Vector2(184,81),str(amount/value_scale)+unit,HORIZONTAL_ALIGNMENT_CENTER,192,19,Color("d2f6ff"))
		draw_string(font,Vector2(396,81),str(maximum/value_scale),HORIZONTAL_ALIGNMENT_RIGHT,140,16,Color("9ac7da"))
const PREVIEW_RECT=Rect2(594,115,240,335)
const DESIGN_ROWS=Rect2(20,128,548,220)
var design:Dictionary={}
var draft:Dictionary={}
var candidates:Array=[]
var browse:="controls"
var candidate_action:="image_open"
var controls:Array=[]
var slider_rule:Dictionary={}
var preview_view:SubViewport
var preview_avatar:Node3D
var preview_camera:Camera3D
var preview_signature:=""
func _ready()->void:
	super()
	slider.free();slider=ValueSlider.new();add_child(slider);slider.mouse_filter=Control.MOUSE_FILTER_IGNORE;slider.amount_changed.connect(func(_value):queue_redraw());slider.hide()
	slider.position=Vector2(18,368)
	preview_view=SubViewport.new();preview_view.size=Vector2i(320,448);preview_view.own_world_3d=true;preview_view.transparent_bg=true;preview_view.render_target_update_mode=SubViewport.UPDATE_WHEN_VISIBLE
	add_child(preview_view)
	var world:=Node3D.new();preview_view.add_child(world)
	var environment:=WorldEnvironment.new();environment.environment=Environment.new();environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color("06131e");environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color("d6e4ee");environment.environment.ambient_light_energy=.7;world.add_child(environment)
	preview_camera=Camera3D.new();preview_camera.fov=42;preview_camera.cull_mask=3;world.add_child(preview_camera)
	preview_avatar=preload("res://scripts/avatar.gd").new();world.add_child(preview_avatar);preview_avatar.rotation.y=PI
func show_candidates(values:Array,action:String="image_open")->void:
	candidate_action=action
	design={};candidates=values.duplicate(true);rows=candidates;selected=-1;offset=0;browse="targets";slider.hide();pending=false;message="Choose a nearby player to invite to your native group." if action=="group_invite" else "Choose yourself or a nearby grouped player.";queue_redraw()
func apply_design(value:Dictionary)->void:
	var changed:bool=str(value.get("session_id",""))!=str(design.get("session_id","")) or int(value.get("revision",-1))!=int(design.get("revision",-1)) or value.get("options",{})!=design.get("options",{}) or value.get("role","")!=design.get("role","")
	design=value.duplicate(true);pending=false
	design["draft"]=design.get("draft",{}).duplicate(true);design.draft["attributes"]=design.draft.get("attributes",{}).duplicate(true)
	if changed:
		cancel_pointer();draft=design.get("draft",{}).duplicate(true);draft["attributes"]=draft.get("attributes",{}).duplicate(true);selected=-1;slider.hide();slider_rule={};browse="controls";offset=0
	controls=design.get("options",{}).get("controls",[]).duplicate(true)
	if changed or rows.is_empty():build_rows()
	update_preview(design.get("preview",design.get("appearance",{})))
	queue_redraw()
func build_rows()->void:
	rows=[]
	if design.get("role","")!="designer":return
	rows.append({"id":"__hair","label":"Hair / head detail"});rows.append({"id":"__holo","label":"Holoemote"});rows.append({"id":"__price","label":"Price · %d credits"%int(draft.get("price",0))})
	rows.append_array(controls)
func update_preview(appearance:Dictionary)->void:
	if appearance.is_empty():return
	var signature:=JSON.stringify(appearance)
	if signature==preview_signature:return
	preview_signature=signature
	var hair:Dictionary=appearance.get("hair",{}) if appearance.get("hair") is Dictionary else {}
	var values:Dictionary={"customization":appearance.get("customization",{}),"height":appearance.get("height",1.0),"hair_template":hair.get("template",appearance.get("hair_template","")),"hair_customization":hair.get("customization",appearance.get("hair_customization",{}))}
	var result:Dictionary=preview_avatar.configure(str(appearance.get("race","")),values,appearance.get("equipment",[]))
	if not str(result.get("error","")).is_empty():message=str(result.error);return
	var h:float=preview_avatar.height_meters
	preview_camera.position=Vector3(0,h*.52,h*1.8);preview_camera.look_at(Vector3(0,h*.5,0))
func row_at(pixel:Vector2)->int:
	if not DESIGN_ROWS.has_point(pixel):return -1
	var index:=int((pixel.y-DESIGN_ROWS.position.y)/ROW_HEIGHT)+int(offset)
	return index if index<rows.size() else -1
func scroll_at(pixel:Vector2,steps:int)->void:
	if pending or not DESIGN_ROWS.has_point(pixel):return
	offset=clampf(offset+steps,0,maxi(0,rows.size()-5));if pointer_down:dragged=true
	queue_redraw()
func navigate_at(pixel:Vector2,steps:int)->void:
	if pending or slider.dragging or steps==0 or not DESIGN_ROWS.has_point(pixel) or rows.is_empty():return
	selected=clampi(int(offset) if selected<0 else selected+steps,0,rows.size()-1)
	offset=clampf(offset,maxi(0,selected-4),selected)
	navigation_anchor=pixel;navigation_category=false
	if pointer_down:dragged=true
	queue_redraw()

func pointer_begin(pixel:Vector2)->void:
	super(pixel)
	if pointer_down and not slider.dragging:drag_scrolling=DESIGN_ROWS.has_point(pixel)
func pointer_move(pixel:Vector2)->void:
	if not pointer_down or pending:return
	if pixel.distance_to(down_pixel)>12:dragged=true
	if slider.dragging:slider.drag_to(pixel-slider.position)
	elif drag_scrolling and dragged:
		scroll_residual+=last_pixel.y-pixel.y
		if absf(scroll_residual)>=ROW_HEIGHT:
			var steps:=int(scroll_residual/ROW_HEIGHT)
			offset=clampf(offset+steps,0,maxi(0,rows.size()-5));scroll_residual-=steps*ROW_HEIGHT;queue_redraw()
	last_pixel=pixel
func pointer_end(pixel:Vector2)->void:
	var was_slider:bool=pointer_down and slider.dragging
	var amount:int=slider.amount
	super(pixel)
	if was_slider and design.get("role","")=="designer" and not slider_rule.is_empty():
		if slider_rule.id=="__price":draft.price=amount
		else:draft.attributes[str(slider_rule.id)]=float(amount)/100.0 if slider_rule.get("type","")=="shape" else amount
		queue_redraw()
func mutation_payload()->Dictionary:
	return {"session_id":str(design.get("session_id","")),"revision":int(design.get("revision",-1))}
func click_at(pixel:Vector2)->void:
	if pending:return
	if CLOSE_RECT.has_point(pixel):close_requested.emit();return
	if REFRESH_RECT.has_point(pixel):
		if browse in ["hair","holo"]:browse="controls";offset=0;build_rows();queue_redraw()
		elif not design.is_empty():action_requested.emit("image_cancel",mutation_payload())
		return
	if CONFIRM_RECT.has_point(pixel) and not design.is_empty():
		var payload:=mutation_payload()
		if design.get("role","")=="designer" and draft!=design.get("draft",{}):payload.draft=draft.duplicate(true);action_requested.emit("image_propose",payload)
		elif bool(design.get("can_accept",false)):action_requested.emit("image_accept",payload)
		return
	var index:=row_at(pixel)
	if index<0:return
	selected=index
	var row:Dictionary=rows[index]
	if browse=="targets":action_requested.emit(candidate_action,{"target_id":str(row.id)});return
	if design.get("role","")!="designer":return
	if browse=="hair":draft.hair_template=str(row.get("template",""));browse="controls";offset=0;build_rows();slider.hide();queue_redraw();return
	if browse=="holo":draft.holoemote=str(row.get("id",""));browse="controls";offset=0;build_rows();slider.hide();queue_redraw();return
	match str(row.id):
		"__hair":
			rows=design.get("options",{}).get("hair",[]).duplicate(true)
			if design.get("options",{}).get("allow_bald",false):rows.push_front({"label":"No hair","template":""})
			browse="hair";offset=0;slider.hide()
		"__holo":
			rows=[{"id":"","label":"No holoemote"}]
			for value in design.get("options",{}).get("holoemotes",[]):rows.append({"id":str(value),"label":str(value).capitalize()})
			browse="holo";offset=0;slider.hide()
		_:
			slider_rule=row.duplicate(true)
			var shape:bool=row.get("type","")=="shape"
			var scale:=100 if shape else 1
			var lower:int=int(float(row.get("min",0))*scale);var upper:int=10000 if row.id=="__price" else int(float(row.get("max",1))*scale)
			var value:float=float(draft.get("price",0)) if row.id=="__price" else float(draft.get("attributes",{}).get(row.id,float(row.get("value",.5 if shape else 0))))*scale
			slider.value_scale=100.0 if shape else 1.0;slider.unit=" credits" if row.id=="__price" else ""
			slider.configure_range(lower,upper,int(value));slider.show()
	queue_redraw()
func _draw()->void:
	draw_style_box(preload("res://scripts/datapad_theme.gd").frame(14,"wide"),Rect2(Vector2.ZERO,size))
	draw_string(FONT,Vector2(30,50),("GROUP INVITE" if design.is_empty() and candidate_action=="group_invite" else "IMAGE DESIGN"),HORIZONTAL_ALIGNMENT_LEFT,760,27,Color("d2f6ff"));draw_string(FONT,Vector2(818,40),"×",HORIZONTAL_ALIGNMENT_LEFT,30,25,Color("d2f6ff"))
	var subtitle:=("Invite a nearby player to your native group" if candidate_action=="group_invite" else "Choose a nearby grouped player · self design supported") if design.is_empty() else "Your proposal" if design.get("role","")=="designer" else "Review proposed appearance and payment"
	draw_string(FONT,Vector2(22,83),subtitle,HORIZONTAL_ALIGNMENT_LEFT,810,20,Color("9ac7da"))
	for i in range(5):
		var index:=int(offset)+i
		if index>=rows.size():break
		var row:Dictionary=rows[index];var rect:=Rect2(20,128+i*44,548,42)
		draw_style_box(Holo.cell(index==selected),rect);draw_string(FONT,rect.position+Vector2(12,28),str(row.get("label",row.get("name",row.get("id","")))),HORIZONTAL_ALIGNMENT_LEFT,520,20,Color("d2f6ff"))
	if rows.size()>5:draw_string(FONT,Vector2(22,112),"%d–%d / %d · drag or joystick"%[int(offset)+1,mini(rows.size(),int(offset)+5),rows.size()],HORIZONTAL_ALIGNMENT_LEFT,550,15,Color("9ac7da"))
	if not design.is_empty():
		if not preview_signature.is_empty():draw_texture_rect(preview_view.get_texture(),PREVIEW_RECT,false)
		if design.get("role","")!="designer":draw_multiline_string(FONT,Vector2(28,150),"%d credits\n\nBoth players must accept this exact revision.\nAny new proposal cancels previous consent."%int(draft.get("price",0)),HORIZONTAL_ALIGNMENT_LEFT,510,23,5,Color("d2f6ff"))
		if slider.visible:draw_string(FONT,Vector2(28,363),str(slider_rule.get("label","Value")),HORIZONTAL_ALIGNMENT_LEFT,540,18,Color("9ac7da"))
		button(REFRESH_RECT,"Back" if browse in ["hair","holo"] else "Cancel")
		var dirty:bool=draft!=design.get("draft",{})
		button(CONFIRM_RECT,"Send proposal" if design.get("role","")=="designer" and dirty else "Accept · %d cr"%int(draft.get("price",0)) if design.get("can_accept",false) else "Waiting for consent")
		draw_string(FONT,Vector2(228,523),"Revision %d"%int(design.get("revision",0)),HORIZONTAL_ALIGNMENT_LEFT,345,17,Color("9ac7da"))
	draw_string(FONT,Vector2(30,590),message,HORIZONTAL_ALIGNMENT_LEFT,810,16,Color("9ac7da"))
func button(rect:Rect2,text:String)->void:
	draw_style_box(Holo.button("disabled" if pending else "normal"),rect);draw_string(FONT,rect.position+Vector2(12,32),text,HORIZONTAL_ALIGNMENT_LEFT,rect.size.x-24,20,Color("d2f6ff"))
