extends Node3D
## Core3 services orchestration. UI is local; all economic mutations are native.
const HandInput = preload("res://scripts/tracked_hand_input.gd")
const MAX_VISIBLE_PEERS := 8
var app: Node
var ui: Node3D
var bounty:Node3D
var gcw:Node3D
var scenery: Node3D
var state: Dictionary = {}
var busy := false
var presence_busy := false
var allowed := false
var generation := 0
var epoch := -1
var poll_clock := 0.0
var presence_clock := 0.0
var presence_age := 100.0
var state_age := 100.0
var presence_sequence := 0
var presence_token := ""
var party_bump=preload("res://scripts/party_bump.gd").new()
var party_notice:Label3D
var party_notice_seconds:=0.0
var peers: Array = []
var previous_position := Vector3.ZERO
var have_previous := false
var last_error := ""
var peer_markers: Dictionary = {}
var queued_action: Dictionary = {}
var presented_skills: Array = []
var have_presented_skills := false

func setup(host: Node) -> void:
	app = host
	process_priority = 119
	if app.xr_requested and is_instance_valid(app.xr_origin):
		ui = preload("res://scripts/xr_services.gd").new()
		add_child(ui)
		ui.configure(app.xr_origin, app.player, app.vr_settings.offhand)
		ui.terminal_provider = terminal_records
		ui.remote_hands_provider = remote_hands
		ui.inventory_focus_provider=func()->bool:return is_instance_valid(app.inventory) and app.inventory.has_method("blocks_services") and app.inventory.blocks_services()
		ui.action_requested.connect(request)
		ui.opened.connect(interface_opened)
		ui.closed.connect(func():
			if is_instance_valid(app.get("space")):app.space.lobby_closed())
	scenery = preload("res://scripts/service_world.gd").new()
	add_child(scenery)
	gcw=preload("res://gcw/controller.gd").new();add_child(gcw);gcw.setup(self)
	bounty=preload("res://bounty/controller.gd").new();add_child(bounty);bounty.setup(self)
	reset()

func reset() -> void:
	generation += 1
	if is_instance_valid(gcw):gcw.reset()
	if is_instance_valid(bounty):bounty.reset()
	busy = false; presence_busy = false; state = {}; peers = []
	presence_token = ""; presence_sequence = 0; presence_age = 100.0;party_bump.reset()
	party_notice_seconds=0
	if is_instance_valid(party_notice):party_notice.hide()
	state_age = 100.0
	if is_instance_valid(app) and is_instance_valid(app.get("datapad")) and is_instance_valid(app.datapad.get("ui")) and app.datapad.ui.has_method("set_service_points"):
		app.datapad.ui.set_service_points([])
	poll_clock = 0; presence_clock = 0; have_previous = false
	queued_action = {}
	presented_skills = []; have_presented_skills = false
	epoch = app.datapad_epoch if is_instance_valid(app) else -1
	if is_instance_valid(ui): ui.set_allowed(false); ui.set_pending(false)
	if is_instance_valid(scenery):
		scenery.reset()
		var origin: Array = app.loader.report.get("origin", [0,0,0])
		scenery.configure(Vector3(float(origin[0]),float(origin[1]),float(origin[2])),preload("res://scripts/planet_catalog.gd").context_path(app,"services","res://../runtime/assets/services/catalog.json"))
	for marker: Node3D in peer_markers.values(): marker.queue_free()
	peer_markers.clear()

func set_allowed(value: bool) -> void:
	allowed = value and not app.datapad_character_id.is_empty()
	if is_instance_valid(ui):
		ui.avatar = app.tracked_avatar
		ui.set_allowed(allowed)

func blocks_combat() -> bool:
	return is_instance_valid(ui) and ui.blocks_combat()

func inventory_accessible() -> bool:
	return is_instance_valid(ui) and ui.terminal.get("kind","") in ["bazaar","vendor"] and not ui.wallet_held

func blocks_inventory() -> bool:
	return blocks_combat() and not inventory_accessible()

func interface_opened() -> void:
	if is_instance_valid(app.datapad): app.datapad.set_open(false)
	if is_instance_valid(app.inventory): app.inventory.set_open(false)
	if is_instance_valid(app.combat_rig): app.combat_rig.set_allowed(false)

func source(point: Vector3) -> Array:
	var value: Vector3 = app.source_position_at(point)
	return [value.x, value.y, value.z]

