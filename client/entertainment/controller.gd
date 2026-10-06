extends Node3D
## Shared adapter presence + original playback. Persistent buffs stay Core3-owned.
const HandInput = preload("res://scripts/tracked_hand_input.gd")
var assets = preload("res://entertainment/assets.gd").new()
var native:Node
var gestures = preload("res://entertainment/gestures.gd").new()
var motion := SwgPerformanceGesture.new()
var models = preload("res://scripts/inventory_assets.gd").new()
var host: Node
var body: CharacterBody3D
var origin: XROrigin3D
var head: Camera3D
var context: Dictionary = {}
var token := ""
var account := ""
var state: Dictionary = {}
var item: Dictionary = {}
var selected: Dictionary = {}:
	get:
		return body.combat_pools.selection if is_instance_valid(body) and body.combat_pools.selection_owner=="entertainer" else {}
	set(value):
		if is_instance_valid(body):
			if not value.is_empty(): body.combat_pools.replace_selection(value,"entertainer")
			elif body.combat_pools.selection_owner=="entertainer": body.combat_pools.replace_selection({})
var primed := false:
	get: return is_instance_valid(body) and body.combat_pools.selection_owner=="entertainer" and body.combat_pools.primed
	set(value):
		if is_instance_valid(body) and body.combat_pools.selection_owner=="entertainer": body.combat_pools.primed=value
var ui: Node3D
var held_model: Node3D
var held_pose := Transform3D.IDENTITY
var circles: Dictionary = {}
var voices: Dictionary = {}
var pending := false
var actions: Array = []
var sequence := 0
var poll_time := 0.0
var server_clock := 0.0
var since_reply := 100.0
var click_down := false
var a_down := false
var stick_latched := false
var message := ""
var active_performance: Dictionary = {}
var clip_key := ""
var clip_time := 0.0
var generation := 0
var keyboard_pose := Transform3D.IDENTITY

func _ready() -> void:
	native=preload("res://entertainment/native_controller.gd").new();add_child(native)
	assets.load_catalog()
	models.configure(assets.directory.path_join("items/catalog.json"))
	ui = preload("res://combat/ability_hologram.gd").new()
	add_child(ui)
	process_physics_priority = -60
	process_priority = 90

func configure(owner_node: Node, player: CharacterBody3D, xr: XROrigin3D, session: Dictionary, login: String) -> void:
	reset()
	host = owner_node
	body = player
	origin = xr
	head = player.get_camera()
	context = session.get("context",{})
	token = str(session.get("token",""))
	account = login
	body.feedback.performer = self
	native.setup(self)

func reset() -> void:
	generation += 1
	if is_instance_valid(native):native.reset()
	token = ""; state = {}; context = {}; actions.clear(); selected = {}; primed = false
	active_performance = {}; clip_key = ""; pending = false; item = {}
	clear_presentation()
	if is_instance_valid(held_model): held_model.queue_free()
	held_model = null
	if is_instance_valid(ui): ui.close(); ui.update_badge({},false,0,Vector3.ZERO,false)
	motion.reset(); gestures.reset()

func clear_presentation() -> void:
	for node in circles.values(): if is_instance_valid(node): node.queue_free()
	circles.clear()
	for entry in voices.values():
		if is_instance_valid(entry.player): entry.player.queue_free()
	voices.clear()

func dominant() -> String:
	return body.dominant_hand if is_instance_valid(origin) else "right"

func owns_controls() -> bool:
	if not body.active or not (context.get("entertainer",false) or (is_instance_valid(native) and (native.image_eligible() or native.group_available()))): return false
	if is_instance_valid(native) and is_instance_valid(native.design_ui) and not native.design_ui.terminal.is_empty():return false
	if is_instance_valid(host.inventory) and host.inventory.is_open: return false
	if is_instance_valid(host.datapad) and host.datapad.is_open: return false
	if is_instance_valid(host.inventory) and not host.inventory.held_item.is_empty() and item.is_empty(): return false
	return not is_instance_valid(host.combat_rig) or host.combat_rig.selected < 0

func reserves_datapad() -> bool:
	# Priming a learned performance explicitly reserves its gesture. Inventory
	# remains available for switching props; an already-open datapad keeps focus.
	return owns_controls() and not body.feedback.combat_blocked() and (primed or ui.menu_open or gestures.join_time > 0.0 or is_performing() or (is_instance_valid(native) and native.get("pending_actions") is Array and not native.get("pending_actions").is_empty()))

func blocks_interactions()->bool:
	return is_instance_valid(native) and is_instance_valid(native.design_ui) and not native.design_ui.terminal.is_empty()

func is_performing() -> bool:
	return not active_performance.is_empty() and since_reply < 3 and body.active and not body.feedback.combat_blocked()

