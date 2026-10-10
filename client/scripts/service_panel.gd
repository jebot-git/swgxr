extends Control
## Compact local-only service UI. All values and entries come from Core3.
signal action_requested(action: String, payload: Dictionary)
signal close_requested
const Holo=preload("res://scripts/datapad_theme.gd")
const AmountSlider=preload("res://scripts/service_amount_slider.gd")
const FONT=preload("res://resources/fonts/Jupiteroid-Regular.ttf")
const ROWS_RECT=Rect2(20,128,548,352)
const ROW_HEIGHT=44.0
const CATEGORY_RECT=Rect2(20,128,218,352)
const BAZAAR_ROWS_RECT=Rect2(248,128,320,352)
const BAZAAR_REFRESH=Rect2(228,488,148,52)
const PAGE_PREVIOUS=Rect2(386,488,86,52)
const PAGE_NEXT=Rect2(482,488,86,52)
const CONFIRM_RECT=Rect2(590,488,250,52)
const BOARDING_RECT=Rect2(228,488,340,52)
const REFRESH_RECT=Rect2(20,488,190,52)
const CLOSE_RECT=Rect2(808,12,40,40)
var player_position:=Vector3.INF
var player_planet:=""
var terminal: Dictionary={}
var wallet: Dictionary={"cash":0,"bank":0}
var rows: Array=[]
var tickets: Array=[]
var travel_overview=preload("res://scripts/travel_overview.gd").new()
const TRAVEL_ROWS_RECT=Rect2(20,128,390,352)
var selected := -1
var offset := 0.0
var pending := false
var message := ""
var direction := "deposit"
var bid_mode := false
var categories: Array=[]
var category_rows: Array=[]
var category_path: Array=[]
var category_id:=0
var category_name:="All"
var category_offset:=0
var category_selected:=-1
var drag_category:=false
var page:=0
var has_more:=false
var search_scope:="galaxy"
const SEARCH_SCOPES=["local","planet","galaxy","vendor"]
const SCOPE_RECT=Rect2(20,66,548,38)
var target_id := ""
var slider: Control
var faction_sliders: Dictionary={}
var pointer_down := false
var drag_scrolling := false
var down_pixel := Vector2.ZERO
var last_pixel := Vector2.ZERO
var down_row := -1
var dragged := false
var scroll_residual := 0.0
var navigation_anchor:=Vector2.INF
var navigation_category:=false
var delivery_dialogue:RichTextLabel

func _ready() -> void:
	theme=Holo.build()
	size=Vector2(860,620)
	mouse_filter=Control.MOUSE_FILTER_STOP
	slider=AmountSlider.new()
	add_child(slider)
	slider.position=Vector2(148,290)
	slider.mouse_filter=Control.MOUSE_FILTER_IGNORE
	slider.amount_changed.connect(func(_amount): queue_redraw())
	slider.visible=false
	for faction in ["imperial","rebel"]:
		var currency:=AmountSlider.new();add_child(currency);faction_sliders[faction]=currency
		currency.currency_unit=faction.capitalize()+" FP";currency.position=Vector2(148,290 if faction=="imperial" else 380)
		currency.mouse_filter=Control.MOUSE_FILTER_IGNORE;currency.hide()
		currency.amount_changed.connect(func(_amount):queue_redraw())
	delivery_dialogue=RichTextLabel.new();add_child(delivery_dialogue);delivery_dialogue.position=Vector2(40,125);delivery_dialogue.size=Vector2(770,270);delivery_dialogue.mouse_filter=Control.MOUSE_FILTER_IGNORE;delivery_dialogue.add_theme_font_override("normal_font",FONT);delivery_dialogue.add_theme_font_size_override("normal_font_size",24);delivery_dialogue.add_theme_color_override("default_color",Color("d2f6ff"));delivery_dialogue.hide()