func world(point: Array) -> Vector3:
	var origin: Array = app.stage.get_meta("manifest", {}).get("origin", [0,0,0]) if is_instance_valid(app.stage) else [0,0,0]
	var converted := Vector3(float(point[0])-float(origin[0]), float(point[1])-float(origin[1]), -(float(point[2])-float(origin[2])))
	return app.stage.to_global(converted) if is_instance_valid(app.stage) else converted

func identity_payload() -> Dictionary:
	var payload: Dictionary = {"account":app.datapad_account,"character_id":app.datapad_character_id,
		"zone":preload("res://scripts/planet_catalog.gd").current(app),"position":source(app.player.global_position),"building_id":"0","cell_index":0}
	if is_instance_valid(app.get("space")) and app.space.aboard():payload.zone=str(app.space.ship.get("zone","space_tatooine"))
	if is_instance_valid(app.stage) and app.stage.get("current_cell") is Dictionary:
		var cell: Dictionary = app.stage.current_cell
		var key := str(cell.get("cell_id", ""))
		payload.building_id = str(cell.get("building_object_id", "0"))
		payload.cell_index = int(key.get_slice(":",1)) if key.contains(":") else 0
		if payload.cell_index == 0: payload.building_id = "0"
	var native_id:=preload("res://scripts/native_session_identity.gd").id(app)
	if not native_id.is_empty():payload.session_id=native_id
	return payload

func request(action: String, detail: Dictionary = {}) -> Dictionary:
	if is_instance_valid(app.get("space")) and app.space.aboard():return await app.space.terminal_request(action,detail)
	if action=="skill_forget" and is_instance_valid(app.get("space")) and app.space.aboard():return {"ok":false,"error":"Return to ground before forgetting skills."}
	if action in ["jtl_launch","jtl_launch_confirm","jtl_crew_remove"] and is_instance_valid(app.get("space")):
		var launched:Dictionary=await app.space.request({"jtl_launch":"crew_prepare","jtl_launch_confirm":"launch","jtl_crew_remove":"crew_remove"}[action],detail)
		if is_instance_valid(ui):
			ui.set_pending(false)
			if launched.get("ok",false):
				if action=="jtl_launch_confirm":ui.close_interface()
			else:ui.panel.message=str(launched.get("error","Ship launch not confirmed"));ui.panel.queue_redraw()
		return launched
	if busy:
		if action == "skill_forget": return {"ok":false,"error":"Wait for the current service request to finish."}
		if action != "status" and queued_action.is_empty(): queued_action = {"action":action,"detail":detail.duplicate(true)}
		return {}
	var skill_browser: bool = not (is_instance_valid(app.get("space")) and app.space.aboard()) and is_instance_valid(app.get("datapad")) and app.datapad.get("is_open") == true and str(app.datapad.ui.category) == "skills"
	if (not allowed and action != "skill_forget" and not (action == "status" and skill_browser)) or app.datapad_character_id.is_empty():
		if is_instance_valid(ui): ui.set_pending(false)
		return {}
	if action=="travel_tickets":
		return open_terminal_tickets()
	if action in ["travel_purchase","travel_board"]:
		var ready:=travel_assets_ready(action,detail)
		if not ready.get("ok",false):
			last_error=str(ready.error)
			if is_instance_valid(ui):ui.set_pending(false);ui.panel.message=last_error;ui.panel.queue_redraw()
			return ready
	busy = true
	var version := generation
	var character_epoch: int = app.datapad_epoch
	var payload := identity_payload()
	payload.merge(detail, true)
	if str(payload.get("request_id","")).is_empty():payload.request_id = "service-%d-%d" % [int(Time.get_unix_time_from_system()*1000000),Time.get_ticks_usec()]
	if is_instance_valid(ui) and action != "status": ui.set_pending(true)
	var response: Dictionary = await app.api(HTTPClient.METHOD_POST, "/services/"+action, payload)
	if version != generation or character_epoch != app.datapad_epoch: return {}
	busy = false
	if not accept_response(response, action != "status"):
		if is_instance_valid(gcw) and action.begins_with("recruiter_"):gcw.outcome(last_error)
		if is_instance_valid(bounty) and action.begins_with("bounty_"):bounty.outcome(last_error)
		if is_instance_valid(ui):
			ui.set_pending(false); ui.panel.message = last_error; ui.panel.queue_redraw()
		poll_clock = 5.0
		queued_action = {} # A failed read must not launch a pending economic mutation.
		return response
	if action.begins_with("bounty_") and bool(response.get("mutation",{}).get("success",false)):
		if is_instance_valid(ui):ui.close_interface()
		if is_instance_valid(bounty):bounty.outcome(preload("res://bounty/presentation.gd").progress_text(state.get("bounty",{})))
	if action=="house_permission_arm" and bool(response.get("mutation",{}).get("success",false)):
		# Release the terminal interaction gate so the owner can shake hands.
		if is_instance_valid(ui):ui.close_interface()
	if action in ["delivery_pickup","delivery_complete"] and bool(response.get("mutation",{}).get("success",false)):
		if is_instance_valid(ui):ui.close_interface()
		if is_instance_valid(app.datapad):
			var notice:="Mission parcel added to Data. Grip and pull it out; present it to the recipient and press trigger." if action=="delivery_pickup" else "Parcel handed over. Core3 is completing the mission."
			if action=="delivery_pickup" and state.get("terminal",{}).get("mission_kind","")=="crafting":notice="Mission recipe and components received. Craft the commissioned item; it will appear in Data when ready."
			app.datapad.ui.set_status(notice)
	if action in ["trainer_train", "skill_forget"] and bool(response.get("mutation",{}).get("success",false)):
		var persistent_reserved: bool=bool(app.get("live_combat_reserved")) or (is_instance_valid(app.live_combat) and app.live_combat.live)
		if not persistent_reserved and app.has_method("refresh_weapon_statistics"):
			await app.refresh_weapon_statistics()
			if version != generation or character_epoch != app.datapad_epoch: return response
	if action == "crafting_station" and bool(response.get("mutation",{}).get("success",false)):
		await use_crafting_tool(str(detail.get("tool_id",state.get("terminal",{}).get("tool_id",""))))
	if action == "travel_board" and bool(response.get("mutation",{}).get("success",false)):
		if is_instance_valid(ui): ui.close_interface()
		var transport: Dictionary = response.get("transport", state.get("transport",{}))
		if not transport.is_empty() and preload("res://scripts/native_session_identity.gd").id(app).is_empty():
			await app.perform_service_transport(transport)
	if not queued_action.is_empty():
		var next := queued_action
		queued_action = {}
		call_deferred("request", str(next.action), next.detail)
	return response