func set_item(value: Dictionary) -> void:
	var template := str(value.get("template","")).replace("/shared_","/")
	var supported: bool = assets.catalog.get("items",{}).has(template) and template != "object/static/item/item_ribbon.iff"
	item = value.duplicate(true) if supported else {}
	selected = {}; primed = false; motion.reset()
	if is_instance_valid(ui): ui.close()
	if is_instance_valid(held_model): held_model.queue_free()
	held_model = null
	if not supported: return
	var mesh: ArrayMesh = models.model(template, value.get("customization",{}))
	if mesh == null: message = "Original prop model unavailable"; return
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	held_model = visual
	add_child(held_model)
	keyboard_pose = Transform3D(Basis(Vector3.UP,head.global_rotation.y),body.global_position-head.global_basis.z.slide(Vector3.UP).normalized()*0.8)
	# Original asset dimensions, with grip anchored at object origin.
	if is_instance_valid(host.inventory): host.inventory.set_held_visual_enabled(false)
	poll_time = 1

func eligible_menu() -> Array:
	var entries: Array = []
	if is_instance_valid(native) and native.image_eligible():entries.append({"id":"image_design","label":"Image Design","source_command":"imagedesign"})
	if is_instance_valid(native) and native.has_method("group_available"):
		if native.group_available():entries.append({"id":"group_join","label":"Accept Group Invite","source_command":"join"})
		if native.image_eligible() or context.get("entertainer",false):entries.append({"id":"group_invite","label":"Invite to Group","source_command":"invite"})
		if str(native.state.get("group_id","0")) not in ["","0"]:entries.append({"id":"group_leave","label":"Leave Group","source_command":"leavegroup"})
	if not context.get("entertainer",false): return entries
	var band := str(state.get("band_id",""))
	if band.is_empty(): entries.append({"id":"start_band","label":"Start Band","source_command":"startband"})
	else: entries.append({"id":"leave","label":"Leave Band","source_command":"stopmusic"})
	if band.is_empty() or str(state.get("leader","")) == str(context.get("character_id","")):
		if is_performing(): entries.append({"id":"stop","label":"Stop Performance","source_command":"stopmusic"})
		entries.append_array(assets.performances(context,item))
	if is_instance_valid(host.get("scout")):
		var entry: Dictionary=host.scout.mask_entry()
		if not entry.is_empty(): entries.append(entry)
	return entries

func apply_native_context(value:Dictionary)->void:
	if value==context:return
	context=value.duplicate(true)
	var permitted:Array=assets.performances(context,item)
	if not selected.is_empty() and not permitted.any(func(row):return row.id==selected.get("id","")):
		selected={};primed=false;motion.reset()
	if is_instance_valid(ui):ui.close()

func queue_action(action: String, detail: Dictionary = {}) -> void:
	if action in ["perform","stop","flourish","group_join","group_leave"]:
		if is_instance_valid(native):native.request(action,detail)
		else:message="Waiting for the native entertainer session."
		return
	if token.is_empty() or actions.size() >= 4: return
	var entry := detail.duplicate(true)
	entry["action"] = action
	actions.append(entry)
	poll_time = 1

func flourish() -> bool:
	if not is_performing(): return false
	queue_action("flourish")
	return true

func sample_menu(click: bool, stick: Vector2, a_pressed: bool, tracked: bool) -> void:
	var permitted: bool = owns_controls() and tracked and not body.feedback.combat_blocked()
	if not permitted:
		ui.close(); stick_latched = false; motion.reset()
	else:
		if click and not click_down:
			if ui.menu_open: ui.close()
			else: ui.open_on_hand(eligible_menu(),origin.get_node(dominant().capitalize()+"Hand") if is_instance_valid(origin) else head,head)
			stick_latched = true
		if ui.menu_open:
			var choice: String = ui.sample_stick(stick)
			if choice=="image_design" and is_instance_valid(native):native.image_open_selector()
			elif choice=="group_invite" and is_instance_valid(native):native.group_selector()
			elif choice in ["start_band","leave","stop","group_join","group_leave"]: queue_action(choice); selected={}; primed=false
			elif choice=="mask_scent" and is_instance_valid(host.get("scout")): host.scout.select_mask()
			elif not choice.is_empty():
				selected = assets.catalog.performances.get(choice,{})
				primed = not selected.is_empty(); motion.reset()
		# A performs a flourish during playback; otherwise it primes the selection.
		if a_pressed and not a_down and not ui.menu_open:
			if body.combat_pools.selected=="mask_scent" and is_instance_valid(host.get("scout")): host.scout.activate_mask()
			elif is_performing(): flourish()
			elif not selected.is_empty(): primed = not primed; motion.reset()
		if not ui.menu_open and stick.length() < 0.25: stick_latched = false
	click_down = click; a_down = a_pressed
	if permitted and body.has_method("set_combat_capture"):
		body.set_combat_capture(dominant() if ui.menu_open or stick_latched else "",true)

