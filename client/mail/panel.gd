extends PanelContainer
signal action_requested(action:String,payload:Dictionary)
signal close_requested
const Holo=preload("res://scripts/datapad_theme.gd")
var mode:="inbox"
var pending:=false
var page:=0
var selected_id:=""
var messages:Array=[]
var current:Dictionary={}
var quote:Dictionary={}
var bank_terminal:=""
var list:ItemList
var reader:RichTextLabel
var recipient:LineEdit
var subject:LineEdit
var body:TextEdit
var status:Label
var primary:Button
var delete_button:Button
var reply_button:Button
var previous:Button
var next:Button
var fields:VBoxContainer
var inbox:HBoxContainer
var attachments:HBoxContainer
var bank_amount:Control
var probe_choice:OptionButton
var tool_choice:OptionButton
var planet_choice:OptionButton
var probe_data:Dictionary={}
var delete_armed:=false
var probe_id:=""
var navigation:Array[Button]=[]
var has_more:=false

func button(parent:Node,label:String,callback:Callable)->Button:
	var b:=Button.new();b.text=label;b.custom_minimum_size.y=50;b.pressed.connect(callback);parent.add_child(b);return b
func label(parent:Node,value:String)->Label:
	var l:=Label.new();l.text=value;parent.add_child(l);return l
func _ready()->void:
	theme=Holo.build();add_theme_stylebox_override("panel",Holo.frame(24,"wide"))
	var column:=VBoxContainer.new();add_child(column)
	var header:=HBoxContainer.new();column.add_child(header)
	var title:=label(header,"COMMUNICATIONS");title.size_flags_horizontal=SIZE_EXPAND_FILL
	navigation.append(button(header,"Inbox",func():show_mode("inbox");action_requested.emit("mail_list",{"page":page})))
	navigation.append(button(header,"Compose",func():compose()))
	navigation.append(button(header,"Survey probes",func():show_mode("probe");action_requested.emit("probe_status",{})))
	button(header,"Close",func():close_requested.emit())
	status=label(column,"");status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	inbox=HBoxContainer.new();column.add_child(inbox);inbox.size_flags_vertical=SIZE_EXPAND_FILL
	list=ItemList.new();inbox.add_child(list);list.custom_minimum_size.x=500;list.size_flags_vertical=SIZE_EXPAND_FILL;list.item_selected.connect(select_mail)
	var detail:=VBoxContainer.new();inbox.add_child(detail);detail.size_flags_horizontal=SIZE_EXPAND_FILL
	reader=RichTextLabel.new();detail.add_child(reader);reader.size_flags_vertical=SIZE_EXPAND_FILL;reader.bbcode_enabled=false
	attachments=HBoxContainer.new();detail.add_child(attachments)
	var actions:=HBoxContainer.new();detail.add_child(actions)
	reply_button=button(actions,"Reply",func():compose(current));delete_button=button(actions,"Delete",delete_mail)
	previous=button(actions,"Previous",func():if page>0:action_requested.emit("mail_list",{"page":page-1}))
	next=button(actions,"Next",func():action_requested.emit("mail_list",{"page":page+1}))
	fields=VBoxContainer.new();column.add_child(fields);fields.size_flags_vertical=SIZE_EXPAND_FILL
	recipient=LineEdit.new();fields.add_child(recipient);recipient.placeholder_text="Recipient’s first character name";recipient.max_length=40;recipient.custom_minimum_size.y=52;recipient.text_changed.connect(func(_s):invalidate_quote())
	subject=LineEdit.new();fields.add_child(subject);subject.placeholder_text="Subject";subject.max_length=128;subject.custom_minimum_size.y=52
	body=TextEdit.new();fields.add_child(body);body.placeholder_text="Message (up to 4,000 characters)";body.size_flags_vertical=SIZE_EXPAND_FILL;body.wrap_mode=TextEdit.LINE_WRAPPING_BOUNDARY
	bank_amount=preload("res://scripts/service_amount_slider.gd").new();fields.add_child(bank_amount);bank_amount.custom_minimum_size=Vector2(580,100);bank_amount.amount_changed.connect(func(_n):invalidate_quote())
	probe_choice=OptionButton.new();fields.add_child(probe_choice);probe_choice.custom_minimum_size.y=54
	tool_choice=OptionButton.new();fields.add_child(tool_choice);tool_choice.custom_minimum_size.y=54
	planet_choice=OptionButton.new();fields.add_child(planet_choice);planet_choice.custom_minimum_size.y=54
	probe_choice.item_selected.connect(func(_i):probe_details());tool_choice.item_selected.connect(func(_i):probe_details())
	primary=button(fields,"Send",submit)
	show_mode("inbox")