func travel_assets_ready(action:String,detail:Dictionary)->Dictionary:
	var planet:=str(detail.get("destination_planet",""))
	if action=="travel_board":
		var choices:Array=state.get("tickets",[]).duplicate()
		for shuttle:Dictionary in state.get("shuttles",[]):choices.append_array(shuttle.get("tickets",[]))
		var found:=false
		for ticket:Dictionary in choices:
			if str(ticket.get("id",""))==str(detail.get("ticket_id","")):
				planet=str(ticket.get("destination_planet",ticket.get("planet",ticket.get("zone",""))));found=true;break
		if not found:return {"ok":false,"error":"Refresh the available shuttle tickets before boarding."}
	if planet.is_empty():planet=preload("res://scripts/planet_catalog.gd").current(app)
	var resolver:=preload("res://scripts/planet_catalog.gd").new()
	resolver.configure(str(app.planet_catalog.path) if app.get("planet_catalog")!=null else preload("res://scripts/planet_catalog.gd").DEFAULT_PATH)
	return resolver.readiness(planet)

func accept_response(response: Dictionary, resolve_pending := true) -> bool:
	if not response.get("ok",false) or response.get("source_kind","") != "core3_services" or str(response.get("character_id","")) != str(app.datapad_character_id):
		last_error = str(response.get("error", "Core3 did not confirm this interaction. Refresh before retrying."))
		return false
	var incoming: Variant = response.get("state")
	if not incoming is Dictionary or str(incoming.get("character_id","")) != str(app.datapad_character_id):
		last_error = "Mismatched native services state."
		return false
	var live: Variant = response.get("live_response")
	var normal: Variant=app.get("gameplay_session")
	var session: Variant=app.live_combat if is_instance_valid(app.live_combat) and app.live_combat.live else normal if is_instance_valid(normal) and normal.live else null
	if str(incoming.get("zone",preload("res://scripts/planet_catalog.gd").current(app)))!=preload("res://scripts/planet_catalog.gd").current(app):
		# Only an owned, newer native transport can replace the current zone.
		if live is Dictionary and is_instance_valid(session) and str(live.get("session_id",""))==str(session.session_id) and int(live.get("sequence",-1))>int(session.sequence) and live.get("snapshot") is Dictionary and live.snapshot.get("transport") is Dictionary and not live.snapshot.transport.is_empty():
			return session.accept_native_response(live) if session==normal else session.accept_response(live)
		last_error="Discarded services from a previous planet.";return false
	var accepted_epoch:=generation
	var progress_current: bool=not (is_instance_valid(normal) and normal.live and session==normal)
	if is_instance_valid(session) and response.has("live_response"):
		progress_current=live is Dictionary and str(live.get("session_id",""))==str(session.session_id) and int(live.get("sequence",-1))>=int(session.sequence)
	# A late mutation receipt may resolve its UI, but cannot resurrect cancelled items.
	if progress_current:
		state = incoming.duplicate(true)
		state_age = 0.0
	var parcels:Variant=app.get("mission_parcels")
	if progress_current and is_instance_valid(parcels):parcels.observe(response)
	var slicing_controller:Variant=app.get("slicing")
	if progress_current and is_instance_valid(slicing_controller):slicing_controller.observe(response)
	var housing_controller:Variant=app.get("housing")
	if progress_current and is_instance_valid(housing_controller):housing_controller.observe(response)
	var vendors:Variant=app.get("vendor_placement")
	if progress_current and is_instance_valid(vendors):vendors.observe(response)
	if is_instance_valid(app.get("datapad")) and is_instance_valid(app.datapad.get("ui")) and app.datapad.ui.has_method("set_service_points"):
		app.datapad.ui.set_service_points(state.get("terminals",[]))
	last_error = ""
	if response.get("presence") is Dictionary:
		presence_token = str(response.presence.get("token",presence_token))
		presence_sequence = maxi(presence_sequence,int(response.presence.get("sequence_floor",-1)))
	var display := state.duplicate(true)
	display.mutation = response.get("mutation",{})
	if is_instance_valid(ui): ui.apply_response(display, resolve_pending)
	if progress_current and is_instance_valid(gcw):gcw.observe(response)
	if progress_current and is_instance_valid(bounty):bounty.observe(response)
	if live is Dictionary and is_instance_valid(normal) and normal.live and session==normal and str(live.get("session_id",""))==str(normal.session_id) and int(live.get("sequence",-1))>int(normal.sequence):
		if not normal.accept_native_response(live):
			last_error=normal.last_error;return false
	if generation!=accepted_epoch:return true
	# Economic receipts remain visible, but older live envelopes cannot roll back XP/skills.
	if progress_current:
		apply_skill_snapshot(state)
		apply_experience_snapshot(state)
	if is_instance_valid(scenery): scenery.apply_snapshot(state,app.player.global_position)
	var inventory: Variant = response.get("inventory", state.get("inventory"))
	if progress_current and inventory is Dictionary and inventory.get("source_kind","") == "core3_inventory" and str(inventory.get("character_id","")) == str(app.datapad_character_id):
		app.inventory_snapshot = inventory.duplicate(true)
		app.reconcile_inventory_presentations(); app.update_inventory_presentation()
		if is_instance_valid(slicing_controller):slicing_controller.equipment_updated(response)
	if live is Dictionary and is_instance_valid(app.live_combat) and app.live_combat.live and str(live.get("session_id","")) == app.live_combat.session_id and int(live.get("sequence",-1)) > app.live_combat.sequence:
		if not app.live_combat.accept_response(live):
			last_error = app.live_combat.last_error
			app.live_combat.fail(last_error)
			return false
	poll_clock = services_poll_interval(state)
	return true