func _physics_process(delta: float) -> void:
	if not is_instance_valid(body) or not body.active:return
	server_clock += delta; since_reply += delta; poll_time += delta
	if since_reply > 3:
		active_performance = {}; clip_key = ""; clear_presentation()
	var tracked := false
	if is_instance_valid(origin):
		var main: XRController3D = origin.get_node("LeftHand" if dominant()=="left" else "RightHand")
		var off: XRController3D = origin.get_node("RightHand" if dominant()=="left" else "LeftHand")
		var hmd = XRServer.get_tracker("head")
		var pose: XRPose = hmd.get_pose("default") if hmd != null else null
		tracked = pose != null and pose.has_tracking_data and HandInput.controller_tracked(main)
		var right: XRController3D = origin.get_node("RightHand")
		sample_menu(main.is_button_pressed("primary_click"), main.get_vector2("primary"), right.is_button_pressed("ax_button"), tracked)
		var permitted: bool = owns_controls() and tracked and not body.feedback.combat_blocked()
		if primed and permitted and not ui.menu_open:
			var descriptor: Dictionary = assets.catalog.items.get(str(item.get("template","")).replace("/shared_","/"),{})
			var kind := "dance" if item.is_empty() else str(descriptor.get("gesture",""))
			if motion.sample(delta,kind,head.global_transform,main.global_transform,off.global_transform,HandInput.controller_tracked(off) or kind=="wind",gestures.dance_hands(main,off) if kind=="dance" else {}):
				queue_action("perform",{"performance_id":selected.id}); primed=false
		var near := nearest_band()
		var left: XRController3D = origin.get_node("LeftHand")
		if gestures.join_sample(delta,not near.is_empty() and str(state.get("band_id","")).is_empty() and permitted,
			gestures.thumbs_up(left,"left"),gestures.thumbs_up(right,"right"),tracked and HandInput.controller_tracked(off)):
			queue_action("join",{"band_id":near.id})
	else: tracked = body.active # Desktop debug input never fabricates a physical gesture.
	if not token.is_empty() and poll_time >= 0.2 and not pending:
		poll_time = 0
		send_update(tracked and body.active and not body.feedback.combat_blocked())
	update_playback()

func send_update(enabled: bool) -> void:
	if not is_instance_valid(host): return
	pending = true
	var epoch := generation
	var payload: Dictionary = actions.pop_front() if not actions.is_empty() else {}
	sequence += 1
	payload.merge({"account":account,"token":token,"seq":sequence,"position":[body.global_position.x,body.global_position.y,body.global_position.z],
		"area":preload("res://scripts/planet_catalog.gd").current(host),"item_id":str(item.get("id","")),"enabled":enabled})
	var reply: Dictionary = await host.api(HTTPClient.METHOD_POST,"/performance",payload)
	if epoch != generation: return
	pending = false
	if not reply.get("ok",false):
		message = str(reply.get("error","Performance connection unavailable"))
		return
	apply_snapshot(reply)

func apply_snapshot(reply: Dictionary) -> void:
	if is_instance_valid(native):native.observe_bus(reply)
	state = reply.duplicate(true)
	server_clock = float(reply.get("server_time",0)); since_reply=0
	active_performance = assets.catalog.get("performances",{}).get(str(reply.get("performance_id","")),{})
	message = "Following band leader" if not str(state.get("band_id","")).is_empty() and str(state.get("leader",""))!=str(context.get("character_id","")) else ""

func nearest_band() -> Dictionary:
	var nearest := {}
	var distance := INF
	for band: Dictionary in state.get("bands",[]):
		var position := Vector3(band.position[0],band.position[1],band.position[2])
		var diff := position-body.global_position
		var d := Vector2(diff.x,diff.z).length()
		if absf(diff.y)<1.8 and d<=float(band.radius) and d<distance:
			nearest=band; distance=d
	return nearest

func animation_context() -> Dictionary:
	return {"performance_clip":clip_key,"performance_time":clip_time} if is_performing() else {}

func _process(_delta: float) -> void:
	if not is_instance_valid(body) or not is_instance_valid(ui): return
	if is_instance_valid(held_model):
		var hand: Node3D = origin.get_node("LeftHand" if dominant()=="left" else "RightHand") if is_instance_valid(origin) else head
		held_pose = hand.global_transform
		if not is_instance_valid(origin): held_pose.origin += head.global_basis*Vector3(0.2,-0.25,-0.45)
		if is_instance_valid(host.tracked_avatar): held_pose = host.tracked_avatar.limit_weapon_pose(dominant(),held_pose)
		if item_gesture()=="keyboard": held_pose=keyboard_pose
		held_model.global_transform=held_pose
		held_model.visible=body.active and owns_controls()
		if is_instance_valid(host.inventory): host.inventory.set_held_visual_enabled(false)
	var point := held_pose.origin if is_instance_valid(held_model) else head.global_position-head.global_basis.z*0.4
	var badge_selection: Dictionary=selected
	ui.update_badge(badge_selection,body.combat_pools.primed,float(body.combat_pools.cooldowns.get(body.combat_pools.selected,0)),point+Vector3.UP*0.20,owns_controls(),message)