func show_mode(value:String)->void:
	mode=value;quote={};delete_armed=false;delete_button.text="Delete"
	inbox.visible=mode=="inbox";fields.visible=not inbox.visible
	recipient.visible=mode in ["compose","bank"];subject.visible=mode=="compose";body.visible=mode=="compose"
	bank_amount.visible=mode=="bank"
	for choice in [probe_choice,tool_choice,planet_choice]:choice.visible=mode=="probe"
	primary.text={"compose":"Send mail","bank":"Review payment","probe":"Launch survey probe"}.get(mode,"")
	status.text={"inbox":"","compose":"Write to another character in this galaxy.","bank":"Bank-to-bank transfer. Review the recipient and native fee before sending.","probe":"The probe consumes one probe use and the selected survey tool. Its report arrives by mail."}.get(mode,"")
	set_pending(pending)

func compose(reply:Dictionary={})->void:
	show_mode("compose");recipient.text=str(reply.get("sender",""));subject.text=("Re: "+str(reply.get("subject",""))).left(128) if not reply.is_empty() else "";body.text="";recipient.grab_focus()
func show_bank(terminal_id:String,balance:int,amount:int=0)->void:
	show_mode("bank");bank_terminal=terminal_id;recipient.text="";bank_amount.configure(balance,amount);recipient.grab_focus()
func invalidate_quote()->void:
	quote={}
	if mode=="bank":primary.text="Review payment"
func set_pending(value:bool)->void:
	pending=value
	for control in navigation:control.disabled=value
	for control in [primary,delete_button,reply_button,previous,next,probe_choice,tool_choice,planet_choice]:control.disabled=value
	previous.disabled=value or page==0;next.disabled=value or not has_more
	recipient.editable=not value;subject.editable=not value;body.editable=not value;bank_amount.enabled=not value
func set_mail(state:Dictionary)->void:
	if not state.has("messages"):return
	has_more=bool(state.get("has_more",false));page=int(state.get("page",0));messages=state.messages.duplicate(true);list.clear()
	for row in messages:
		list.add_item(("• " if not row.get("read",false) else "")+str(row.sender)+"\n"+str(row.subject))
		if str(row.id)==selected_id:list.select(list.item_count-1)
	previous.disabled=pending or page==0;next.disabled=pending or not state.get("has_more",false)
	if mode=="inbox":status.text="%d messages · %d unread"%[int(state.get("total",0)),int(state.get("unread",0))]
func select_mail(index:int)->void:
	if pending or index<0 or index>=messages.size():return
	selected_id=str(messages[index].id);delete_armed=false;delete_button.text="Delete";action_requested.emit("mail_read",{"mail_id":selected_id,"page":page})
func show_message(message:Dictionary)->void:
	if str(message.get("id",""))!=selected_id:return
	current=message.duplicate(true);reader.text=str(message.subject)+"\nFrom: "+str(message.sender)+"\n\n"+str(message.body)
	for child in attachments.get_children():child.queue_free()
	for point in message.get("waypoints",[]):
		button(attachments,"Save "+str(point.get("waypointName","waypoint")),func():action_requested.emit("mail_waypoint",{"mail_id":selected_id,"index":int(point.index)}))