func configure(record: Dictionary, balances: Dictionary, held_tickets: Array=[]) -> void:
	var upkeep_mode:bool=terminal.get("kind","")=="house_deposit" and str(terminal.get("id",""))==str(record.get("id",""))
	var previous_id:=str(terminal.get("id",""))
	navigation_anchor=Vector2.INF
	terminal=record.duplicate(true)
	if upkeep_mode and terminal.get("kind","")=="house":terminal.kind="house_deposit"
	if terminal.get("kind","")=="vendor":terminal.kind="bazaar";terminal.market_kind="vendor"
	if is_instance_valid(delivery_dialogue):
		delivery_dialogue.visible=terminal.get("kind","") in ["delivery","underworld","bounty_informant","pilot_trainer"]
		delivery_dialogue.position=Vector2(590,125) if terminal.get("kind","")=="pilot_trainer" else Vector2(40,125)
		delivery_dialogue.size=Vector2(242,370) if terminal.get("kind","")=="pilot_trainer" else Vector2(770,270)
		delivery_dialogue.mouse_filter=Control.MOUSE_FILTER_STOP if terminal.get("kind","")=="pilot_trainer" else Control.MOUSE_FILTER_IGNORE
		delivery_dialogue.text=str(terminal.get("dialogue","Waiting for the mission contact…"))
		if terminal.get("kind","")=="underworld" and not terminal.get("eligible",false) and not str(terminal.get("blocked_reason","")).is_empty():delivery_dialogue.text+="\n\n"+str(terminal.blocked_reason)
	if terminal.get("kind","")=="bazaar":
		search_scope=str(terminal.get("search_scope","galaxy" if previous_id!=str(terminal.get("id","")) else search_scope))
		var source_categories: Array=terminal.get("categories",[])
		if previous_id!=str(terminal.get("id","")) or source_categories!=categories:
			categories=source_categories.duplicate(true)
			category_rows=categories.duplicate(true);category_path=[];category_offset=0;category_selected=-1;category_id=0;category_name="All"
		page=int(terminal.get("page",0));has_more=bool(terminal.get("has_more",false))
	wallet=balances.duplicate(true)
	tickets=held_tickets.duplicate(true)
	rows=[]
	match str(terminal.get("kind","")):
		"bazaar": rows=terminal.get("listings",[]).duplicate(true)
		"mission": rows=terminal.get("missions",[]).duplicate(true)
		"travel": rows=terminal.get("destinations",[]).duplicate(true)
		"boarding": rows=tickets.duplicate(true)
		"crafting": rows=terminal.get("tools",[]).duplicate(true)
		"trainer": rows=terminal.get("skills",[]).duplicate(true)
		"starship": rows=terminal.get("ships",[]).duplicate(true)
		"ship_crew": rows=terminal.get("members",[]).duplicate(true)
		"house","ship_control","bounty_droid","pilot_trainer","chassis_dealer","ship_outfit": rows=terminal.get("options",[]).duplicate(true)
	if selected>=rows.size(): selected=-1
	offset=clampf(offset,0,maxf(0,rows.size()-8))
	pending=false
	bid_mode=false
	cancel_pointer()
	slider.visible=str(terminal.get("kind","")) in ["bank","payment","house_deposit"]
	if previous_id!=str(terminal.get("id","")):
		slider.amount=0
		for currency in faction_sliders.values():currency.amount=0
	update_limit()
	queue_redraw()

func update_limit() -> void:
	if not is_instance_valid(slider): return
	var delegation:bool=terminal.get("kind","")=="payment" and bool(wallet.get("faction_delegation",false))
	slider.position.y=200 if delegation else 290
	for faction in faction_sliders:
		var currency:Control=faction_sliders[faction];currency.visible=delegation
		currency.configure(int(wallet.get("faction_limits",{}).get(faction,0)),currency.amount if delegation else 0)
	if bid_mode and selected>=0 and selected<rows.size():
		var minimum:=int(rows[selected].get("min_bid",int(rows[selected].get("price",0))+1))
		slider.configure_range(minimum,maxi(minimum,int(wallet.get("cash",0))+int(wallet.get("bank",0))),maxi(minimum,slider.amount))
		return
	var maximum:=int(wallet.get("cash",0)) if direction=="deposit" or terminal.get("kind","") in ["payment","house_deposit"] else int(wallet.get("bank",0))
	slider.configure(maximum,slider.amount)

func set_pending(value: bool) -> void:
	pending=value
	slider.enabled=not value
	for currency in faction_sliders.values():currency.enabled=not value
	if value: cancel_pointer()
	queue_redraw()

func row_at(pixel: Vector2) -> int:
	var region:=BAZAAR_ROWS_RECT if terminal.get("kind","")=="bazaar" else TRAVEL_ROWS_RECT if terminal.get("kind","")=="travel" else ROWS_RECT
	if not region.has_point(pixel): return -1
	var index:=int((pixel.y-ROWS_RECT.position.y)/ROW_HEIGHT)+int(offset)
	return index if index>=0 and index<rows.size() else -1

func pointer_begin(pixel: Vector2) -> void:
	if pending: return
	pointer_down=true
	down_pixel=pixel
	last_pixel=pixel
	down_row=row_at(pixel)
	dragged=false
	scroll_residual=0
	for currency in faction_sliders.values():
		if currency.visible and currency.begin_drag(pixel-currency.position):
			dragged=true;drag_scrolling=false;return
	if slider.visible and slider.begin_drag(pixel-slider.position):
		dragged=true
		drag_scrolling=false
	else:
		drag_category=terminal.get("kind","")=="bazaar" and CATEGORY_RECT.has_point(pixel)
		drag_scrolling=ROWS_RECT.has_point(pixel) and not slider.visible

func pointer_move(pixel: Vector2) -> void:
	if not pointer_down or pending: return
	if pixel.distance_to(down_pixel)>12: dragged=true
	for currency in faction_sliders.values():
		if currency.dragging:currency.drag_to(pixel-currency.position);last_pixel=pixel;return
	if slider.dragging: slider.drag_to(pixel-slider.position)
	elif drag_scrolling and dragged:
		scroll_residual+=last_pixel.y-pixel.y
		if absf(scroll_residual)>=ROW_HEIGHT:
			var steps:=int(scroll_residual/ROW_HEIGHT)
			if drag_category: category_offset=clampi(category_offset+steps,0,maxi(0,category_rows.size()-8))
			else: offset=clampf(offset+steps,0,maxf(0,rows.size()-8))
			scroll_residual-=steps*ROW_HEIGHT
			queue_redraw()
	last_pixel=pixel

func pointer_end(pixel: Vector2) -> void:
	if not pointer_down: return
	var click:=not dragged and pixel.distance_to(down_pixel)<16 and not pending
	cancel_pointer()
	if click: click_at(navigation_target(pixel))

func cancel_pointer() -> void:
	pointer_down=false
	drag_scrolling=false
	if is_instance_valid(slider): slider.cancel_drag()
	for currency in faction_sliders.values():currency.cancel_drag()

