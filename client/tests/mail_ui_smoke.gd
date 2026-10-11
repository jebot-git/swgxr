extends SceneTree
var failures:Array=[]
var checks:=0
var requests:Array=[]
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);push_error(label)
func _initialize()->void:call_deferred("run")
func mouse(view:Viewport,point:Vector2,pressed:bool)->void:
	var motion:=InputEventMouseMotion.new();motion.position=point;view.push_input(motion,true)
	var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.position=point;event.pressed=pressed;view.push_input(event,true)
func run()->void:
	root.size=Vector2i(1440,1000)
	var panel=preload("res://mail/panel.gd").new();root.add_child(panel);panel.size=Vector2(1440,900)
	panel.action_requested.connect(func(action,payload):requests.append({"action":action,"payload":payload}))
	panel.set_mail({"messages":[{"id":"7","sender":"Tester","subject":"Hello","read":false}],"total":1,"unread":1,"has_more":false})
	check(panel.list.get_item_text(0).begins_with("• "),"Unread native mail is marked")
	panel.select_mail(0);check(requests.back().action=="mail_read" and requests.back().payload.mail_id=="7","Mail read preserves native identity")
	panel.show_message({"id":"7","sender":"Tester","subject":"Hello","body":"[b]Literal message[/b]"})
	check(not panel.reader.bbcode_enabled and "[b]" in panel.reader.text,"Mail cannot inject markup")
	panel.compose(panel.current);check(panel.recipient.text=="Tester" and panel.subject.text=="Re: Hello","Reply addresses original sender")
	var keyboard=preload("res://ui/virtual_keyboard.gd").new();root.add_child(keyboard);keyboard.target_viewport=root;keyboard.position=Vector2(0,910)
	panel.subject.grab_focus();panel.subject.text="";await process_frame
	keyboard.press_key("h","H");keyboard.press_key("Shift",KEY_SHIFT);keyboard.press_key("i","I");keyboard.press_key("Space",KEY_SPACE);keyboard.press_key("1","!")
	check(panel.subject.text=="hI 1","Virtual keyboard inserts text and shifted characters into focused field")
	keyboard.press_key("Backspace",KEY_BACKSPACE);check(panel.subject.text=="hI ","Virtual keyboard backspace edits field")
	panel.body.grab_focus();keyboard.press_key("a","A");keyboard.press_key("Enter",KEY_ENTER);keyboard.press_key("b","B")
	check(panel.body.text=="a\nb","Virtual keyboard supports multiline mail")
	panel.show_bank("55",1000,100);panel.recipient.text="Tester";panel.submit()
	check(requests.back().action=="bank_quote","Pay first requests native quote")
	panel.outcome("bank_quote",{"ok":true,"mutation":{"quote":{"recipient":"Tester","recipient_id":"9","amount":100,"fee":5,"total":105}}});panel.submit()
	check(requests.back().action=="bank_pay" and requests.back().payload.fee==5 and requests.back().payload.recipient_id=="9","Payment includes reviewed native recipient and fee")
	panel.recipient.grab_focus();keyboard.press_key("a","A");await process_frame;check(panel.quote.is_empty(),"Editing recipient invalidates quote")
	panel.set_pending(true);check(panel.navigation.all(func(b):return b.disabled) and not panel.recipient.editable,"Pending request locks editing and mode changes")
	panel.set_pending(false);panel.hide();keyboard.hide()
	var scroller:=ScrollContainer.new();root.add_child(scroller);scroller.position=Vector2(20,20);scroller.size=Vector2(400,220)
	var content:=VBoxContainer.new();scroller.add_child(content);var clicks:Array=[]
	for i in 30:
		var b:=Button.new();b.text="Row %d"%i;b.custom_minimum_size=Vector2(350,50);content.add_child(b);b.pressed.connect(func():clicks.append(i))
	var drag=preload("res://ui/drag_scroll.gd").new();root.add_child(drag)
	await process_frame;await process_frame
	mouse(root,Vector2(100,180),true)
	var move:=InputEventMouseMotion.new();move.position=Vector2(100,65);root.push_input(move,true);mouse(root,Vector2(100,65),false)
	check(scroller.scroll_vertical>80 and clicks.is_empty(),"Dragging scrolls button lists without activating a row")
	mouse(root,Vector2(100,90),true);mouse(root,Vector2(100,90),false)
	check(clicks.size()==1,"A stationary click still activates its row")
	for control in [ItemList.new(),RichTextLabel.new(),TextEdit.new()]:
		root.add_child(control);control.position=Vector2(500,20);control.size=Vector2(400,220)
		if control is ItemList:
			for i in 100:control.add_item("Row %d"%i)
		else:control.text="Scrollable line\n".repeat(100)
		await process_frame;await process_frame
		check(drag.begin(control,Vector2(550,190)),"Scroll control accepts drag: "+control.get_class());drag.move(Vector2(550,60));drag.finish(Vector2(550,60))
		check(control.get_v_scroll_bar().value>0,"Scroll control moves: "+control.get_class());control.free()
	var interaction=preload("res://scripts/corpse_interaction.gd")
	check(interaction.coin_position(AABB(Vector3(0,0,0),Vector3(2,8,3)),0).y<=1.20001,"Large corpse loot marker capped at chest height")
	var corpses=preload("res://scripts/corpse_visuals.gd").new();root.add_child(corpses);corpses.set_process(false);corpses.set_physics_process(false)
	var coin:=Node3D.new();corpses.add_child(coin);corpses.coins["native-dead"]=coin
	corpses.confirm_looted("native-dead")
	check(not corpses.coins.has("native-dead") and corpses.looted.has("native-dead"),"Confirmed empty loot removes marker and prevents stale snapshot resurrection")
	corpses.free()
	var assets=preload("res://scripts/inventory_assets.gd").new();assets.configure()
	for template in ["object/tangible/loot/misc/ledger_s01.iff","object/tangible/loot/misc/damaged_datapad.iff"]:
		check(assets.model(template)!=null,"Original junk model loads: "+template)
	panel.free();keyboard.free();scroller.free();drag.free()
	var report:Dictionary={"passed":failures.is_empty(),"checks":checks,"errors":failures,"renderer":"dummy","headset_tested":false}
	FileAccess.open("res://../runtime/evidence/mail-ui-smoke.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "));print(JSON.stringify(report));quit(0 if failures.is_empty() else 1)
