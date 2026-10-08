extends "res://scripts/service_panel.gd"
var tracking:Dictionary={}
var types:Array=[]
var pending_elapsed:=0.0
var redraw_elapsed:=0.0
const TRACK_ROWS:=Rect2(20,204,820,280)
const TRACK_ROW_HEIGHT:=56.0
const TRACK_PAGE_SIZE:=5
const TRACK_PREVIOUS:=Rect2(20,544,140,52)
const TRACK_NEXT:=Rect2(700,544,140,52)
func apply(value:Dictionary)->void:
	var previous_request:=str(tracking.get("request_id",""))
	tracking=value.get("tracking",{}).duplicate(true);types=value.get("track_types",[]).duplicate(true)
	rows=tracking.get("results",[]).duplicate(true);offset=clampf(offset,0,maxi(0,rows.size()-TRACK_PAGE_SIZE))
	if previous_request!=str(tracking.get("request_id","")):pending_elapsed=0.0
	set_pending(tracking.get("state","")=="pending");queue_redraw()
func set_pending(value:bool)->void:
	if value and not pending:pending_elapsed=0.0
	super.set_pending(value)
func _process(delta:float)->void:
	if not pending:return
	pending_elapsed+=delta;redraw_elapsed+=delta
	if redraw_elapsed>=.1:redraw_elapsed=0.0;queue_redraw()
func type_rect(index:int)->Rect2:return Rect2(20+index*275,72,264,62)
func click_at(point:Vector2)->void:
	if CLOSE_RECT.has_point(point):close_requested.emit();return
	if pending:return
	if TRACK_PREVIOUS.has_point(point):scroll_rows(-TRACK_PAGE_SIZE);return
	if TRACK_NEXT.has_point(point):scroll_rows(TRACK_PAGE_SIZE);return
	for i in range(mini(3,types.size())):
		if type_rect(i).has_point(point):action_requested.emit("area_track",{"track_type":str(types[i])});return
	var index:=row_at(point)
	if index>=0:selected=index;queue_redraw()
func row_at(pixel:Vector2)->int:
	if not TRACK_ROWS.has_point(pixel):return -1
	var index:=int(offset)+int((pixel.y-TRACK_ROWS.position.y)/TRACK_ROW_HEIGHT)
	return index if index<rows.size() else -1
func scroll_rows(steps:int)->void:
	if pending or steps==0:return
	offset=clampf(offset+steps,0,maxi(0,rows.size()-TRACK_PAGE_SIZE))
	if pointer_down:dragged=true
	queue_redraw()
func scroll_at(pixel:Vector2,steps:int)->void:
	if TRACK_ROWS.has_point(pixel):scroll_rows(steps)
func navigate_at(pixel:Vector2,steps:int)->void:
	if pending or not TRACK_ROWS.has_point(pixel) or rows.is_empty() or steps==0:return
	selected=clampi(int(offset) if selected<0 else selected+steps,0,rows.size()-1)
	offset=clampf(offset,maxi(0,selected-TRACK_PAGE_SIZE+1),selected);navigation_anchor=pixel;queue_redraw()
func navigation_target(pixel:Vector2)->Vector2:
	if pixel.distance_to(navigation_anchor)<=12 and selected>=0:return Vector2(TRACK_ROWS.get_center().x,TRACK_ROWS.position.y+(selected-int(offset)+.5)*TRACK_ROW_HEIGHT)
	return pixel
func pointer_begin(pixel:Vector2)->void:
	if pending:return
	pointer_down=true;down_pixel=pixel;last_pixel=pixel;down_row=row_at(pixel);dragged=false;scroll_residual=0.0;drag_scrolling=TRACK_ROWS.has_point(pixel)
func pointer_move(pixel:Vector2)->void:
	if not pointer_down or pending:return
	if pixel.distance_to(down_pixel)>12:dragged=true
	if drag_scrolling and dragged:
		scroll_residual+=last_pixel.y-pixel.y
		if absf(scroll_residual)>=TRACK_ROW_HEIGHT:
			var steps:=int(scroll_residual/TRACK_ROW_HEIGHT);scroll_rows(steps);scroll_residual-=steps*TRACK_ROW_HEIGHT
	last_pixel=pixel
func type_label(value:String)->String:
	return {"animal":"Animals","npc":"NPCs","player":"Players"}.get(value,value.capitalize())