func scroll_at(pixel: Vector2, steps: int) -> void:
	if pending or slider.visible or not ROWS_RECT.has_point(pixel):return
	if terminal.get("kind","")=="bazaar" and CATEGORY_RECT.has_point(pixel):
		category_offset=clampi(category_offset+steps,0,maxi(0,category_rows.size()-8))
	else:offset=clampf(offset+steps,0,maxf(0,rows.size()-8))
	# A stick/wheel scroll while pressing must not select its final hovered row.
	if pointer_down:dragged=true
	queue_redraw()

func navigate_at(pixel: Vector2, steps: int) -> void:
	if pending or slider.dragging or steps==0 or not ROWS_RECT.has_point(pixel):return
	if terminal.get("kind","")=="bazaar" and CATEGORY_RECT.has_point(pixel):
		if category_rows.is_empty():return
		category_selected=clampi((category_offset if category_selected<0 else category_selected+steps),0,category_rows.size()-1)
		category_offset=clampi(category_offset, maxi(0,category_selected-7), category_selected)
	else:
		if rows.is_empty():return
		selected=clampi((int(offset) if selected<0 else selected+steps),0,rows.size()-1)
		offset=clampf(offset,maxi(0,selected-7),selected)
	navigation_anchor=pixel
	navigation_category=terminal.get("kind","")=="bazaar" and CATEGORY_RECT.has_point(pixel)
	if pointer_down:dragged=true
	queue_redraw()

func confirm_navigation() -> bool:
	if pending or pointer_down or slider.dragging or not navigation_anchor.is_finite():return false
	if navigation_category:
		if category_selected<0 or category_selected>=category_rows.size():return false
	elif selected<0 or selected>=rows.size():return false
	click_at(navigation_target(navigation_anchor))
	return true

func navigation_target(pixel:Vector2)->Vector2:
	if pixel.distance_to(navigation_anchor)>12:return pixel
	if navigation_category and category_selected>=0:
		return Vector2(CATEGORY_RECT.get_center().x,128+(category_selected-category_offset+.5)*ROW_HEIGHT)
	if selected>=0:
		var region:=BAZAAR_ROWS_RECT if terminal.get("kind","")=="bazaar" else TRAVEL_ROWS_RECT if terminal.get("kind","")=="travel" else ROWS_RECT
		return Vector2(region.get_center().x,128+(selected-int(offset)+.5)*ROW_HEIGHT)
	return pixel

func browse_payload() -> Dictionary:
	return {"terminal_id":str(terminal.get("id","")),"category_id":category_id,"page":page,"search_scope":search_scope}

func select_scope(index:int)->void:
	if pending or index<0 or index>=SEARCH_SCOPES.size():return
	search_scope=SEARCH_SCOPES[index];page=0;offset=0;selected=-1
	request_browse()

func request_browse() -> void:
	rows=[] # A rejected filter request must never relabel results from its parent.
	set_pending(true)
	action_requested.emit("open",browse_payload())

func select_category(index: int) -> void:
	if pending or index<0 or index>=category_rows.size(): return
	var row: Dictionary=category_rows[index]
	var identifier:=int(row.get("id",0))
	if identifier!=category_id:
		category_path.append({"id":category_id,"name":category_name,"rows":category_rows.duplicate(true),"offset":category_offset,"selected":index,"page":page,"item_offset":offset,"item_selected":selected})
		category_id=identifier;category_name=str(row.get("label",row.get("name",identifier)))
		category_rows=row.get("children",[]).duplicate(true);category_offset=0;category_selected=-1
	else: category_selected=index
	page=0;offset=0;selected=-1;bid_mode=false;slider.visible=false
	request_browse()

func category_back() -> void:
	if pending or category_path.is_empty(): return
	var previous: Dictionary=category_path.pop_back()
	category_id=int(previous.id);category_name=str(previous.name)
	category_rows=previous.rows;category_offset=int(previous.offset);category_selected=int(previous.selected)
	page=int(previous.page);offset=float(previous.item_offset);selected=int(previous.item_selected)
	request_browse()

