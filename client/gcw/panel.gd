extends "res://scripts/service_panel.gd"
## Recruiter specialization preserves trainer/service input and native confirmation.
var reward_preview:SubViewport
var preview_image:TextureRect
var info:RichTextLabel
var preview_ready:=false
func _ready()->void:
	super()
	reward_preview=preload("res://gcw/reward_preview.gd").new();add_child(reward_preview)
	preview_image=TextureRect.new();add_child(preview_image);preview_image.position=Vector2(590,145);preview_image.size=Vector2(244,170);preview_image.texture=reward_preview.get_texture();preview_image.mouse_filter=Control.MOUSE_FILTER_IGNORE;preview_image.hide()
	info=RichTextLabel.new();add_child(info);info.position=Vector2(590,326);info.size=Vector2(244,146);info.mouse_filter=Control.MOUSE_FILTER_IGNORE;info.add_theme_font_override("normal_font",FONT);info.add_theme_font_size_override("normal_font_size",19);info.add_theme_color_override("default_color",Color("d2f6ff"));info.hide()
func configure(record:Dictionary,balances:Dictionary,held_tickets:Array=[])->void:
	var old:=""
	if selected>=0 and selected<rows.size():old=str(rows[selected].get("id",""))
	var same:=str(record.get("id",""))==str(terminal.get("id",""))
	super(record,balances,held_tickets)
	var recruiter:bool=terminal.get("kind","")=="recruiter"
	if is_instance_valid(info):info.visible=recruiter
	if not recruiter:
		if is_instance_valid(preview_image):preview_image.hide();reward_preview.suspend()
		return
	rows=[{"id":"enlist","name":"Enlist with "+str(terminal.get("faction","")).capitalize(),"kind":"join","eligible":bool(terminal.get("can_join",false)),"reason":str(terminal.get("reason","")),"description":str(terminal.get("recruiter_text",""))}]
	if terminal.has("rank"):
		rows.append({"id":"promotion","name":"Request promotion", "kind":"promotion","eligible":bool(terminal.get("can_promote",false)),"reason":str(terminal.get("promotion_reason","")),"cost_faction_points":terminal.get("promotion_cost_faction_points",0),"description":"Current rank: "+str(terminal.get("rank_name",""))+"\nNext rank: "+str(terminal.get("next_rank_name",""))})
	for reward:Dictionary in terminal.get("rewards",[]):
		var value:=reward.duplicate(true);value.kind="reward";rows.append(value)
	selected=-1
	if same:
		for i in range(rows.size()):
			if str(rows[i].get("id",""))==old:selected=i;break
	offset=clampf(offset,0,maxi(0,rows.size()-8));refresh_details();queue_redraw()
func refresh_details()->void:
	if not is_instance_valid(info):return
	preview_ready=false;preview_image.hide()
	if selected<0 or selected>=rows.size():
		info.position=Vector2(590,135);info.size=Vector2(244,335);info.text=str(terminal.get("recruiter_text","Select enlistment or a reward to inspect it."));reward_preview.show_item({});return
	var row:Dictionary=rows[selected];var reward:bool=row.get("kind")=="reward"
	preview_ready=reward_preview.show_item(row if reward else {})
	preview_image.visible=reward and preview_ready
	info.position=Vector2(590,326 if reward else 135);info.size=Vector2(244,146 if reward else 335)
	info.text=label_for(row)+"\n"
	if reward or row.get("kind")=="promotion":info.text+="%d faction points\n"%int(row.get("cost_faction_points",0))
	if not bool(row.get("eligible",false)):info.text+=str(row.get("reason","Unavailable"))+"\n"
	if reward and not preview_ready:info.text+="Original reward preview unavailable.\n"
	info.text+=str(row.get("description",""));info.scroll_to_line(0)
func interface_closed()->void:reward_preview.suspend()
func scroll_details(pixel:Vector2,steps:int)->bool:
	if terminal.get("kind","")!="recruiter" or not info.visible or not Rect2(info.position,info.size).has_point(pixel):return false
	info.get_v_scroll_bar().value+=steps*40
	return true
func scroll_at(pixel:Vector2,steps:int)->void:
	if scroll_details(pixel,steps):return
	super(pixel,steps)
func navigate_at(pixel:Vector2,steps:int)->void:
	if scroll_details(pixel,steps):return
	var previous:=selected;super(pixel,steps)
	if terminal.get("kind","")=="recruiter" and previous!=selected:refresh_details()
func click_at(pixel:Vector2)->void:
	if terminal.get("kind","")=="contraband":
		if pending:return
		if CLOSE_RECT.has_point(pixel):close_requested.emit();return
		if not terminal.get("scan",{}).get("answer_pending",false):return
		if REFRESH_RECT.has_point(pixel) or CONFIRM_RECT.has_point(pixel):
			set_pending(true);action_requested.emit("contraband_answer",{"scan_id":str(terminal.scan.id),"accept":REFRESH_RECT.has_point(pixel)})
		return
	if terminal.get("kind","")!="recruiter":super(pixel);return
	if pending:return
	if CLOSE_RECT.has_point(pixel):close_requested.emit();return
	if REFRESH_RECT.has_point(pixel):set_pending(true);action_requested.emit("open",{"terminal_id":str(terminal.id)});return
	if ROWS_RECT.has_point(pixel):selected=row_at(pixel);refresh_details();queue_redraw();return
	if CONFIRM_RECT.has_point(pixel):confirm()