func delete_mail()->void:
	if pending or selected_id.is_empty():return
	if not delete_armed:delete_armed=true;delete_button.text="Confirm delete";return
	action_requested.emit("mail_delete",{"mail_id":selected_id,"page":page})
func set_probes(data:Dictionary)->void:
	probe_data=data.duplicate(true)
	for choice in [probe_choice,tool_choice,planet_choice]:choice.clear()
	for row in data.get("probes",[]):
		probe_choice.add_item(str(row.name));probe_choice.set_item_metadata(probe_choice.item_count-1,row.id)
		if str(row.id)==probe_id:probe_choice.select(probe_choice.item_count-1)
	for row in data.get("tools",[]):tool_choice.add_item(str(row.name));tool_choice.set_item_metadata(tool_choice.item_count-1,row.id)
	for planet in data.get("planets",[]):planet_choice.add_item(str(planet).capitalize());planet_choice.set_item_metadata(planet_choice.item_count-1,planet)
	probe_details()
func probe_details()->void:
	if mode!="probe":return
	if not probe_data.get("eligible",false):status.text="The Survey ability is required.";return
	if probe_choice.item_count==0 or tool_choice.item_count==0:status.text="Carry an interplanetary survey probe and a survey tool, including inside your backpack.";return
	var seconds:int=probe_data.probes[probe_choice.selected].duration_seconds
	status.text="Consumes one probe use and the selected survey tool. Report by mail in about %d minutes."%ceili(seconds/60.0)
func submit()->void:
	if pending:return
	if mode=="compose":
		if recipient.text.strip_edges().is_empty() or subject.text.strip_edges().is_empty() or body.text.strip_edges().is_empty() or body.text.length()>4000:status.text="Enter recipient, subject and a message of 1–4,000 characters.";return
		action_requested.emit("mail_send",{"recipient":recipient.text,"subject":subject.text,"body":body.text})
	elif mode=="bank":
		if quote.is_empty():action_requested.emit("bank_quote",{"terminal_id":bank_terminal,"recipient":recipient.text,"amount":bank_amount.amount})
		else:action_requested.emit("bank_pay",{"terminal_id":bank_terminal,"recipient":quote.recipient,"recipient_id":quote.recipient_id,"amount":quote.amount,"fee":quote.fee})
	elif mode=="probe":
		if not probe_data.get("eligible",false) or probe_choice.item_count==0 or tool_choice.item_count==0 or planet_choice.item_count==0:return
		action_requested.emit("probe_launch",{"probe_id":str(probe_choice.get_selected_metadata()),"tool_id":str(tool_choice.get_selected_metadata()),"target_planet":str(planet_choice.get_selected_metadata())})
func outcome(action:String,response:Dictionary)->void:
	set_pending(false)
	if not response.get("ok",false):status.text=str(response.get("error","Request not confirmed. Retry to check the same operation."));return
	var mutation:Dictionary=response.get("mutation",{})
	if action=="mail_read":show_message(mutation.get("message",{}))
	if action=="mail_send":body.text="";subject.text="";status.text="Mail sent."
	if action=="mail_delete":selected_id="";current={};reader.text="";delete_armed=false;delete_button.text="Delete"
	if action=="mail_waypoint":status.text="Waypoint saved to your datapad."
	if action=="bank_quote":
		quote=mutation.get("quote",{});status.text="To %s: %d credits + %d fee = %d credits from your bank."%[quote.get("recipient",""),int(quote.get("amount",0)),int(quote.get("fee",0)),int(quote.get("total",0))];primary.text="Send payment"
	if action=="bank_pay":quote={};bank_amount.amount=0;primary.text="Review payment";status.text="Payment completed. Both players receive bank receipts by mail."
	if action=="probe_launch":status.text="Probe launched. Report due in about %d minutes; watch the minimap mail icon."%ceili(int(mutation.get("duration_seconds",0))/60.0)