func click_at(pixel: Vector2) -> void:
	if pending: return
	if CLOSE_RECT.has_point(pixel): close_requested.emit(); return
	if terminal.get("kind","") in ["travel","ticket_collector"] and BOARDING_RECT.has_point(pixel):
		action_requested.emit("travel_tickets",{"terminal_id":str(terminal.get("id",""))});return
	if terminal.get("kind","")=="bazaar" and not bid_mode and SCOPE_RECT.has_point(pixel):
		select_scope(int((pixel.x-SCOPE_RECT.position.x)/(SCOPE_RECT.size.x/4)));return
	if terminal.get("kind","")=="travel" and travel_overview.RECT.has_point(pixel):
		var destination:int=travel_overview.select_at(pixel,rows,selected)
		if destination>=0:selected=destination;offset=clampf(offset,maxi(0,selected-7),selected);queue_redraw()
		return
	if terminal.get("kind","")=="ship_crew":
		if REFRESH_RECT.has_point(pixel):close_requested.emit();return
		if ROWS_RECT.has_point(pixel):
			var member:=row_at(pixel)
			if member>=0 and str(rows[member].get("id",""))!=str(terminal.get("pilot_id","")) and terminal.get("is_pilot",false):
				set_pending(true);action_requested.emit("jtl_crew_remove",{"member_id":str(rows[member].id)})
			return
	if terminal.get("kind","")=="house_deposit" and REFRESH_RECT.has_point(pixel):
		terminal.kind="house";slider.visible=false;rows=terminal.get("options",[]).duplicate(true);selected=-1;queue_redraw();return
	if REFRESH_RECT.has_point(pixel) and bid_mode:
		bid_mode=false;slider.visible=false;queue_redraw();return
	if terminal.get("kind","")=="bazaar" and not bid_mode:
		if CATEGORY_RECT.has_point(pixel):
			select_category(category_offset+int((pixel.y-CATEGORY_RECT.position.y)/ROW_HEIGHT));return
		if REFRESH_RECT.has_point(pixel):
			if not category_path.is_empty(): category_back()
			return
		if BAZAAR_REFRESH.has_point(pixel): request_browse();return
		if PAGE_PREVIOUS.has_point(pixel) and page>0: page-=1;offset=0;selected=-1;request_browse();return
		if PAGE_NEXT.has_point(pixel) and has_more: page+=1;offset=0;selected=-1;request_browse();return
	if REFRESH_RECT.has_point(pixel) and terminal.get("kind","")=="starship":
		if selected>=0 and selected<rows.size():action_requested.emit("ship_manage",{"terminal_id":str(terminal.id),"ship_id":str(rows[selected].id)})
		return
	if REFRESH_RECT.has_point(pixel) and terminal.get("kind","")=="ship_outfit":
		action_requested.emit("open",{"terminal_id":str(terminal.id)});return
	if REFRESH_RECT.has_point(pixel) and terminal.get("kind","") in ["bazaar","mission","travel","trainer"]:
		set_pending(true)
		action_requested.emit("mission_refresh" if terminal.get("kind","")=="mission" else "open",browse_payload() if terminal.get("kind","")=="bazaar" else {"terminal_id":str(terminal.get("id",""))})
		return
	if slider.visible:
		if terminal.get("kind","")=="bank" and Rect2(170,192,520,60).has_point(pixel):
			direction="deposit" if pixel.x<430 else "withdraw"
			update_limit();queue_redraw();return
	elif ROWS_RECT.has_point(pixel):
		selected=row_at(pixel)
		if terminal.get("kind","")=="bounty_droid":confirm();return
		if terminal.get("kind","")=="bazaar" and selected>=0 and bool(rows[selected].get("auction",false)) and bool(rows[selected].get("buy_eligible",true)):
			bid_mode=true;slider.visible=true;slider.amount=0;update_limit()
		queue_redraw();return
	if CONFIRM_RECT.has_point(pixel): confirm()

func mission_blocked_reason(row: Dictionary) -> String:
	if bool(row.get("supported",true)): return ""
	var reason:=str(row.get("blocked_reason","")).strip_edges()
	return reason if not reason.is_empty() else "The required mission interaction is not available in this prototype."

func trainer_blocked_reason(row: Dictionary) -> String:
	if bool(row.get("learned",false)): return "Already learned."
	if bool(row.get("eligible",false)): return ""
	var reason:=str(row.get("blocked_reason","")).strip_edges()
	return reason if not reason.is_empty() else "CoreCU has not confirmed eligibility for this skill."

func trainer_skill_name(identifier: String) -> String:
	for skill: Dictionary in rows:
		if str(skill.get("id",""))==identifier: return label_for(skill)
	return identifier