func apply_skill_snapshot(snapshot: Dictionary) -> void:
	# A complete same-character native snapshot is presentation data, never a grant.
	if str(snapshot.get("character_id",""))!=str(app.datapad_character_id) or not bool(snapshot.get("skills_complete",false)): return
	var skills: Variant=snapshot.get("skills")
	if not skills is Array: return
	for skill in skills:
		if not skill is String or skill.is_empty(): return
	if not is_instance_valid(app.datapad) or not is_instance_valid(app.datapad.get("ui")): return
	if not have_presented_skills or skills!=presented_skills:app.datapad.ui.set_skills(skills,true)
	if app.datapad.ui.has_method("set_forget_skills"):
		app.datapad.ui.set_forget_skills(snapshot.get("forget_skills", []), int(snapshot.get("skill_points", -1)))
	presented_skills=skills.duplicate();have_presented_skills=true

func apply_experience_snapshot(snapshot: Dictionary) -> void:
	if str(snapshot.get("character_id",""))!=str(app.datapad_character_id) or not bool(snapshot.get("experience_complete",false)): return
	var experience: Variant=snapshot.get("experience")
	if not experience is Dictionary: return
	for key in experience:
		if not key is String or key.is_empty(): return
		var amount: Variant=experience[key]
		if (not amount is int and not amount is float) or not is_finite(float(amount)) or float(amount)<0 or float(amount)!=float(int(amount)): return
	if not is_instance_valid(app.datapad) or not is_instance_valid(app.datapad.get("ui")) or not app.datapad.ui.has_method("set_experience"): return
	# The profession UI deduplicates values; live snapshots also write here.
	app.datapad.ui.set_experience(experience,true)