func confirm()->void:
	if terminal.get("kind","")!="recruiter":super();return
	if pending or selected<0 or selected>=rows.size():return
	var row:Dictionary=rows[selected]
	if not row.get("eligible",false):message=str(row.get("reason","Core3 does not allow this action."));queue_redraw();return
	var action:="recruiter_join";var payload:Dictionary={"terminal_id":str(terminal.id)}
	if row.get("kind")=="reward":
		if not preview_ready:message="Inspect the original reward preview before purchasing.";queue_redraw();return
		action="recruiter_purchase";payload.reward_id=str(row.id)
	if row.get("kind")=="promotion":action="recruiter_promote";payload.expected_rank=int(terminal.get("rank",-1))
	set_pending(true);action_requested.emit(action,payload)
func draw_scan()->void:
	draw_style_box(Holo.frame(14,"wide"),Rect2(Vector2.ZERO,size))
	draw_string(FONT,Vector2(30,50),"CONTRABAND INSPECTION",HORIZONTAL_ALIGNMENT_LEFT,760,27,Color("d2f6ff"));draw_string(FONT,Vector2(818,40),"×",HORIZONTAL_ALIGNMENT_LEFT,30,25,Color("d2f6ff"))
	var scan:Dictionary=terminal.get("scan",{})
	draw_multiline_string(FONT,Vector2(40,160),"Core3's inspecting patrol has issued a fine.\n\nFine: %d credits\nCarried: %d credits · Bank: %d credits\n\nPay the fine or refuse. The patrol determines the outcome."%[int(scan.get("fine",0)),int(wallet.get("cash",0)),int(wallet.get("bank",0))],HORIZONTAL_ALIGNMENT_LEFT,770,24,10,Color("d2f6ff"))
	for button in [{"rect":REFRESH_RECT,"text":"Pay fine"},{"rect":CONFIRM_RECT,"text":"Refuse"}]:
		draw_style_box(Holo.button("disabled" if pending else "normal"),button.rect);draw_string(FONT,button.rect.position+Vector2(10,33),str(button.text),HORIZONTAL_ALIGNMENT_CENTER,button.rect.size.x-20,20,Color("d2f6ff"))
	draw_string(FONT,Vector2(22,580),"Waiting for Core3…" if pending else message,HORIZONTAL_ALIGNMENT_LEFT,810,18,Color("9ac7da"))
func _draw()->void:
	if terminal.get("kind","")=="contraband":draw_scan();return
	if terminal.get("kind","")!="recruiter":super();return
	draw_style_box(Holo.frame(14,"wide"),Rect2(Vector2.ZERO,size))
	draw_string(FONT,Vector2(30,50),str(terminal.get("name","FACTION RECRUITER")),HORIZONTAL_ALIGNMENT_LEFT,760,27,Color("d2f6ff"));draw_string(FONT,Vector2(818,40),"×",HORIZONTAL_ALIGNMENT_LEFT,30,25,Color("d2f6ff"))
	var duty:=str(terminal.get("gcw",{}).get("status_name","combatant" if int(terminal.get("status",0))==1 else "neutral")).replace("_"," ").capitalize()
	draw_string(FONT,Vector2(22,84),str(terminal.get("faction","")).capitalize()+" · "+duty+" · PvE duty",HORIZONTAL_ALIGNMENT_LEFT,810,20,Color("9ac7da"))
	draw_string(FONT,Vector2(22,115),"Enlistment and original faction rewards",HORIZONTAL_ALIGNMENT_LEFT,800,18,Color("9ac7da"))
	for i in range(int(offset),mini(rows.size(),int(offset)+8)):
		var y:=128+(i-int(offset))*ROW_HEIGHT;draw_style_box(Holo.cell(selected==i),Rect2(20,y,548,ROW_HEIGHT-2));draw_string(FONT,Vector2(28,y+29),label_for(rows[i]),HORIZONTAL_ALIGNMENT_LEFT,530,21,Color("d2f6ff"))
	draw_style_box(Holo.button("disabled" if pending else "normal"),REFRESH_RECT);draw_string(FONT,REFRESH_RECT.position+Vector2(10,33),"Refresh",HORIZONTAL_ALIGNMENT_CENTER,170,19,Color("d2f6ff"))
	if rows.size()>8:draw_string(FONT,Vector2(230,519),"%d–%d / %d · drag"%[int(offset)+1,mini(rows.size(),int(offset)+8),rows.size()],HORIZONTAL_ALIGNMENT_LEFT,330,18,Color("9ac7da"))
	var valid:=selected>=0 and selected<rows.size();var reward:bool=valid and rows[selected].get("kind")=="reward";var enabled:bool=valid and rows[selected].get("eligible",false) and (not reward or preview_ready) and not pending
	draw_style_box(Holo.button("hover" if enabled else "disabled"),CONFIRM_RECT);draw_string(FONT,CONFIRM_RECT.position+Vector2(10,33),"Waiting for Core3…" if pending else "Purchase reward" if reward else "Request promotion" if valid and rows[selected].get("kind")=="promotion" else "Confirm enlistment",HORIZONTAL_ALIGNMENT_CENTER,230,20,Color("d2f6ff"))
	draw_string(FONT,Vector2(22,559),"Salute your recruiter to request on-leave / combatant duty.",HORIZONTAL_ALIGNMENT_LEFT,810,18,Color("9ac7da"));draw_string(FONT,Vector2(22,592),message,HORIZONTAL_ALIGNMENT_LEFT,810,17,Color("9ac7da"))