func confirm() -> void:
	if pending: return
	var kind:=str(terminal.get("kind",""))
	var payload: Dictionary={"terminal_id":str(terminal.get("id",""))}
	var action:=""
	if kind=="bazaar": payload.merge(browse_payload(),true)
	if kind in ["bank","payment","house_deposit"]:
		var points:Dictionary={}
		if kind=="payment" and wallet.get("faction_delegation",false):
			for faction in faction_sliders:
				if faction_sliders[faction].amount>0:points[faction]=faction_sliders[faction].amount
		if slider.amount<=0 and points.is_empty(): return
		if not points.is_empty():payload.faction_points=points
		payload.amount=slider.amount
		if kind=="house_deposit":action="house_deposit"
		elif kind=="bank": action="bank_transfer";payload.direction=direction
		else:
			if target_id.is_empty(): return
			action="pay";payload.target_id=target_id;payload.erase("terminal_id")
	elif kind=="starship":
		if selected<0 or selected>=rows.size():return
		if not rows[selected].get("eligible",false):message=str(rows[selected].get("reason","This ship cannot launch."));queue_redraw();return
		action="jtl_launch"
		if str(rows[selected].get("id",""))!="starter":payload.ship_id=str(rows[selected].get("id",""))
	elif kind=="ship_crew":
		if not terminal.get("is_pilot",false) or str(terminal.get("launch_id","")).is_empty():return
		action="jtl_launch_confirm";payload.launch_id=str(terminal.launch_id)
	elif kind=="ship_control":
		if selected<0 or selected>=rows.size():return
		action="ship_terminal_command";payload.command_id=rows[selected].command_id
	elif kind=="house" and terminal.get("pob",false):
		if selected<0 or selected>=rows.size():return
		action="pob_recover";payload.item_id=rows[selected].item_id
	elif kind=="house":
		if selected<0 or selected>=rows.size():return
		var choice:Dictionary=rows[selected]
		if choice.get("id","")=="deposit":
			terminal.kind="house_deposit";slider.visible=true;slider.amount=0;update_limit();queue_redraw();return
		action="house_permission_arm";payload.permission_list=choice.permission_list;payload.permission_action=choice.permission_action
	elif kind=="bounty_informant":
		if not terminal.get("eligible",false):return
		action="bounty_informant"
		payload={"target_id":str(terminal.get("id",""))}
	elif kind=="bounty_droid":
		if selected<0 or selected>=rows.size() or not rows[selected].get("enabled",false):return
		action="bounty_probe"
		payload={"item_id":str(terminal.get("item_id","")),"search_planet":str(rows[selected].get("id",""))}
	elif kind=="underworld":
		if not terminal.get("eligible",false) or terminal.get("confirm_action","")!="underworld_accept":return
		action="underworld_accept"
	elif kind=="delivery":
		if str(terminal.get("confirm_action",""))!="delivery_pickup":
			message="Grip and pull the parcel from Data, present it to the recipient, and press trigger.";queue_redraw();return
		action="delivery_pickup";payload={"npc_id":str(terminal.get("id","")),"mission_id":str(terminal.get("mission_id",""))}
	elif kind in ["ship_outfit","chassis_dealer"]:
		if selected<0 or selected>=rows.size():return
		var option:Dictionary=rows[selected];action=str(option.operation)
		for key in ["slot","component_id","item_id","price"]:
			if option.has(key):payload[key]=option[key]
		if kind=="ship_outfit":payload.ship_id=str(terminal.ship_id)
	elif kind=="pilot_trainer":
		if selected<0 or selected>=rows.size():return
		var option:Dictionary=rows[selected]
		action="pilot_begin" if option.get("begin",false) else "pilot_choose"
		if action=="pilot_choose":payload.option=int(option.option);payload.screen_token=str(terminal.get("screen_token",""))
	elif kind=="trainer":
		if selected<0 or selected>=rows.size(): return
		var skill: Dictionary=rows[selected]
		var blocked:=trainer_blocked_reason(skill)
		if not blocked.is_empty(): message=blocked;queue_redraw();return
		var skill_id:=str(skill.get("id",""))
		if skill_id.is_empty(): return
		action="trainer_train";payload.skill_id=skill_id
	elif kind=="crafting":
		if selected<0 or selected>=rows.size(): return
		action="crafting_station";payload.tool_id=str(rows[selected].get("id",""))
	else:
		if selected<0 or selected>=rows.size(): return
		var row: Dictionary=rows[selected]
		match kind:
			"bazaar":
				action="bazaar_retrieve" if bool(row.get("retrieve_eligible",false)) else "bazaar_buy"
				if action=="bazaar_buy" and not bool(row.get("buy_eligible",true)): return
				payload.listing_id=str(row.get("id",row.get("listing_id","")))
				payload.price=slider.amount if bid_mode else int(row.get("price",0))
			"mission":
				if not bool(row.get("active",false)) and not mission_blocked_reason(row).is_empty():
					message=mission_blocked_reason(row);queue_redraw();return
				action="mission_abort" if bool(row.get("active",false)) else "mission_accept"
				payload.mission_id=str(row.get("id",row.get("mission_id","")))
			"travel":
				if not bool(row.get("available",true)): return
				action="travel_purchase";payload.destination_id=str(row.get("id",row.get("destination_id","")));payload.destination_planet=str(row.get("planet",row.get("zone","")))
			"boarding": action="travel_board";payload.ticket_id=str(row.get("id",row.get("ticket_id","")))
	if action.is_empty(): return
	if terminal.get("market_kind","")=="vendor" and action.begins_with("bazaar_"):action=action.replace("bazaar_","vendor_")
	set_pending(true)
	action_requested.emit(action,payload)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
		scroll_at(event.position,-1 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1);accept_event();return
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		if event.pressed: pointer_begin(event.position)
		else: pointer_end(event.position)
	elif event is InputEventMouseMotion: pointer_move(event.position)

func label_for(row: Dictionary) -> String:
	return str(row.get("name",row.get("label",row.get("destination_name",row.get("arrival",row.get("title",row.get("id","")))))))