func terminal_records(require_fresh: bool=true) -> Array:
	if is_instance_valid(app.get("space")) and app.space.aboard():return app.space.terminal_records()
	var parcels:Variant=app.get("mission_parcels")
	if is_instance_valid(parcels) and parcels.blocks_interactions():return []
	var records: Array = []
	if require_fresh and state_age > 8.0: return records
	var identity := identity_payload()
	for record: Dictionary in state.get("terminals",[])+preload("res://scripts/service_world.gd").collector_records(state)+state.get("delivery_contacts",[])+(bounty.contacts() if is_instance_valid(bounty) else []):
		if not record.get("position") is Array or record.position.size()!=3: continue
		if str(record.get("building_id","0")) != str(identity.building_id) or int(record.get("cell_index",0)) != int(identity.cell_index): continue
		var value := record.duplicate(true)
		value.position = world(record.position)
		if is_instance_valid(scenery) and scenery.has_method("screen_offsets") and record.get("kind") not in ["trainer","delivery","recruiter","underworld","bounty_informant","pilot_trainer","chassis_dealer"]:
			var basis: Basis=scenery.terminal_basis(record)
			if is_instance_valid(app.stage):basis=app.stage.global_basis*basis
			var object_pose:=Transform3D(basis,value.position)
			value.pick_geometry=scenery.terminal_pick_geometry(record)
			value.pick_pose=object_pose
			value.ui_displays=[]
			for screen:Dictionary in scenery.screen_surfaces(record):
				value.ui_displays.append({"pose":object_pose*screen.pose,"size":screen.size,"area":screen.area})
			value.ui_anchors=[]
			for offset: Transform3D in scenery.screen_offsets(record):value.ui_anchors.append(object_pose*offset)
		records.append(value)
	return records

func remote_hands() -> Array:
	return peers if presence_age < 0.8 else []

func update_presence() -> void:
	if presence_busy or presence_token.is_empty() or not is_instance_valid(ui): return
	presence_busy = true
	var version := generation
	var character_epoch: int = app.datapad_epoch
	var rig: XROrigin3D = app.xr_origin
	var hand: XRController3D = rig.get_node("RightHand" if app.vr_settings.offhand=="left" else "LeftHand")
	var tracker = XRServer.get_tracker("head")
	var head_pose: XRPose = tracker.get_pose("default") if tracker != null else null
	var tracked := allowed and head_pose != null and head_pose.has_tracking_data and HandInput.controller_tracked(hand)
	presence_sequence += 1
	var payload := identity_payload()
	var native_player: Dictionary = state.get("player",{})
	if str(payload.building_id)!=str(native_player.get("building_id","0")) or int(payload.cell_index)!=int(native_player.get("cell_index",0)):
		tracked=false; poll_clock=0; peers=[]; update_peer_markers()
	payload.merge({"token":presence_token,"sequence":presence_sequence,"wallet_held":ui.wallet_held and tracked,
		"main_hand_side":"right" if app.vr_settings.offhand=="left" else "left",
		"heading_radians":app.tracked_avatar.global_rotation.y if is_instance_valid(app.tracked_avatar) else app.player.global_rotation.y,
		"hand":{"position":source(hand.global_position),"tracked":tracked,"grip":tracked and hand.get_float("grip")>=0.65}})
	var hands:Dictionary={}
	for side in ["left","right"]:
		var controller:XRController3D=rig.get_node(side.capitalize()+"Hand")
		var hand_tracked:bool=allowed and head_pose!=null and head_pose.has_tracking_data and HandInput.controller_tracked(controller)
		if str(payload.building_id)!=str(native_player.get("building_id","0")) or int(payload.cell_index)!=int(native_player.get("cell_index",0)):hand_tracked=false
		hands[side]=party_bump.hand_sample(source(controller.global_position),hand_tracked,controller.get_float("grip"),controller.get_float("trigger"),party_hand_free(side,true))
	payload.hands=hands
	var response: Dictionary = await app.api(HTTPClient.METHOD_POST,"/services/presence",payload)
	if version != generation or character_epoch != app.datapad_epoch: return
	presence_busy = false
	if not response.get("ok",false) or response.get("source_kind","") != "authenticated_hand_presence" or str(response.get("character_id","")) != str(app.datapad_character_id):
		peers=[]; return
	peers = []
	for record: Dictionary in response.get("peers",[]):
		if not record.get("hand_position") is Array or record.hand_position.size()!=3: continue
		var peer := record.duplicate(true)
		peer.hand_position = world(record.hand_position)
		if record.get("position") is Array: peer.position = world(record.position)
		peer.authenticated = true
		peer.grip = 1.0 if bool(record.get("grip",false)) else 0.0
		peers.append(peer)
	peers.sort_custom(func(a,b): return a.hand_position.distance_squared_to(app.player.global_position)<b.hand_position.distance_squared_to(app.player.global_position))
	if peers.size()>MAX_VISIBLE_PEERS: peers.resize(MAX_VISIBLE_PEERS)
	presence_age = 0
	update_peer_markers()
	if is_instance_valid(app.get("space")):app.space.consume_crew_handshakes(response.get("peers",[]))
	consume_party_bumps(response.get("peers",[]))

