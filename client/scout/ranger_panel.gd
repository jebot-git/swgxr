extends "res://scripts/service_panel.gd"
var tracking:Dictionary={}
var types:Array=[]
func apply(value:Dictionary)->void:
	tracking=value.get("tracking",{}).duplicate(true);types=value.get("track_types",[]).duplicate(true)
	rows=tracking.get("results",[]).duplicate(true);offset=clampf(offset,0,maxi(0,rows.size()-8));pending=tracking.get("state","")=="pending";queue_redraw()
func type_rect(index:int)->Rect2:return Rect2(20+index*275,68,264,42)
func click_at(point:Vector2)->void:
	if CLOSE_RECT.has_point(point):close_requested.emit();return
	if pending:return
	for i in range(mini(3,types.size())):
		if type_rect(i).has_point(point):action_requested.emit("area_track",{"track_type":str(types[i])});return
func notice()->String:
	match str(tracking.get("state","")):
		"pending":return "Tracking… stay still and out of combat for six seconds"
		"failed","cancelled","interrupted":
			var reason:=str(tracking.get("reason",""))
			if reason in ["","native_tracking_interrupted"]:return "Tracking interrupted. Stay still and out of combat; try again."
			return "Tracking failed: "+reason.replace("_"," ").capitalize()
		"succeeded":
			if rows.is_empty():return "No tracks found"
			if tracking.get("truncated",false):
				var total:=int(tracking.get("total_results",0))
				return "Showing %d of %d tracks · drag or joystick to scroll"%[rows.size(),total] if total>rows.size() else "Showing first %d tracks · drag or joystick to scroll"%rows.size()
			if rows.size()>=256 and not tracking.has("truncated"):return "Showing up to 256 tracks · drag or joystick to scroll"
			return "%d tracks · finger drag or joystick to scroll"%rows.size()
	return "Choose an available tracking category" if not types.is_empty() else "Area Track is not currently available"
func _draw()->void:
	draw_style_box(preload("res://scripts/datapad_theme.gd").frame(14,"wide"),Rect2(Vector2.ZERO,size))
	draw_string(FONT,Vector2(30,50),"AREA TRACK",HORIZONTAL_ALIGNMENT_LEFT,760,27,Color("d2f6ff"));draw_string(FONT,Vector2(818,40),"×",HORIZONTAL_ALIGNMENT_LEFT,30,25,Color("d2f6ff"))
	for i in range(mini(3,types.size())):
		var rect:=type_rect(i);draw_style_box(Holo.button("disabled" if pending else "normal"),rect);draw_string(FONT,rect.position+Vector2(12,28),str(types[i]).capitalize(),HORIZONTAL_ALIGNMENT_LEFT,240,20,Color("d2f6ff"))
	for i in range(8):
		var index:=int(offset)+i
		if index>=rows.size():break
		var row:Dictionary=rows[index];var text:=str(row.get("name","Unknown"))
		if row.has("direction"):text+=" · "+str(row.direction)
		if row.has("distance"):text+=" · %dm"%int(row.distance)
		if row.has("distance_m"):text+=" · %dm"%int(row.distance_m)
		draw_style_box(Holo.cell(index==selected),Rect2(20,128+i*44,820,42))
		draw_string(FONT,Vector2(30,156+i*44),text,HORIZONTAL_ALIGNMENT_LEFT,790,21,Color("d2f6ff"))
	draw_string(FONT,Vector2(22,525),notice(),HORIZONTAL_ALIGNMENT_LEFT,810,20,Color("9ac7da"));draw_string(FONT,Vector2(30,590),message,HORIZONTAL_ALIGNMENT_LEFT,810,17,Color("9ac7da"))