func detail_for(row: Dictionary) -> String:
	var detail:=label_for(row)+"\n\n"
	if terminal.get("kind","")=="house" and terminal.get("pob",false):detail+="Placed items: %d / %d\n\n"%[int(terminal.get("item_count",0)),int(terminal.get("item_limit",0))]
	elif terminal.get("kind","")=="house":detail+="Items: %d / %d\nUpkeep: %d credits\nRate: %.1f credits/hour\n\n"%[int(terminal.get("item_count",0)),int(terminal.get("item_limit",0)),int(terminal.get("maintenance",0)),float(terminal.get("maintenance_rate",0))]
	if terminal.get("kind","")=="mission":
		detail+="Type: "+str(row.get("type","mission")).capitalize()+"\n"
		var distance:=preload("res://scripts/mission_distance.gd").text(row,player_position,player_planet)
		if not distance.is_empty():detail+=distance+"\n"
		if not str(row.get("target","")).is_empty(): detail+="Target: "+str(row.target)+"\n"
		if row.get("type","")=="bounty":
			detail+="PvE only\n"
			if row.get("active",false):detail+=preload("res://bounty/presentation.gd").progress_text(row.get("bounty",{}))+"\n"
		if row.get("type","")=="survey": detail+="Survey at least %d%% density, over 1024m from the terminal.\n"%int(row.get("difficulty",0))
		var target_position: Variant=row.get("position")
		if target_position is Array and target_position.size()==3:
			detail+="X %.0f · Z %.0f\n"%[float(target_position[0]),float(target_position[2])]
		for key in ["difficulty","reward","planet"]:
			if row.has(key): detail+=key.capitalize()+": "+str(row[key])+"\n"
		var standing:Dictionary=row.get("faction_points",{})
		for faction in ["imperial","rebel"]:
			var points:=int(standing.get(faction,0))
			if points!=0:detail+="%s standing: %s%d\n"%[faction.capitalize(),"+" if points>0 else "",points]
		if not mission_blocked_reason(row).is_empty(): detail+="\n"+mission_blocked_reason(row)+"\n"
		detail+="\n"+str(row.get("description",""))
	elif terminal.get("kind","")=="trainer":
		detail+="%d credits\n%d skill points\n"%[int(row.get("credit_cost",0)),int(row.get("skill_point_cost",0))]
		if not str(row.get("xp_type","")).is_empty():
			detail+="%s XP\n%d / %d\n"%[str(row.get("xp_name",row.get("xp_type",""))),int(row.get("xp_available",0)),int(row.get("xp_cost",0))]
		var reason:=trainer_blocked_reason(row)
		if not reason.is_empty(): detail+="\n"+reason+"\n"
		var prerequisites: Array=row.get("prerequisites",[])
		if not prerequisites.is_empty():
			var labels:=PackedStringArray()
			for requirement in prerequisites: labels.append(trainer_skill_name(str(requirement)))
			detail+="\nRequires: "+", ".join(labels)+"\n"
		detail+="\n"+str(row.get("description",""))
	else:
		detail+=str(row.get("description",""))
		for key in ["price","reward","planet","location","type"]:
			if row.has(key): detail+="\n"+key.capitalize()+": "+str(row[key])
	return detail