func notice()->String:
	match str(tracking.get("state","")):
		"pending":return "Tracking… stay still and out of combat for six seconds"
		"failed","cancelled","interrupted":
			var reason:=str(tracking.get("reason",""))
			if reason in ["","native_tracking_interrupted"]:return "Tracking interrupted. Stay still and out of combat; try again."
			return "Tracking failed: "+reason.replace("_"," ").capitalize()
		"succeeded":
			if rows.is_empty():return "No tracks found · choose a category to search again"
			if tracking.get("truncated",false):
				var total:=int(tracking.get("total_results",0))
				return "Showing %d of %d tracks · drag or joystick to scroll"%[rows.size(),total] if total>rows.size() else "Showing first %d tracks · drag or joystick to scroll"%rows.size()
			if rows.size()>=256 and not tracking.has("truncated"):return "Showing up to 256 tracks · drag or joystick to scroll"
			return "%d tracks · finger drag or joystick to scroll"%rows.size()
	return "Choose an available tracking category" if not types.is_empty() else "Area Track is not currently available"
func _draw()->void:
	draw_style_box(Holo.frame(14,"wide"),Rect2(Vector2.ZERO,size))
	draw_string(FONT,Vector2(30,48),"AREA TRACK",HORIZONTAL_ALIGNMENT_LEFT,760,29,Holo.INK);draw_string(FONT,Vector2(818,40),"×",HORIZONTAL_ALIGNMENT_LEFT,30,25,Holo.INK)
	for i in range(mini(3,types.size())):
		var rect:=type_rect(i);draw_style_box(Holo.button("disabled" if pending else "normal"),rect)
		if str(types[i])==str(tracking.get("track_type","")):draw_rect(rect.grow(-3),Color("7ce3ba"),false,2)
		draw_string(FONT,rect.position+Vector2(12,40),type_label(str(types[i])),HORIZONTAL_ALIGNMENT_CENTER,240,25,Holo.INK)
	draw_multiline_string(FONT,Vector2(22,164),notice(),HORIZONTAL_ALIGNMENT_LEFT,810,22,2,Holo.MUTED)
	if pending:
		var duration:=maxf(1.0,float(tracking.get("duration_seconds",6)))
		draw_string(FONT,Vector2(70,306),"Waiting for tracking result…" if pending_elapsed>=duration else "Searching for "+type_label(str(tracking.get("track_type","tracks"))).to_lower()+"…",HORIZONTAL_ALIGNMENT_CENTER,720,29,Holo.INK)
		draw_rect(Rect2(90,340,680,12),Color("163e4c"));draw_rect(Rect2(90,340,680*clampf(pending_elapsed/duration,0,1),12),Color("7ce3ba"))
		draw_string(FONT,Vector2(70,388),"You can lower your hands while the search finishes.",HORIZONTAL_ALIGNMENT_CENTER,720,22,Holo.MUTED)
	else:
		for i in range(TRACK_PAGE_SIZE):
			var index:=int(offset)+i
			if index>=rows.size():break
			var row:Dictionary=rows[index];var y:=TRACK_ROWS.position.y+i*TRACK_ROW_HEIGHT
			draw_style_box(Holo.cell(index==selected),Rect2(20,y,820,54))
			draw_string(FONT,Vector2(32,y+35),str(row.get("name","Unknown")),HORIZONTAL_ALIGNMENT_LEFT,550,25,Holo.INK)
			var detail:=str(row.get("direction",""))
			if row.has("distance_m") or row.has("distance"):detail+=" · %dm"%int(row.get("distance_m",row.get("distance",0)))
			draw_string(FONT,Vector2(598,y+35),detail,HORIZONTAL_ALIGNMENT_RIGHT,228,23,Holo.MUTED)
		if not rows.is_empty():draw_string(FONT,Vector2(250,580),"%d–%d / %d"%[int(offset)+1,mini(rows.size(),int(offset)+TRACK_PAGE_SIZE),rows.size()],HORIZONTAL_ALIGNMENT_CENTER,360,24,Holo.INK)
		if offset>0:draw_style_box(Holo.button("normal"),TRACK_PREVIOUS);draw_string(FONT,Vector2(32,578),"Previous",HORIZONTAL_ALIGNMENT_CENTER,116,21,Holo.INK)
		if offset+TRACK_PAGE_SIZE<rows.size():draw_style_box(Holo.button("normal"),TRACK_NEXT);draw_string(FONT,Vector2(712,578),"Next",HORIZONTAL_ALIGNMENT_CENTER,116,21,Holo.INK)
	if not message.is_empty():draw_string(FONT,Vector2(30,520),message,HORIZONTAL_ALIGNMENT_LEFT,810,18,Holo.MUTED)