func party_hand_free(side:String,crew_contact:=false)->bool:
	if not allowed or not is_instance_valid(ui) or ui.wallet_held or (not ui.terminal.is_empty() and not (crew_contact and ui.terminal.get("kind","")=="ship_crew")) or ui.pointer_pressed:return false
	var occupied:Array=[]
	var combat:Variant=app.get("combat_rig")
	var main_side:String="right" if app.vr_settings.offhand=="left" else "left"
	var bag:Variant=app.get("inventory")
	if is_instance_valid(bag):
		if bag.is_open or bag.action_pending or bag.hologram.active:return false
		if not bag.held_item.is_empty():occupied.append(bag.held_hand_side())
		if not bag.equipment_drag.is_empty():occupied.append(main_side)
		if bag.offhand_occupied:occupied.append(str(app.vr_settings.offhand))
		for item:Dictionary in bag.current_equipment:
			# Native hold_r remains equipped while the original weapon visual is holstered.
			if is_instance_valid(combat) and combat.weapons.any(func(entry):return str(entry.state.profile.get("item_id",""))==str(item.get("id","")) and (combat.selected<0 or str(combat.weapons[combat.selected].state.profile.get("item_id",""))!=str(item.get("id","")))):continue
			if "hold_r" in item.get("equipped_slots",[]):occupied.append(main_side)
			if "hold_l" in item.get("equipped_slots",[]):occupied.append(str(app.vr_settings.offhand))
	if is_instance_valid(combat):
		if combat.ability_ui.menu_open:return false
		if combat.selected>=0:occupied.append(main_side)
		if combat.support_latched or combat.offhand_occupied:occupied.append(str(app.vr_settings.offhand))
		if combat.vehicle_hand_busy(side) or combat.pet_trigger_reserved(side):occupied.append(side)
	var performer:Variant=app.get("entertainer")
	if is_instance_valid(performer):
		if performer.ui.menu_open or performer.is_performing():return false
		if not performer.item.is_empty() and not performer.item.get("placed",false):occupied.append(performer.dominant())
	for key in ["datapad","crafting"]:
		var node:Variant=app.get(key)
		if is_instance_valid(node) and node.get("is_open"):return false
	for key in ["mission_parcels","vendor_placement","vendor_commerce","housing"]:
		var node:Variant=app.get(key)
		if is_instance_valid(node) and node.has_method("blocks_interactions") and node.blocks_interactions():return false
	var slicer:Variant=app.get("slicing")
	if is_instance_valid(slicer) and not slicer.current_tool().is_empty():occupied.append(str(slicer.tool_hand().name).to_lower().trim_suffix("hand"))
	var fishing:Variant=app.get("fishing")
	if is_instance_valid(fishing) and fishing.busy_hand(side):occupied.append(side)
	return party_bump.free_hand(side,{"blocked":false,"occupied":occupied})