func _draw() -> void:
	draw_style_box(preload("res://scripts/datapad_theme.gd").frame(14,"wide"),Rect2(Vector2.ZERO,size))
	var kind:=str(terminal.get("kind","service"))
	draw_string(FONT,Vector2(30,50),str(terminal.get("name",kind.to_upper())),HORIZONTAL_ALIGNMENT_LEFT,760,27,Color("d2f6ff"))
	draw_string(FONT,Vector2(818,40),"×",HORIZONTAL_ALIGNMENT_LEFT,30,25,Color("d2f6ff"))
	if kind=="bazaar" and not bid_mode:
		for index in range(4):
			var rect:=Rect2(SCOPE_RECT.position+Vector2(index*SCOPE_RECT.size.x/4,0),Vector2(SCOPE_RECT.size.x/4-4,SCOPE_RECT.size.y))
			draw_style_box(Holo.button("hover" if search_scope==SEARCH_SCOPES[index] else "normal"),rect)
			draw_string(FONT,rect.position+Vector2(4,26),SEARCH_SCOPES[index].capitalize(),HORIZONTAL_ALIGNMENT_CENTER,rect.size.x-8,18,Color("d2f6ff"))
		draw_string(FONT,Vector2(590,82),"BANK  %d cr"%int(wallet.get("bank",0)),HORIZONTAL_ALIGNMENT_LEFT,240,17,Color("9ac7da"))
	else:draw_string(FONT,Vector2(22,82),"CARRIED  %d cr       BANK  %d cr"%[int(wallet.get("cash",0)),int(wallet.get("bank",0))],HORIZONTAL_ALIGNMENT_LEFT,800,19,Color("9ac7da"))
	if kind=="underworld":
		draw_multiline_string(FONT,Vector2(40,408),"Front money: %d cr · Underworld reputation: %d\nReward: %d cr + %d reputation\nTime limit: %d minutes · Shuttle travel restricted"%[int(terminal.get("front_money",0)),int(terminal.get("reputation",0)),int(terminal.get("reward_credits",0)),int(terminal.get("reward_faction",0)),int(terminal.get("duration_seconds",1800))/60],HORIZONTAL_ALIGNMENT_LEFT,770,20,3,Color("9ac7da"))
	elif kind=="bounty_informant":
		draw_multiline_string(FONT,Vector2(40,408),"PvE bounty investigation · Confirm to contact this informant.",HORIZONTAL_ALIGNMENT_LEFT,770,20,3,Color("9ac7da"))
	elif kind=="delivery":
		var hint:=("Confirm to receive the mission recipe and components." if terminal.get("mission_kind","")=="crafting" else "Confirm to receive the mission parcel in Data.") if terminal.get("confirm_action","")=="delivery_pickup" else "Grip and pull the parcel from Data.\nPresent it to the recipient and press trigger.\nRelease grip to return it to the datapad."
		draw_multiline_string(FONT,Vector2(40,408),hint,HORIZONTAL_ALIGNMENT_LEFT,770,20,3,Color("9ac7da"))
	elif kind in ["bank","payment","house_deposit"] or bid_mode:
		if bid_mode:
			draw_string(FONT,Vector2(170,228),"Bid: "+label_for(rows[selected]),HORIZONTAL_ALIGNMENT_LEFT,520,24,Color("d2f6ff"))
		elif kind=="bank":
			for index in range(2):
				var active:=(index==0)==(direction=="deposit")
				draw_style_box(Holo.button("pressed" if active else "normal"),Rect2(170+index*260,192,250,60))
				draw_string(FONT,Vector2(180+index*260,229),"Deposit to bank" if index==0 else "Withdraw to wallet",HORIZONTAL_ALIGNMENT_LEFT,240,21,Color("d2f6ff"))
		elif kind=="house_deposit":draw_string(FONT,Vector2(170,228),"Deposit house upkeep · %d credits in reserve"%int(terminal.get("maintenance",0)),HORIZONTAL_ALIGNMENT_LEFT,630,24,Color("d2f6ff"))
		else: draw_string(FONT,Vector2(170,178 if wallet.get("faction_delegation",false) else 228),"Pay "+str(terminal.get("recipient_name",target_id)),HORIZONTAL_ALIGNMENT_LEFT,520,24,Color("d2f6ff"))
		if kind=="payment" and wallet.get("faction_delegation",false):
			draw_string(FONT,Vector2(170,122),"Imperial %d FP · Rebel %d FP · delegation cost ×%.2f"%[int(wallet.get("faction_points",{}).get("imperial",0)),int(wallet.get("faction_points",{}).get("rebel",0)),float(wallet.get("delegation_ratio",1.0))],HORIZONTAL_ALIGNMENT_LEFT,650,17,Color("9ac7da"))
		else:draw_string(FONT,Vector2(170,414),"Grab and drag to set an amount; confirm to submit",HORIZONTAL_ALIGNMENT_LEFT,550,19,Color("9ac7da"))
	else:
		var item_region:=BAZAAR_ROWS_RECT if kind=="bazaar" else TRAVEL_ROWS_RECT if kind=="travel" else ROWS_RECT
		if kind=="ship_crew":
			draw_multiline_string(FONT,Vector2(590,155),"Crew %d / %d\n\nShake the pilot’s\nfree main hand to join.\n\nTap a guest to remove.\n\nPress Launch when\neveryone is ready.\n\nWalking away cancels."%[rows.size(),int(terminal.get("capacity",0))],HORIZONTAL_ALIGNMENT_LEFT,242,19,16,Color("d2f6ff"))
		if kind=="bazaar":
			var breadcrumb:="Bazaar"
			for entry: Dictionary in category_path:
				if int(entry.id)!=0: breadcrumb+=" / "+str(entry.name)
			breadcrumb+=" / "+category_name
			draw_string(FONT,Vector2(22,115),breadcrumb,HORIZONTAL_ALIGNMENT_LEFT,810,16,Color("9ac7da"))
			for index in range(category_offset,mini(category_rows.size(),category_offset+8)):
				var category: Dictionary=category_rows[index]
				var y:=128+(index-category_offset)*ROW_HEIGHT
				draw_style_box(Holo.cell(category_selected==index),Rect2(20,y,218,ROW_HEIGHT-2))
				draw_multiline_string(FONT,Vector2(28,y+18),str(category.get("label",category.get("name",""))),HORIZONTAL_ALIGNMENT_LEFT,195,16,2,Color("d2f6ff"))
			if category_rows.is_empty(): draw_multiline_string(FONT,Vector2(28,157),"No subcategories" if not categories.is_empty() else "Loading original categories…",HORIZONTAL_ALIGNMENT_LEFT,190,18,3,Color("9ac7da"))
		for index in range(int(offset),mini(rows.size(),int(offset)+8)):
			var y:=128+(index-int(offset))*ROW_HEIGHT
			draw_style_box(Holo.cell(selected==index),Rect2(item_region.position.x,y,item_region.size.x,ROW_HEIGHT-2))
			var row_width:=item_region.size.x-16
			if kind=="trainer":
				row_width-=100
				var state:="Learned" if bool(rows[index].get("learned",false)) else ("Train" if bool(rows[index].get("eligible",false)) else "Locked")
				draw_string(FONT,Vector2(item_region.end.x-98,y+27),state,HORIZONTAL_ALIGNMENT_RIGHT,88,17,Color("8bddd2") if state=="Train" else Color("85a9b2"))
			draw_string(FONT,Vector2(item_region.position.x+8,y+29),label_for(rows[index])+(" · pilot" if kind=="ship_crew" and str(rows[index].get("id",""))==str(terminal.get("pilot_id","")) else ""),HORIZONTAL_ALIGNMENT_LEFT,row_width,21,Color("d2f6ff"))
		if rows.is_empty(): draw_multiline_string(FONT,Vector2(item_region.position.x+8,159),"Wait for boarding, then use your ticket." if kind=="ticket_collector" else "No entries returned by CoreCU." if kind!="crafting" else "No compatible owned crafting tools returned by CoreCU.",HORIZONTAL_ALIGNMENT_LEFT,item_region.size.x-16,21,3,Color("9ac7da"))
		if kind=="trainer" and selected<0:
			draw_multiline_string(FONT,Vector2(590,155),str(terminal.get("trainer_text","Select a skill to inspect its training requirements.")),HORIZONTAL_ALIGNMENT_LEFT,242,20,14,Color("d2f6ff"))
		if kind not in ["ship_crew","travel","pilot_trainer"] and selected>=0 and selected<rows.size():
			var row: Dictionary=rows[selected]
			var detail:=detail_for(row)
			draw_multiline_string(FONT,Vector2(590,155),detail,HORIZONTAL_ALIGNMENT_LEFT,242,20,14,Color("d2f6ff"))
		if rows.size()>8 and kind not in ["bazaar","travel"]: draw_string(FONT,Vector2(230,519),"%d–%d / %d · drag"%[int(offset)+1,mini(rows.size(),int(offset)+8),rows.size()],HORIZONTAL_ALIGNMENT_LEFT,330,18,Color("9ac7da"))
	if kind=="travel":
		travel_overview.draw(self,rows,selected,FONT)
	if kind in ["travel","ticket_collector"]:
		draw_style_box(Holo.button("disabled" if pending else "normal"),BOARDING_RECT)
		draw_string(FONT,BOARDING_RECT.position+Vector2(10,33),"Use ticket / board shuttle",HORIZONTAL_ALIGNMENT_CENTER,320,19,Color("d2f6ff"))
	if kind=="house_deposit":
		draw_style_box(Holo.button(),REFRESH_RECT);draw_string(FONT,REFRESH_RECT.position+Vector2(10,33),"Back",HORIZONTAL_ALIGNMENT_CENTER,170,19,Color("d2f6ff"))
	if kind in ["bazaar","mission","travel","trainer","ship_crew","starship","ship_outfit"]:
		draw_style_box(Holo.button("disabled" if pending else "normal"),REFRESH_RECT)
		draw_string(FONT,REFRESH_RECT.position+Vector2(10,33),"Components" if kind=="starship" else "Back to ships" if kind=="ship_outfit" else "Cancel launch" if kind=="ship_crew" else ("Back to listings" if bid_mode else ("Back" if kind=="bazaar" else ("Refresh offers" if kind=="mission" else "Refresh"))),HORIZONTAL_ALIGNMENT_CENTER,170,19,Color("d2f6ff"))
	if kind=="bazaar" and not bid_mode:
		for item in [{"rect":BAZAAR_REFRESH,"label":"Refresh"},{"rect":PAGE_PREVIOUS,"label":"‹"},{"rect":PAGE_NEXT,"label":"›"}]:
			draw_style_box(Holo.button(),item.rect)
			draw_string(FONT,item.rect.position+Vector2(5,33),item.label,HORIZONTAL_ALIGNMENT_CENTER,item.rect.size.x-10,20,Color("d2f6ff"))
		draw_string(FONT,Vector2(590,115),"Page %d · %d listings"%[page+1,rows.size()],HORIZONTAL_ALIGNMENT_LEFT,240,14,Color("9ac7da"))
	var button: String={"bazaar":"Purchase","mission":"Accept mission","travel":"Buy ticket","boarding":"Board shuttle","bank":"Transfer","payment":"Send credits","crafting":"Use station","trainer":"Train skill","starship":"Launch ship"}.get(kind,"Confirm")
	if kind=="house" and terminal.get("pob",false):button="Recover item"
	if kind=="ship_control":button="Activate"
	if kind=="pilot_trainer":button="Reply"
	if kind in ["chassis_dealer","ship_outfit"]:button="Confirm selection"
	if kind=="starship":button="Prepare launch"
	if kind=="ship_crew":button="Launch" if terminal.get("is_pilot",false) else "Waiting for pilot"
	if kind=="underworld":button="Accept smuggling job"
	if kind=="bounty_informant":button="Obtain bio-signature"
	if kind=="bounty_droid":button="Launch search"
	if kind=="payment" and wallet.get("faction_delegation",false):button="Send currencies"
	if kind=="delivery":button=("Receive recipe" if terminal.get("mission_kind","")=="crafting" else "Receive parcel") if terminal.get("confirm_action","")=="delivery_pickup" else "Present parcel by hand"
	var confirmation_disabled:bool=(kind=="underworld" and not terminal.get("eligible",false)) or (kind=="delivery" and terminal.get("confirm_action","")!="delivery_pickup") or pending or (kind=="trainer" and (selected<0 or selected>=rows.size()))
	if kind=="ship_crew" and not terminal.get("is_pilot",false):confirmation_disabled=true
	if kind=="bounty_informant" and not terminal.get("eligible",false):confirmation_disabled=true;button="Unavailable"
	if kind=="bounty_droid" and (selected<0 or selected>=rows.size() or not rows[selected].get("enabled",false)):confirmation_disabled=true;button="Unavailable"
	if selected>=0 and selected<rows.size():
		if kind=="trainer" and not trainer_blocked_reason(rows[selected]).is_empty():
			confirmation_disabled=true;button="Already learned" if bool(rows[selected].get("learned",false)) else "Unavailable"
		if kind=="mission" and not bool(rows[selected].get("active",false)) and not mission_blocked_reason(rows[selected]).is_empty():
			confirmation_disabled=true;button="Not available"
		if kind=="mission" and bool(rows[selected].get("active",false)): button="Abandon mission"
		if kind=="bazaar":
			if bool(rows[selected].get("retrieve_eligible",false)): button="Retrieve item"
			elif bool(rows[selected].get("auction",false)): button="Place bid"
	draw_style_box(Holo.button("disabled" if confirmation_disabled else "hover"),CONFIRM_RECT)
	draw_string(FONT,CONFIRM_RECT.position+Vector2(10,33),"Waiting for CoreCU…" if pending else button,HORIZONTAL_ALIGNMENT_CENTER,230,20,Color("d2f6ff"))
	draw_string(FONT,Vector2(30,590),message,HORIZONTAL_ALIGNMENT_LEFT,814,18,Color("9ac7da"))
