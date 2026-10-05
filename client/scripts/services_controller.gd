extends Node3D
## Core3 services orchestration. UI is local; all economic mutations are native.
const HandInput = preload("res://scripts/tracked_hand_input.gd")
const MAX_VISIBLE_PEERS := 8
var app: Node
var ui: Node3D
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
		ui.action_requested.connect(request)
		ui.opened.connect(interface_opened)
	scenery = preload("res://scripts/service_world.gd").new()
	add_child(scenery)
	reset()

func reset() -> void:
	generation += 1
	busy = false; presence_busy = false; state = {}; peers = []
	presence_token = ""; presence_sequence = 0; presence_age = 100.0
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
		scenery.configure(Vector3(float(origin[0]),float(origin[1]),float(origin[2])))
	for marker: Node3D in peer_markers.values(): marker.queue_free()
	peer_markers.clear()

func set_allowed(value: bool) -> void:
	allowed = value and not app.datapad_character_id.is_empty()
	if is_instance_valid(ui):
		ui.avatar = app.tracked_avatar
		ui.set_allowed(allowed)

func blocks_combat() -> bool:
	return is_instance_valid(ui) and ui.blocks_combat()

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
		"position":source(app.player.global_position),"building_id":"0","cell_index":0}
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
	if busy:
		if action != "status" and queued_action.is_empty(): queued_action = {"action":action,"detail":detail.duplicate(true)}
		return {}
	if not allowed or app.datapad_character_id.is_empty():
		if is_instance_valid(ui): ui.set_pending(false)
		return {}
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
		if is_instance_valid(ui):
			ui.set_pending(false); ui.panel.message = last_error; ui.panel.queue_redraw()
		poll_clock = 5.0
		queued_action = {} # A failed read must not launch a pending economic mutation.
		return response
	if action in ["delivery_pickup","delivery_complete"] and bool(response.get("mutation",{}).get("success",false)):
		if is_instance_valid(ui):ui.close_interface()
		if is_instance_valid(app.datapad):
			var notice:="Mission parcel added to Data. Grip and pull it out; present it to the recipient and press trigger." if action=="delivery_pickup" else "Parcel handed over. Core3 is completing the mission."
			if action=="delivery_pickup" and state.get("terminal",{}).get("mission_kind","")=="crafting":notice="Mission recipe and components received. Craft the commissioned item; it will appear in Data when ready."
			app.datapad.ui.set_status(notice)
	if action == "trainer_train" and bool(response.get("mutation",{}).get("success",false)):
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
	var progress_current: bool=not (is_instance_valid(normal) and normal.live and session==normal)
	if is_instance_valid(session) and response.has("live_response"):
		progress_current=live is Dictionary and str(live.get("session_id",""))==str(session.session_id) and int(live.get("sequence",-1))>=int(session.sequence)
	# A late mutation receipt may resolve its UI, but cannot resurrect cancelled items.
	if progress_current:
		state = incoming.duplicate(true)
		state_age = 0.0
	var parcels:Variant=app.get("mission_parcels")
	if progress_current and is_instance_valid(parcels):parcels.observe(response)
	if is_instance_valid(app.get("datapad")) and is_instance_valid(app.datapad.get("ui")) and app.datapad.ui.has_method("set_service_points"):
		app.datapad.ui.set_service_points(state.get("terminals",[]))
	last_error = ""
	if response.get("presence") is Dictionary:
		presence_token = str(response.presence.get("token",presence_token))
		presence_sequence = maxi(presence_sequence,int(response.presence.get("sequence_floor",-1)))
	var display := state.duplicate(true)
	display.mutation = response.get("mutation",{})
	if is_instance_valid(ui): ui.apply_response(display, resolve_pending)
	if live is Dictionary and is_instance_valid(normal) and normal.live and session==normal and str(live.get("session_id",""))==str(normal.session_id) and int(live.get("sequence",-1))>int(normal.sequence):
		if not normal.accept_native_response(live):
			last_error=normal.last_error;return false
	# Economic receipts remain visible, but older live envelopes cannot roll back XP/skills.
	if progress_current:
		apply_skill_snapshot(state)
		apply_experience_snapshot(state)
	if is_instance_valid(scenery): scenery.apply_snapshot(state,app.player.global_position)
	var inventory: Variant = response.get("inventory", state.get("inventory"))
	if progress_current and inventory is Dictionary and inventory.get("source_kind","") == "core3_inventory" and str(inventory.get("character_id","")) == str(app.datapad_character_id):
		app.inventory_snapshot = inventory.duplicate(true)
		app.reconcile_inventory_presentations(); app.update_inventory_presentation()
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
	if have_presented_skills and skills==presented_skills: return
	app.datapad.ui.set_skills(skills,true)
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
	var parcels:Variant=app.get("mission_parcels")
	if is_instance_valid(parcels) and parcels.blocks_interactions():return []
	var records: Array = []
	if require_fresh and state_age > 8.0: return records
	var identity := identity_payload()
	for record: Dictionary in state.get("terminals",[])+state.get("delivery_contacts",[]):
		if not record.get("position") is Array or record.position.size()!=3: continue
		if str(record.get("building_id","0")) != str(identity.building_id) or int(record.get("cell_index",0)) != int(identity.cell_index): continue
		var value := record.duplicate(true)
		value.position = world(record.position)
		if is_instance_valid(scenery) and scenery.has_method("screen_offsets") and record.get("kind") not in ["trainer","delivery"]:
			var basis: Basis=scenery.terminal_basis(record)
			if is_instance_valid(app.stage):basis=app.stage.global_basis*basis
			var object_pose:=Transform3D(basis,value.position)
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
	if epoch != app.datapad_epoch: reset()
	presence_age += delta
	state_age += delta
	for marker: Node3D in peer_markers.values(): marker.advance(delta)
	if presence_age > 0.8 and not peer_markers.is_empty(): update_peer_markers()
	if is_instance_valid(scenery): scenery.advance(delta)
	if not allowed: have_previous=false; return
	if is_instance_valid(ui) and not ui.terminal.is_empty() and ui.terminal.get("kind","") not in ["payment","boarding"]:
		# A background scheduler delay cannot close an otherwise static panel.
		# New discovery still requires fresh records; every mutation revalidates natively.
		if not terminal_records(false).any(func(record): return str(record.id)==str(ui.terminal.id)):
			ui.close_interface()
	poll_clock -= delta
	if poll_clock <= 0 and not busy and not (is_instance_valid(ui) and ui.pointer_pressed) and (not app.has_method("try_background_poll") or app.try_background_poll("services")):
		poll_clock=5.0
		var detail: Dictionary={}
		if is_instance_valid(ui) and not ui.terminal.is_empty() and ui.terminal.get("kind","") not in ["payment","boarding"]: detail.terminal_id=str(ui.terminal.id)
		if is_instance_valid(ui) and ui.terminal.get("kind","")=="bazaar": detail.merge(ui.panel.browse_payload(),true)
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

func services_poll_interval(snapshot: Dictionary) -> float:
	# Distant planetary shuttle state does not justify another native scene login.
	if is_instance_valid(ui) and str(ui.terminal.get("kind","")) in ["travel","boarding"]:return 1.0
	if is_instance_valid(app) and is_instance_valid(app.get("player")):
		for shuttle in snapshot.get("shuttles",[]):
			if not shuttle is Dictionary or not shuttle.get("position") is Array or shuttle.position.size()!=3:continue
			if world(shuttle.position).distance_to(app.player.global_position)<=40.0:return 1.0
	return 5.0