func consume_party_bumps(records:Array)->void:
	if is_instance_valid(app.get("space")) and not app.space.launch_stage().is_empty():return
	records=records.filter(func(peer):return str(peer.get("crew_launch_id","")).is_empty())
	var performer:Variant=app.get("entertainer")
	if not is_instance_valid(performer) or not is_instance_valid(performer.native):return
	var native:Node=performer.native
	if native.busy or not native.allowed() or not (party_hand_free("left") or party_hand_free("right")):return
	var detail:Dictionary=party_bump.take_ready(str(app.datapad_character_id),records)
	if detail.is_empty():return
	var version:=generation
	var response:Dictionary=await native.request("group_bump",detail)
	if version!=generation:return
	if response.get("ok",false) and response.get("source_kind","")=="core3_entertainer" and str(response.get("character_id",""))==str(app.datapad_character_id) and response.get("mutation",{}).get("success",false):
		poll_clock=0
		show_party_notice(str(response.get("mutation",{}).get("message","Party updated")))

func show_party_notice(message:String)->void:
	if not is_instance_valid(party_notice):
		party_notice=Label3D.new();add_child(party_notice);party_notice.font=preload("res://resources/fonts/Jupiteroid-Regular.ttf");party_notice.font_size=24;party_notice.pixel_size=.0008;party_notice.modulate=Color("b8ffff");party_notice.billboard=BaseMaterial3D.BILLBOARD_ENABLED
	party_notice.text=message;party_notice_seconds=3.5;party_notice.show()
	update_party_notice(0)

func update_party_notice(delta:float)->void:
	party_notice_seconds=maxf(0,party_notice_seconds-delta)
	if not is_instance_valid(party_notice):return
	party_notice.visible=party_notice_seconds>0 and allowed
	if party_notice.visible and is_instance_valid(app.xr_origin):
		var camera:Camera3D=app.xr_origin.get_node("XRCamera3D")
		party_notice.global_position=camera.global_position-camera.global_basis.z*.7-Vector3.UP*.18

func update_peer_markers() -> void:
	# Persistent multiplayer owns full avatars; handshake proof remains separate.
	if is_instance_valid(app.get("multiplayer_sync")):
		for marker:Node in peer_markers.values():marker.queue_free()
		peer_markers.clear()
		return
	var present: Dictionary = {}
	for peer: Dictionary in remote_hands():
		var id := str(peer.id)
		present[id] = true
		if not peer_markers.has(id):
			var marker := preload("res://scripts/service_peer.gd").new()
			add_child(marker); marker.configure(); peer_markers[id]=marker
		var value:=peer.duplicate(true)
		value.tracked=bool(peer.get("fresh",false))
		peer_markers[id].apply_peer(value)
	for id in peer_markers.keys():
		if not present.has(id): peer_markers[id].queue_free(); peer_markers.erase(id)

func use_crafting_tool(tool_id: String) -> void:
	if not is_instance_valid(app.crafting) or not is_instance_valid(app.inventory): return
	var item: Dictionary = app.inventory.held_item
	if item.get("tool_kind","") != "crafting" or (not tool_id.is_empty() and str(item.get("id","")) != tool_id):
		item = app.owned_inventory_item(tool_id)
		if item.get("tool_kind","") != "crafting":
			if is_instance_valid(ui): ui.panel.message="Draw a compatible crafting tool from your inventory, then use the station."; ui.panel.queue_redraw()
			return
		if is_instance_valid(ui): ui.close_interface()
		# Selection draws the owned source tool only after terminal controls release.
		await get_tree().process_frame
		if not is_instance_valid(app.inventory) or app.datapad_epoch!=epoch: return
		app.inventory.take_item(item)
		if app.inventory.held_item.is_empty(): return
	if is_instance_valid(ui): ui.close_interface()
	await app.crafting.activate(item)