func hand_target(side: String) -> Variant:
	return held_pose if item_gesture()!="keyboard" and side==dominant() and is_instance_valid(held_model) and held_model.visible else null

func item_gesture() -> String:
	return "dance" if item.is_empty() else str(assets.catalog.get("items",{}).get(str(item.get("template","")).replace("/shared_","/"),{}).get("gesture",""))

func constrain_prop() -> void:
	if item_gesture()!="keyboard" and is_instance_valid(held_model) and is_instance_valid(host.tracked_avatar):
		held_pose=host.tracked_avatar.limit_weapon_pose(dominant(),held_pose)
		held_model.global_transform=held_pose

func circle(band: Dictionary) -> Node3D:
	var root_node := Node3D.new()
	var line := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius=float(band.radius)-0.025; mesh.outer_radius=float(band.radius)+0.025
	mesh.rings=96; mesh.ring_segments=6
	line.mesh=mesh
	line.visibility_range_end=float(assets.catalog.get("cull_distance",96))
	line.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color=Color(0.15,0.85,1,0.5)
	line.material_override=material
	root_node.add_child(line)
	add_child(root_node)
	return root_node

func update_playback() -> void:
	var seen: Dictionary = {}
	var heard: Dictionary = {}
	clip_key=""
	if since_reply>3 or not body.active: clear_presentation(); return
	for band: Dictionary in state.get("bands",[]):
		seen[band.id]=true
		if not circles.has(band.id): circles[band.id]=circle(band)
		var position := Vector3(band.position[0],band.position[1],band.position[2])
		circles[band.id].global_position=position+Vector3.UP*0.035
		for member: Dictionary in band.members:
			var performance: Dictionary = assets.catalog.performances.get(str(member.performance_id),{})
			if performance.is_empty(): continue
			var elapsed := maxf(0,server_clock-float(band.started))
			var flourish: Dictionary = band.get("flourish",{})
			var key := "perform_"+str(performance.animation)
			var sound_key := "mainloop"
			var time := elapsed
			var serial := str(band.revision)
			if flourish.get("actor","")==member.id and int(flourish.get("index",0)) in range(1,9):
				var flourish_elapsed := maxf(0,server_clock-float(flourish.time))
				var candidate := key+"_"+str(int(flourish.index))
				var rig: Dictionary = assets.catalog.rigs.get(str(host.avatar.race_id) if is_instance_valid(host.avatar) else "human_male",{})
				var duration := float(rig.get(candidate,{}).get("length",0))
				if flourish_elapsed<duration:
					key=candidate; sound_key="flourish"+str(int(flourish.index)); time=flourish_elapsed; serial += ":"+str(flourish.time)
			if member.id==str(context.get("character_id","")):
				clip_key=key; clip_time=time
			var snd := str(performance.sounds.get(sound_key,""))
			if snd.is_empty(): continue
			var definition: Dictionary = assets.catalog.sounds.get(snd,{})
			if definition.get("samples",[]).is_empty(): continue
			heard[member.id]=true
			var identity := str(performance.id)+":"+serial+":"+sound_key
			if voices.has(member.id) and voices[member.id].key!=identity:
				voices[member.id].player.queue_free(); voices.erase(member.id)
			if not voices.has(member.id):
				var stream: AudioStreamWAV = assets.sound(str(definition.samples[0])).duplicate()
				if sound_key=="mainloop":
					stream.loop_mode=AudioStreamWAV.LOOP_FORWARD
					stream.loop_end=int(stream.get_length()*stream.mix_rate)
				var service := get_node_or_null("/root/SWGSpatialAudio")
				var audio: AudioStreamPlayer3D = service.create_player(2.0,96.0) if service!=null else AudioStreamPlayer3D.new()
				audio.stream=stream; audio.max_distance=96; audio.volume_db=linear_to_db(maxf(0.001,float(definition.get("volume",1))))
				add_child(audio)
				voices[member.id]={"key":identity,"player":audio}
				audio.play(fmod(time,maxf(0.01,stream.get_length())))
			voices[member.id].player.global_position=Vector3(member.position[0],member.position[1]+1.1,member.position[2])
	for key in circles.keys():
		if not seen.has(key): circles[key].queue_free(); circles.erase(key)
	for key in voices.keys():
		if not heard.has(key): voices[key].player.queue_free(); voices.erase(key)

func _exit_tree() -> void:
	clear_presentation()