func _process(delta: float) -> void:
	if not is_instance_valid(app): return
	if is_instance_valid(app.get("space")) and app.space.aboard():return
	if epoch != app.datapad_epoch: reset()
	update_party_notice(delta)
	presence_age += delta
	state_age += delta
	for marker: Node3D in peer_markers.values(): marker.advance(delta)
	if presence_age > 0.8 and not peer_markers.is_empty(): update_peer_markers()
	if is_instance_valid(scenery): scenery.advance(delta)
	if not allowed:
		have_previous=false
		if not (is_instance_valid(app.get("space")) and app.space.aboard()) and is_instance_valid(app.get("datapad")) and app.datapad.get("is_open") == true and str(app.datapad.ui.category) == "skills":
			poll_clock -= delta
			if poll_clock <= 0 and not busy:
				poll_clock = 3.0
				request("status")
		return
	if is_instance_valid(ui) and not ui.terminal.is_empty() and ui.terminal.get("kind","") not in ["payment","boarding","contraband","bounty_droid"]:
		# A background scheduler delay cannot close an otherwise static panel.
		# New discovery still requires fresh records; every mutation revalidates natively.
		if not terminal_records(false).any(func(record): return str(record.id)==str(ui.terminal.id)):
			ui.close_interface()
	poll_clock -= delta
	if poll_clock <= 0 and not busy and not (is_instance_valid(ui) and ui.pointer_pressed) and (not app.has_method("try_background_poll") or app.try_background_poll("services")):
		poll_clock=5.0
		var detail: Dictionary={}
		if is_instance_valid(ui) and not ui.terminal.is_empty() and ui.terminal.get("kind","") not in ["payment","boarding","ticket_collector","contraband","bounty_droid","bounty_informant"]: detail.terminal_id=str(ui.terminal.id)
		if is_instance_valid(ui) and ui.terminal.get("kind","") in ["bazaar","vendor"]: detail.merge(ui.panel.browse_payload(),true)
		if is_instance_valid(ui) and ui.terminal.get("kind","")=="delivery":
			detail={"npc_id":str(ui.terminal.id),"mission_id":str(ui.terminal.get("mission_id",""))}
			request("delivery_open",detail)
		else:request("status",detail)
	presence_clock -= delta
	if presence_clock <= 0 and not presence_busy:
		presence_clock=0.1
		update_presence()
	if is_instance_valid(ui) and is_instance_valid(scenery):
		var current: Vector3=app.player.global_position
		var boarding: Array=scenery.boarding_rows() if state_age<2.5 else []
		if ui.terminal.get("kind","")=="boarding" and not boarding.any(func(row): return str(row.id)==str(ui.terminal.id)):
			ui.close_interface()
		if have_previous:
			for shuttle: Dictionary in boarding:
				var value:=shuttle.duplicate(true)
				value.position=world(shuttle.position)
				if shuttle.get("door_position") is Array: value.door_position=world(shuttle.door_position)
				var tickets: Array=shuttle.get("tickets",state.get("tickets",[])).filter(func(ticket): return bool(ticket.get("usable",false)) and str(ticket.get("departure",""))==str(shuttle.get("departure","")))
				if ui.terminal.get("kind","")=="boarding" and str(ui.terminal.id)==str(shuttle.id): ui.sync_boarding_choices(tickets)
				ui.update_boarding(value,tickets,previous_position,current)
		previous_position=current; have_previous=true

func open_terminal_tickets() -> Dictionary:
	if not is_instance_valid(ui):return {"ok":false}
	ui.set_pending(false)
	var reason:="Wait for the shuttle to land and open its doors."
	if state_age>=2.5:
		reason="Refreshing shuttle status. Try again in a moment."
		poll_clock=0
	else:
		for shuttle:Dictionary in state.get("shuttles",[]):
			if not shuttle.get("position") is Array:continue
			if ui.terminal.get("kind","")=="ticket_collector" and str(ui.terminal.get("shuttle_id",""))!=str(shuttle.get("id","")):continue
			# Keep Core3's native boarding range; no local teleport or ticket consumption.
			if (world(shuttle.position)-app.player.global_position).slide(Vector3.UP).length()>25.0:
				reason="Use the shuttle boarding terminal beside the landing pad."
				continue
			if not shuttle.get("landed",false) or not shuttle.get("doors_open",false):continue
			var choices:Array=shuttle.get("tickets",state.get("tickets",[])).filter(func(ticket):return bool(ticket.get("usable",false)) and str(ticket.get("departure",""))==str(shuttle.get("departure","")))
			if choices.is_empty():reason="Buy a ticket for this departure first.";continue
			ui.offer_boarding(shuttle,choices,true)
			return {"ok":true}
	ui.panel.message=reason;ui.panel.queue_redraw()
	return {"ok":false,"error":reason}

func services_poll_interval(snapshot: Dictionary) -> float:
	if snapshot.get("bounty",{}).get("stage","") in ["probe_calling","searching","tracking"]:return 1.0
	# Distant planetary shuttle state does not justify another native scene login.
	if is_instance_valid(ui) and str(ui.terminal.get("kind","")) in ["travel","boarding","ticket_collector"]:return 1.0
	if is_instance_valid(app) and is_instance_valid(app.get("player")):
		for shuttle in snapshot.get("shuttles",[]):
			if not shuttle is Dictionary or not shuttle.get("position") is Array or shuttle.position.size()!=3:continue
			if world(shuttle.position).distance_to(app.player.global_position)<=40.0:return 1.0
	return 5.0
