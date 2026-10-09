extends Node3D
## Weapon and rendered-hand orchestration; XR tracking stays untouched.
const WeaponState = preload("res://combat/weapon_state.gd")
const Projectiles = preload("res://combat/projectiles.gd")
const HandInput = preload("res://scripts/tracked_hand_input.gd")
var movement_spread=preload("res://combat/movement_spread.gd").new()
var spice_gunhand=preload("res://spice/gunhand.gd").new()
var assets = preload("res://combat/original_assets.gd").new()
var reticle: MeshInstance3D
var origin: XROrigin3D
var head: Camera3D
var body: CharacterBody3D
var datapad: Node3D
var inventory: Node3D
var scout: Node3D
var interaction_blocker: Callable
# Optional live authority. Unset only in explicit local/offline inspection modes.
var authority_gate: Callable
var shot_authority: Callable
var commando_authority: Callable
var bountyhunter_context:Dictionary={}
var bountyhunter_authority:Callable
var bountyhunter_key:=""
var bountyhunter_input_captured:=false
var bountyhunter_armed_until:=0
var bountyhunter_arm_item:=""
var bountyhunter_arm_pending:=""
var bountyhunter_arm_pending_shot:=""
var bountyhunter_arm_pending_until:=0
var bountyhunter_gestures=preload("res://combat/bountyhunter_gestures.gd").new()
var rifleman_context:Dictionary={}
var rifleman_authority:Callable
var rifleman_key:=""
var rifleman_input_captured:=false
var rifleman_gestures=preload("res://combat/rifleman_gestures.gd").new()
var carbineer_context:Dictionary={}
var carbineer_authority:Callable
var carbineer_key:=""
var carbineer_input_captured:=false
var carbineer_gestures=preload("res://combat/carbineer_gestures.gd").new()
var pistoleer_context:Dictionary={}
var pistoleer_authority:Callable
var pistoleer_key:=""
var pistoleer_input_captured:=false
var pistoleer_gestures=preload("res://combat/pistoleer_gestures.gd").new()
var showdown:Dictionary={}
var showdown_gate:Callable
var showdown_target:Node3D
var brawler_authority:Callable
var brawler_context:Dictionary={}
var pikeman_context:Dictionary={}
var pikeman_authority:Callable
var pikeman_key:=""
var pikeman_ultimate:=""
var pikeman_input_captured:=false
var pikeman_basis:=Basis.IDENTITY
var pikeman_gestures=preload("res://combat/pikeman_gestures.gd").new()
var fencer_context:Dictionary={}
var fencer_authority:Callable
var fencer_key:=""
var fencer_ultimate:=""
var fencer_input_captured:=false
var fencer_basis:=Basis.IDENTITY
var fencer_gestures=preload("res://combat/fencer_gestures.gd").new()
var swordsman_context:Dictionary={}
var swordsman_authority:Callable
var swordsman_key:=""
var swordsman_ultimate:=""
var swordsman_input_captured:=false
var swordsman_gestures=preload("res://combat/swordsman_gestures.gd").new()
var tka_context:Dictionary={}
var tka_authority:Callable
var tka_key:=""
var tka_ultimate:=""
var tka_input_captured:=false
var tka_basis:=Basis.IDENTITY
var tka_gestures=preload("res://combat/tka_gestures.gd").new()
var brawler_weapon_id:=""
var brawler_gestures=preload("res://combat/brawler_gestures.gd").new()
var brawler_input_captured:=false
var melee_marker_previous:Dictionary={}
var warcry_authority: Callable
var warcry_context: Dictionary={}
var overhead_warcry=preload("res://combat/overhead_warcry.gd").new()
var warcry_input_captured:=false
var taunt_authority: Callable
var taunt_context: Dictionary={}
var chest_taunt=preload("res://combat/chest_taunt.gd").new()
var taunt_input_captured:=false
var inventory_item_id := ""
var inventory_reserved_ids: Dictionary = {}
var tracked_avatar: Node3D
var dominant := "right"
var allowed := false
var weapons: Array[Dictionary] = []
var selected := -1
var two_hands := false
var requested_weapon_pose := Transform3D.IDENTITY
var have_weapon_request := false
var shared_pose_report: Dictionary = {}
var main_grip_down := false
var support_grip_down := false
var offhand_occupied := false
var support_latched := false
var action_down := false
var rounds_sim: Node3D
var last_error := ""
var desktop_support := false
var posture_tracker = preload("res://combat/firing_posture.gd").new()
var camera_yaw := 0.0
var captured_pointer: Node
var pointer_was_enabled := false
var hand_targets: Dictionary = {}
var bound_gloves: Dictionary = {}
var desktop_swing_remaining := 0.0
var unarmed: Dictionary = {}
var unarmed_gloves: Dictionary = {}
var abilities = preload("res://combat/ability_state.gd").new()
var ability_ui: Node3D
var squad_leader:Node3D
var squad_input_captured:=false
var squad_release_pending:=false
var target_abilities: Node3D
var ability_click_down := false
var ability_prime_down := false
var ability_stick_latched := false
var dna_input_captured := false
var physical_guard=preload("res://combat/physical_guard.gd").new()
var guard_head:=Vector3.ZERO
var guard_forward:=Vector3.FORWARD
var guard_feedback_blocks:=-1
var guard_sample_ms:=-1000

func configure_player_combat(context: Dictionary) -> void:
	if is_instance_valid(body) and body.has_method("configure_player_combat"): body.configure_player_combat(context)
	else: abilities.refresh_context(context)

func combat_actions_allowed() -> bool:
	# Friendly VATS owns treatment controls while the Doctor focus is held.
	# Blocking at the shared attack gate also covers melee and volley paths.
	var medic:Variant=body.get("medic") if is_instance_valid(body) else null
	if is_instance_valid(medic) and medic.has_method("captures_combat") and medic.captures_combat():return false
	if authority_gate.is_valid() and not bool(authority_gate.call()): return false
	return not is_instance_valid(body) or not body.has_method("combat_actions_allowed") or body.combat_actions_allowed()

func active_profile() -> Dictionary:
	var profile: Dictionary={}
	if selected>=0:
		if weapons[selected].state.certified(): profile=weapons[selected].state.profile.duplicate(true)
	elif unarmed.has(dominant): profile=unarmed[dominant].profile.duplicate(true)
	if is_instance_valid(scout):
		for entry: Dictionary in [scout.mask_entry(),scout.dna_entry()]:
			if entry.is_empty(): continue
			if not profile.has("abilities"): profile["abilities"]=[]
			profile.abilities.append(entry)
	return profile

func sample_dna_inputs(main_pose: Transform3D, support_pose: Transform3D, main_trigger: float, support_trigger: float, main_tracked: bool, support_tracked: bool) -> void:
	dna_input_captured=false
	if not is_instance_valid(scout): return
	var permitted: bool=allowed and combat_actions_allowed() and inventory_allows_combat() and not ability_ui.menu_open and not (is_instance_valid(datapad) and datapad.is_open)
	var offhand:="left" if dominant=="right" else "right"
	# Both edges are sampled before any gun or fist can consume these triggers.
	var main_capture: bool=scout.sample_dna_hand(dominant,main_pose,main_trigger,main_tracked,permitted and not pet_trigger_reserved(dominant) and not vehicle_hand_busy(dominant))
	var off_capture: bool=scout.sample_dna_hand(offhand,support_pose,support_trigger,support_tracked,permitted and not offhand_occupied and not pet_trigger_reserved(offhand) and not vehicle_hand_busy(offhand))
	dna_input_captured=main_capture or off_capture

func close_ability_menu() -> void:
	if is_instance_valid(ability_ui): ability_ui.close()

func party_menu_controller()->Node:
	if not is_instance_valid(body) or not is_instance_valid(body.get("feedback")):return null
	var performer:Variant=body.feedback.get("performer")
	return performer.native if is_instance_valid(performer) and is_instance_valid(performer.get("native")) and performer.native.has_method("party_menu_entries") else null

func circle_entries(profile:Dictionary)->Array:
	var entries:Array=profile.get("abilities",[]).filter(func(entry):return entry.get("activation","") not in ["native_ranged","native_melee","tka_gesture","swordsman_gesture","fencer_gesture","pikeman_gesture","pistoleer_gesture","carbineer_gesture","carbineer_ultimate","commando_ultimate","squadleader_support","squad_leader_ultimate","rifleman_gesture","bountyhunter_gesture","life_recovery"]).duplicate(true)
	var party:=party_menu_controller()
	if party!=null:entries.append_array(party.party_menu_entries())
	return entries

func select_circle_entry(choice:String,profile:Dictionary)->void:
	var party:=party_menu_controller()
	if choice=="group_leave" and party!=null and party.party_member():party.request("group_leave");return
	abilities.select(profile,choice)
	if choice=="mask_scent":abilities.primed=true

func sample_ability_input(click: bool, stick: Vector2, prime: bool, tracked: bool) -> void:
	if is_instance_valid(body) and body.has_method("combat_actions_allowed") and is_instance_valid(body.feedback.performer) and body.feedback.performer.owns_controls():
		close_ability_menu()
		ability_click_down=click; ability_prime_down=prime
		return
	var permitted: bool = allowed and tracked and combat_actions_allowed() and inventory_allows_combat() and not (is_instance_valid(datapad) and datapad.is_open)
	var profile := active_profile()
	abilities.reconcile(profile)
	if (selected>=0 or unarmed.has(dominant)) and is_instance_valid(target_abilities):
		# Targeted combat uses the body overlay instead of circle selection.
		if abilities.selection.get("activation","") in ["native_ranged","native_melee","tka_gesture","swordsman_gesture","fencer_gesture","pikeman_gesture","pistoleer_gesture","carbineer_gesture","carbineer_ultimate","commando_ultimate","squadleader_support","squad_leader_ultimate","rifleman_gesture","bountyhunter_gesture","life_recovery"]:
			abilities.primed=false;abilities.replace_selection({})
		close_ability_menu();ability_stick_latched=false
		if not permitted:
			target_abilities.reset()
			if is_instance_valid(squad_leader):squad_leader.close()
		elif click and not ability_click_down:
			var pose:=head.global_transform if selected<0 or weapons[selected].state.is_melee() else muzzle_pose(selected)
			if not is_instance_valid(squad_leader) or not squad_leader.toggle(pose):target_abilities.toggle(pose)
			squad_input_captured=is_instance_valid(squad_leader) and squad_leader.active()
		ability_click_down=click;ability_prime_down=prime
		if is_instance_valid(body) and body.has_method("set_combat_capture"):body.set_combat_capture("",false)
		return
	if not permitted:
		if not tracked: abilities.primed=false
		close_ability_menu()
		ability_stick_latched = false
	else:
		if click and not ability_click_down:
			if ability_ui.menu_open: close_ability_menu()
			else:
				ability_ui.open_on_hand(circle_entries(profile),origin.get_node(dominant.capitalize()+"Hand") if is_instance_valid(origin) else head,head)
			ability_stick_latched = true
		if ability_ui.menu_open:
			var choice: String = ability_ui.sample_stick(stick)
			if not choice.is_empty():
				select_circle_entry(choice,profile)
		if prime and not ability_prime_down and not ability_ui.menu_open:
			if abilities.selected=="mask_scent" and is_instance_valid(scout): scout.activate_mask()
			else: abilities.toggle_prime(profile)
		if not ability_ui.menu_open and stick.length() < 0.25: ability_stick_latched = false
	ability_click_down = click
	ability_prime_down = prime
	if is_instance_valid(body) and body.has_method("set_combat_capture"):
		body.set_combat_capture(dominant if permitted and (ability_ui.menu_open or ability_stick_latched) else "", permitted and not profile.is_empty())

func configure(camera: Camera3D, player: CharacterBody3D, profiles: Array, side := "right", xr: XROrigin3D = null) -> bool:
	head = camera; body = player; origin = xr
	if body.has_method("configure_player_combat"): abilities = body.combat_pools
	# Update grip targets before XR Tools renders its hands (-70).
	process_physics_priority = -80
	process_priority = 50
	for hand_side in ["left","right"]:
		var target := Node3D.new()
		target.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF
		add_child(target)
		hand_targets[hand_side] = target
	dominant = "left" if side == "left" else "right"
	if body.has_method("combat_tracking_context"):
		body.dominant_hand = dominant
		body.combat_rig = self
	ability_ui = preload("res://combat/ability_hologram.gd").new()
	add_child(ability_ui)
	target_abilities=preload("res://combat/target_abilities.gd").new();add_child(target_abilities);target_abilities.setup(self)
	squad_leader=preload("res://combat/squad_leader.gd").new();add_child(squad_leader);squad_leader.setup(self)
	if not assets.load_catalog():
		last_error = "Original weapon assets missing. Run python3 tools/combat/prepare_assets.py."
		return false
	for profile in profiles:
		if not assets.catalog.weapons.has(profile.id):
			last_error = "Original weapon asset unavailable: " + str(profile.id)
			return false
	# Decode original WAVs while entering the lab, avoiding disk I/O on the trigger.
	for definition in assets.catalog.sounds.values():
		for sample in definition.samples: assets.sound(sample)
	reticle = preload("res://combat/aim_reference.gd").new()
	add_child(reticle)
	reticle.configure(assets.texture(assets.catalog.reticle.path))
	rounds_sim = Projectiles.new()
	add_child(rounds_sim)
	rounds_sim.excluded.append(body.get_rid())
	rounds_sim.configure_effects(assets,head)
	for data in profiles:
		var state := WeaponState.new()
		state.ability_state = null if shot_authority.is_valid() else abilities
		if shot_authority.is_valid():state.wear_per_shot=0.0
		# Live snapshots use Core3's certification decision. Synthetic grants
		# remain confined to the explicitly labeled template lab.
		var owned_certificates: Array = data.core3.certificationsRequired if data.get("source_kind","")!="core3_weapon_instance" or data.get("certified",false) else []
		if not state.configure(data,owned_certificates,data.get("condition",{})):
			last_error = "Invalid local weapon profile"
			return false
		var visual := make_visual(data)
		visual.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF
		add_child(visual)
		var label := Label3D.new(); label.font = preload("res://resources/fonts/Jupiteroid-Regular.ttf")
		label.font_size = 20
		label.pixel_size = 0.00035
		label.position = Vector3(0,0.14,0)
		label.modulate = Color(0.59,0.96,0.99,0.55)
		label.outline_size = 1
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		visual.add_child(label)
		weapons.append({"state":state,"visual":visual,"label":label,"bounds":visual_bounds(visual)})
	update_visuals()
	return true

func configure_unarmed(profile: Dictionary) -> bool:
	if not profile.get("unarmed",false) or not WeaponState.valid_profile(profile): return false
	for state in unarmed.values(): state.block()
	unarmed.clear()
	for side in ["left","right"]:
		var state := WeaponState.new()
		state.ability_state = null if shot_authority.is_valid() else abilities
		if shot_authority.is_valid():state.wear_per_shot=0.0
		if not state.configure(profile,[]): return false
		unarmed[side]=state
	return true

func unarmed_engaged(side: String) -> bool:
	return allowed and selected<0 and unarmed.has(side) and unarmed[side].swing_feedback.get("engaged",false)

func pet_trigger_reserved(side: String)->bool:
	return is_instance_valid(body) and is_instance_valid(body.get("pet_controls")) and body.pet_controls.blocks_trigger(side)

func vehicle_hand_busy(side: String)->bool:
	return is_instance_valid(body) and is_instance_valid(body.get("vehicles")) and body.vehicles.hand_busy(side)

func sample_unarmed(delta: float, side: String, pose: Transform3D, tracked: bool, posture: String, trigger := 0.0) -> void:
	if not unarmed.has(side): return
	var permitted: bool = allowed and not squad_input_captured and not dna_input_captured and not taunt_input_captured and not warcry_input_captured and not brawler_input_captured and not tka_input_captured and not swordsman_input_captured and not fencer_input_captured and not pikeman_input_captured and not pistoleer_input_captured and not carbineer_input_captured and not rifleman_input_captured and not bountyhunter_input_captured and not pet_trigger_reserved(side) and selected<0 and tracked and not vehicle_hand_busy(side) and not (offhand_occupied and side!=dominant) and combat_actions_allowed() and not ability_ui.menu_open and not (is_instance_valid(datapad) and datapad.is_open) and not (is_instance_valid(inventory) and inventory.interaction_active)
	var shot: Dictionary=unarmed[side].sample_swing(delta,permitted,false,posture,swing_position(pose.origin),is_finite(trigger) and trigger>=0.5)
	var prior:Vector3=melee_marker_previous.get(side,pose.origin)
	melee_marker_previous[side]=pose.origin
	if is_instance_valid(target_abilities):
		target_abilities.sample_punch(side,pose.origin,delta,permitted and trigger>=.5)
		shot=target_abilities.melee_swing(shot,prior,pose.origin,side,delta,permitted and trigger>=.5)
	if not shot.is_empty():
		shot["hand"]=side
		if not dispatch_shot(shot,pose,pose.origin,unarmed[side].profile,true):return
		if is_instance_valid(origin):
			var controller: XRController3D=origin.get_node(side.capitalize()+"Hand")
			controller.trigger_haptic_pulse("haptic",0,0.35,0.045,0)

func update_unarmed_gloves() -> void:
	if not is_instance_valid(origin): return
	for side in ["left","right"]:
		var glove := origin.get_node_or_null(side.capitalize()+"Hand/Hand")
		if glove==null or not glove.has_method("force_grip_trigger"): continue
		if unarmed_engaged(side):
			glove.force_grip_trigger(1.0,1.0); unarmed_gloves[side]=glove
		elif unarmed_gloves.has(side):
			# Weapon overrides take over without being cleared by fist release.
			if not bound_gloves.has(side): glove.force_grip_trigger(-1.0,-1.0)
			unarmed_gloves.erase(side)

func make_visual(data: Dictionary) -> Node3D:
	return assets.model(str(data.id))

func melee_tip_local(index:int)->Vector3:
	var bounds:AABB=weapons[index].bounds
	var axis:=bounds.size.max_axis_index()
	var point:=bounds.get_center()
	point[axis]=bounds.end[axis] if absf(bounds.end[axis])>=absf(bounds.position[axis]) else bounds.position[axis]
	return point
func melee_tip(index:int)->Vector3:
	return weapons[index].visual.global_transform*melee_tip_local(index)

func muzzle_pose(index: int) -> Transform3D:
	var pose: Transform3D = weapons[index].visual.global_transform
	if weapons[index].state.is_melee(): return pose
	pose.origin = pose * assets.muzzle(str(weapons[index].state.profile.id))
	return pose

func grab_transform(hands: int) -> Transform3D:
	var anchors=preload("res://scripts/body_grab_anchor.gd")
	return anchors.shoulder(head,origin,dominant) if hands>1 else anchors.hip(head,origin,dominant)

func holster_transform(hands: int) -> Transform3D:
	var forward := -head.global_basis.z
	forward.y = 0
	if forward.length_squared() > 0.01: camera_yaw = atan2(-forward.x,-forward.z)
	var yaw_basis := Basis(Vector3.UP,camera_yaw)
	var race := str(tracked_avatar.avatar.race_id) if is_instance_valid(tracked_avatar) else "human_male"
	var mount: Dictionary = assets.stow_mount(race,hands,dominant)
	if not mount.is_empty():
		if is_instance_valid(tracked_avatar):
			var skeleton: Skeleton3D = tracked_avatar.skeleton
			var bone := skeleton.find_bone(mount.anchor)
			if bone >= 0:
				var pose: Transform3D = skeleton.global_transform * skeleton.get_bone_global_pose(bone) * mount.local
				# Character fitting moves the socket, never stretches the original gun.
				pose.basis = pose.basis.orthonormalized()
				return pose
		# Desktop/no-avatar inspection uses the same source-derived bind-space
		# socket, positioned below the camera; the live avatar supplies real bones.
		var source_pose: Transform3D = mount.rest * mount.local
		return Transform3D(yaw_basis,head.global_position-Vector3.UP*posture_tracker.standing_eye_height) * source_pose
	push_error("Missing source-derived weapon mount for " + race)
	return Transform3D(yaw_basis,head.global_position)

func visual_bounds(visual: Node3D) -> AABB:
	var bounds := AABB()
	var first := true
	for child in visual.get_children():
		if child is MeshInstance3D:
			var part: AABB = child.transform * child.get_aabb()
			bounds = part if first else bounds.merge(part)
			first = false
	return bounds

func visual_stow_transform(index: int) -> Transform3D:
	var hands := int(weapons[index].state.profile.hands)
	var socket := holster_transform(hands)
	if hands!=2: return socket
	var race := str(tracked_avatar.avatar.race_id) if is_instance_valid(tracked_avatar) else "human_male"
	var mount: Dictionary = assets.stow_mount(race,hands,dominant)
	var carry: Dictionary = mount.get("carry",{})
	if carry.is_empty(): return socket # Older local exports retain their audited source pose.
	var anchor: Transform3D
	if is_instance_valid(tracked_avatar):
		var skeleton: Skeleton3D = tracked_avatar.skeleton
		var bone := skeleton.find_bone(mount.anchor)
		if bone<0: return socket
		anchor = skeleton.global_transform * skeleton.get_bone_global_pose(bone)
	else:
		anchor = Transform3D(Basis(Vector3.UP,camera_yaw),head.global_position-Vector3.UP*posture_tracker.standing_eye_height) * mount.rest
	var center: Vector3 = anchor * Vector3(carry.center[0],carry.center[1],carry.center[2])
	var shoulder: Vector3 = anchor * Vector3(carry.shoulder[0],carry.shoulder[1],carry.shoulder[2])
	var up: Vector3 = (anchor.basis*Vector3(carry.up[0],carry.up[1],carry.up[2])).normalized()
	var back: Vector3 = (anchor.basis*Vector3(carry.back[0],carry.back[1],carry.back[2])).normalized()
	var bounds: AABB = weapons[index].bounds
	var pose := Transform3D(socket.basis,center-socket.basis*bounds.get_center())
	var highest := -INF
	var nearest_back := INF
	for corner in range(8):
		var point: Vector3 = pose*bounds.get_endpoint(corner)-center
		highest = maxf(highest,point.dot(up))
		nearest_back = minf(nearest_back,point.dot(back))
	# Fit the unscaled source weapon behind the torso, with 2.5 cm clearance.
	# Clamp its top to the shoulder/neck boundary; reach socket stays accessible.
	pose.origin += back*maxf(0.0,0.025-nearest_back)
	pose.origin -= up*maxf(0.0,highest-(shoulder-center).dot(up))
	return pose

func support_point(index: int) -> Vector3:
	return support_transform(index).origin

func support_transform(index: int) -> Transform3D:
	var offset := Vector3(0,-0.015,-0.25) if int(weapons[index].state.profile.hands)==2 else Vector3(0.035 if dominant=="left" else -0.035,-0.025,0.015)
	if weapons[index].state.is_melee() and int(weapons[index].state.profile.hands)==2:
		var source: Array = weapons[index].state.profile.get("support_offset",[0,-0.18,0])
		offset = Vector3(source[0],source[1],source[2])
	return weapons[index].visual.global_transform * Transform3D(Basis.IDENTITY,offset)

func hand_target(side: String) -> Variant:
	if not allowed or selected < 0: return null
	if side == dominant: return weapons[selected].visual.global_transform
	return support_transform(selected) if two_hands else null

func update_hand_targets() -> void:
	for side in hand_targets:
		var pose: Variant = hand_target(side)
		var glove: Node = origin.get_node_or_null(side.capitalize()+"Hand/Hand") if is_instance_valid(origin) else null
		if pose is Transform3D:
			var glove_pose: Transform3D = pose
			if glove != null and glove.has_method("force_grip_trigger"):
				var controller: XRController3D = origin.get_node(side.capitalize()+"Hand")
				# XR Tools applies its palm correction inside the hand model. Supply
				# its inverse here because this target already has weapon orientation.
				if glove.hand_offset_mode != 4:
					glove_pose *= XRTools.get_palm_offset(glove.hand_offset_mode,controller).affine_inverse()
			hand_targets[side].global_transform = glove_pose
			if glove != null and glove.has_method("add_target_override") and not bound_gloves.has(side):
				glove.add_target_override(hand_targets[side],100)
				if glove.has_method("force_grip_trigger"): glove.force_grip_trigger(1.0,-1.0 if side==dominant else 1.0)
				bound_gloves[side] = glove
		elif bound_gloves.has(side):
			if is_instance_valid(bound_gloves[side]):
				bound_gloves[side].remove_target_override(hand_targets[side])
				if bound_gloves[side].has_method("force_grip_trigger"): bound_gloves[side].force_grip_trigger()
			bound_gloves.erase(side)

func pose_weapon(main_pose: Transform3D, support_pose: Transform3D) -> void:
	if selected < 0: return
	var weapon := weapons[selected]
	var requested := main_pose
	if two_hands and int(weapon.state.profile.hands)==2 and support_pose.origin.distance_to(main_pose.origin)>0.10:
		var direction := (support_pose.origin-main_pose.origin).normalized()
		if weapon.state.is_melee():
			requested.basis = Basis(Quaternion(-main_pose.basis.y.normalized(),direction))*main_pose.basis
		else:
			var up := main_pose.basis.y
			if absf(direction.dot(up)) > 0.98: up = main_pose.basis.x
			requested.basis = Basis.looking_at(direction,up)
	# Keep the physical request separate: a corrected pose is never tomorrow's
	# input. Physics may use this coherent bound pair; the render solve projects
	# it again against this frame's prepared torso before solving either arm.
	if not weapon.state.is_melee() and is_instance_valid(body) and body.get("feedback")!=null:
		requested=spice_gunhand.sample(requested,main_pose,head.global_transform,Time.get_ticks_usec()/1000000.0,body.feedback.spice.policy(),spice_acquire_target,spice_target_position)
	requested_weapon_pose=requested;have_weapon_request=true
	constrain_held_weapon()

func spice_acquire_target(pose:Transform3D)->String:
	if selected<0:return ""
	var range_m:=float(weapons[selected].state.core.get("maxRange",64))
	var query:=PhysicsRayQueryParameters3D.create(pose.origin,pose.origin-pose.basis.z*range_m,15,[body.get_rid()])
	var hit:=get_world_3d().direct_space_state.intersect_ray(query)
	var actor:Variant=hit.get("collider")
	if not is_instance_valid(actor) or not actor.has_method("core3_identity") or not actor.has_method("is_targetable") or not actor.is_targetable():return ""
	var record:Dictionary=actor.record
	if record.get("relation","") not in ["hostile","attackable"]:return ""
	return str(record.id)
func spice_target_position(id:String)->Variant:
	for actor:Node in get_tree().get_nodes_in_group("swg_radar_contacts"):
		if not actor.has_method("is_targetable") or not actor.is_targetable() or str(actor.record.get("id",""))!=id:continue
		if actor.record.get("relation","") not in ["hostile","attackable"]:return null
		return actor.global_transform*actor.visual_bounds().get_center()
	return null

func constrain_held_weapon() -> void:
	if selected<0 or not have_weapon_request: return
	var visual: Node3D=weapons[selected].visual
	visual.global_transform=requested_weapon_pose
	if not is_instance_valid(tracked_avatar): return
	visual.global_transform=tracked_avatar.limit_weapon_pose(dominant,requested_weapon_pose,support_transform(selected) if two_hands else null)

func finalize_held_weapon() -> void:
	if selected<0 or not have_weapon_request or not is_instance_valid(tracked_avatar): return
	var skeleton:Skeleton3D=tracked_avatar.skeleton
	if not is_instance_valid(skeleton): return
	var hold:=skeleton.find_bone("hold_l" if dominant=="left" else "hold_r")
	if hold<0: return
	var solved:Transform3D=skeleton.global_transform*skeleton.get_bone_global_pose(hold)
	solved.basis=solved.basis.orthonormalized() # Original weapon remains metre-sized.
	weapons[selected].visual.global_transform=solved
	shared_pose_report={"tracking_to_shared_grip_m":solved.origin.distance_to(requested_weapon_pose.origin),"dominant":dominant,"two_hands":two_hands,"grip_errors_m":{}}
	for side:String in ["left","right"]:
		var target:Variant=hand_target(side)
		var bone:=skeleton.find_bone("hold_l" if side=="left" else "hold_r")
		if target is Transform3D and bone>=0:
			var actual:Transform3D=skeleton.global_transform*skeleton.get_bone_global_pose(bone)
			shared_pose_report.grip_errors_m[side]=actual.origin.distance_to(target.origin)
	update_hand_targets()

func set_allowed(value: bool) -> void:
	allowed = value
	if not value:
		chest_taunt.clear();taunt_input_captured=false;overhead_warcry.clear();warcry_input_captured=false;brawler_gestures.clear();brawler_input_captured=false;tka_gestures.clear();tka_input_captured=false;swordsman_gestures.clear();swordsman_input_captured=false;fencer_gestures.clear();fencer_input_captured=false;pikeman_gestures.clear();pikeman_input_captured=false;melee_marker_previous.clear()
		ability_stick_latched = false
		if is_instance_valid(body) and body.has_method("set_combat_capture"): body.set_combat_capture("", false)
		for weapon in weapons: weapon.state.block()
		if is_instance_valid(rounds_sim): rounds_sim.clear()
		stow()

func stow() -> void:
	clear_bountyhunter()
	cancel_showdown();pistoleer_gestures.clear();pistoleer_input_captured=false;carbineer_gestures.clear();carbineer_input_captured=false;rifleman_gestures.clear();rifleman_input_captured=false
	if is_instance_valid(target_abilities):target_abilities.reset()
	if is_instance_valid(squad_leader):squad_leader.close()
	squad_input_captured=squad_release_pending
	physical_guard.clear()
	spice_gunhand.suspend()
	close_ability_menu()
	if not inventory_item_id.is_empty() and is_instance_valid(inventory):
		inventory.set_external_use_active(false)
	inventory_item_id = ""
	for state in unarmed.values(): state.block()
	if selected >= 0: weapons[selected].state.block()
	selected = -1
	have_weapon_request=false;shared_pose_report.clear()
	two_hands = false; support_latched = false
	update_hand_targets()
	update_unarmed_gloves()
	restore_pointer()

func restore_pointer() -> void:
	if is_instance_valid(captured_pointer): captured_pointer.enabled = pointer_was_enabled
	captured_pointer = null

func draw(index: int) -> void:
	if index < 0 or index >= weapons.size(): return
	stow()
	selected = index
	weapons[index].state.block()
	if is_instance_valid(origin):
		var pointer := origin.get_node_or_null(("LeftHand" if dominant=="left" else "RightHand")+"/FunctionPointer")
		if pointer != null:
			captured_pointer = pointer
			pointer_was_enabled = pointer.enabled
			pointer.enabled = false

func set_standing_eye_height(height: float) -> bool:
	return posture_tracker.set_standing_eye_height(height)

func calibrate_standing_height() -> Dictionary:
	if not is_instance_valid(origin) or not body.has_method("combat_tracking_context"):
		return {"valid":false,"reason":"Tracked combat rig is unavailable."}
	var context: Dictionary = body.combat_tracking_context()
	if not context.get("tracked",false) or not context.get("grounded",false):
		return {"valid":false,"reason":"Stand on a supported floor with head tracking active."}
	var height := float(context.get("eye_height",NAN))
	if not set_standing_eye_height(height):
		return {"valid":false,"reason":"Stand upright before calibrating (0.8–2.5 m eye height)."}
	return {"valid":true,"standing_eye_height":height}

func current_firing_posture() -> String:
	if is_instance_valid(origin):
		var context: Dictionary = body.combat_tracking_context() if body.has_method("combat_tracking_context") else {}
		return posture_tracker.update_tracked(context)
	var posture: int = body.get_posture() if body.has_method("get_posture") else 0
	return posture_tracker.update_desktop(posture,body.get_grounded() if body.has_method("get_grounded") else body.is_on_floor())

func sample(delta: float, main_pose: Transform3D, support_pose: Transform3D, grip: float, support_grip: float, trigger: float, tracked: bool, support_tracked: bool, action := false, support_trigger := 0.0) -> void:
	movement_spread.sample(body.velocity,head.position,delta,tracked and allowed)
	var previous_grip := main_grip_down
	var previous_support := support_grip_down
	if grip < 0.25: main_grip_down = false
	elif grip > 0.65: main_grip_down = true
	if support_grip < 0.25: support_grip_down = false
	elif support_grip > 0.65: support_grip_down = true
	var permitted: bool = allowed and tracked and not (is_instance_valid(datapad) and datapad.is_open) and inventory_allows_combat()
	if not permitted:
		stow()
	else:
		if selected >= 0 and not main_grip_down: stow()
		if selected < 0 and main_grip_down and not previous_grip and not taunt_input_captured and not warcry_input_captured and not brawler_input_captured and not tka_input_captured and not swordsman_input_captured and not fencer_input_captured and not pikeman_input_captured and not pistoleer_input_captured and not carbineer_input_captured and not rifleman_input_captured and not bountyhunter_input_captured:
			var nearest := 0.22
			var candidate := -1
			for i in range(weapons.size()):
				if weapons[i].get("inventory_only",false) or inventory_reserved_ids.has(str(weapons[i].state.profile.get("item_id",""))): continue
				var distance := main_pose.origin.distance_to(grab_transform(int(weapons[i].state.profile.hands)).origin)
				if distance < nearest: nearest = distance; candidate = i
			if candidate >= 0: draw(candidate)
		if selected >= 0:
			var weapon := weapons[selected]
			weapon.visual.global_transform = main_pose
			if not support_grip_down or not support_tracked: support_latched = false
			var long_gun := int(weapon.state.profile.hands)==2
			var attach_point := support_point(selected) if long_gun else main_pose.origin
			if support_tracked and support_grip_down and not previous_support and support_pose.origin.distance_to(attach_point) < 0.18 and (not rifleman_input_captured and not bountyhunter_input_captured or rifleman_gestures.phase=="regrip"):
				support_latched = true
			# A pistol's rendered support hand stays attached until release; its
			# physical controller continues reporting input but cannot steer it.
			if long_gun and support_pose.origin.distance_to(main_pose.origin) > 0.65: support_latched = false
			two_hands = support_latched
			pose_weapon(main_pose,support_pose)
			if action and not action_down: weapon.state.cycle_mode()
	action_down = action
	var posture := current_firing_posture()
	var special:Dictionary={};var special_reserved:=false
	var continuing_showdown:=not showdown.is_empty()
	if continuing_showdown:
		step_showdown(delta,permitted and support_tracked and combat_actions_allowed() and not ability_ui.menu_open and not squad_input_captured and not dna_input_captured,posture)
		trigger=0.0
	if not continuing_showdown and not squad_input_captured and is_instance_valid(target_abilities) and selected>=0 and not weapons[selected].state.is_melee():
		target_abilities.refresh()
		var contact:bool=selected>=0 and two_hands and support_tracked and support_grip_down and not offhand_occupied and support_pose.origin.distance_to(support_point(selected) if int(weapons[selected].state.profile.hands)==2 else main_pose.origin)<.23
		var input:Dictionary={"trigger":trigger,"reserved":false,"ultimate":false} if str(active_profile().get("ability_loadout",{}).get("ultimate",""))=="volley_fire" else target_abilities.ultimate_input.sample(delta,trigger,support_trigger,contact,permitted and combat_actions_allowed() and not squad_input_captured and not dna_input_captured and not taunt_input_captured and not warcry_input_captured and not brawler_input_captured and not tka_input_captured and not swordsman_input_captured and not fencer_input_captured and not pikeman_input_captured and not pistoleer_input_captured and not carbineer_input_captured and not rifleman_input_captured and not bountyhunter_input_captured and not ability_ui.menu_open)
		trigger=float(input.trigger);special_reserved=bool(input.reserved)
		if input.ultimate and selected>=0:
			if str(active_profile().get("ability_loadout",{}).get("ultimate",""))=="overdrive":
				trigger=0.;special_reserved=true
				if commando_authority.is_valid() and bool(commando_authority.call("overdrive",muzzle_pose(selected),dominant)):action_haptic("fire")
			elif str(active_profile().get("ability_loadout",{}).get("ultimate",""))=="charge_blast":
				# Cone ultimates use the physical muzzle and need no acquired actor.
				trigger=0.;special_reserved=true
				if not pet_trigger_reserved(dominant) and not pet_trigger_reserved("left" if dominant=="right" else "right") and carbineer_authority.is_valid() and bool(carbineer_authority.call("charge_blast",muzzle_pose(selected),dominant)):action_haptic("fire")
			else:special=target_abilities.attack(muzzle_pose(selected),true)
			if not special.is_empty():
				trigger=1.0;special_reserved=false
				if special.get("ability_id","")=="showdown":showdown_target=target_abilities.ultimate_target
		elif selected>=0 and trigger>=.75 and not special_reserved:special=target_abilities.attack(muzzle_pose(selected))
		if special.get("ability_id","")=="flurry_shot":showdown_target=target_abilities.target
	if bountyhunter_armed_until>0 and selected>=0 and trigger>=.75 and not special_reserved:
		if Time.get_ticks_usec()<=bountyhunter_armed_until and str(weapons[selected].state.profile.get("item_id",""))==bountyhunter_arm_item:special={"ability_id":"underhand_shot"}
	for i in range(weapons.size()):
		var state = weapons[i].state
		var shot: Dictionary = state.sample_swing(delta,permitted and not squad_input_captured and not dna_input_captured and not taunt_input_captured and not warcry_input_captured and not brawler_input_captured and not tka_input_captured and not swordsman_input_captured and not fencer_input_captured and not pikeman_input_captured and not pistoleer_input_captured and not carbineer_input_captured and not rifleman_input_captured and not bountyhunter_input_captured and selected==i and combat_actions_allowed() and not ability_ui.menu_open,two_hands,posture,swing_position(main_pose.origin),is_finite(trigger) and trigger>=0.5) if state.is_melee() else state.tick(delta,0.0 if squad_input_captured or special.get("ability_id","") in ["showdown","flurry_shot"] else trigger,permitted and not dna_input_captured and not taunt_input_captured and not warcry_input_captured and not brawler_input_captured and not tka_input_captured and not swordsman_input_captured and not fencer_input_captured and not pikeman_input_captured and not pistoleer_input_captured and not carbineer_input_captured and not rifleman_input_captured and not bountyhunter_input_captured and selected==i and not continuing_showdown and combat_actions_allowed() and not ability_ui.menu_open,two_hands,posture)
		if selected==i and not state.is_melee() and special.get("ability_id","") in ["showdown","flurry_shot"]:
			shot=state.showdown_round(two_hands,posture,true)
		var melee_point:Vector3=melee_tip(i) if state.is_melee() else muzzle_pose(i).origin
		var previous_point:Vector3=melee_marker_previous.get("weapon",melee_point)
		if selected==i:melee_marker_previous["weapon"]=melee_point
		if state.is_melee() and selected==i and is_instance_valid(target_abilities):
			var melee_permitted:bool=permitted and trigger>=.5 and not brawler_input_captured and not tka_input_captured and not swordsman_input_captured and not fencer_input_captured and not pikeman_input_captured and not pistoleer_input_captured and not carbineer_input_captured and not rifleman_input_captured and not bountyhunter_input_captured and not warcry_input_captured and not taunt_input_captured and not squad_input_captured and not dna_input_captured
			target_abilities.sample_punch("weapon",main_pose.origin,delta,melee_permitted)
			shot=target_abilities.melee_swing(shot,previous_point,melee_point,"weapon",delta,melee_permitted)
		if not shot.is_empty():
			if special.get("ability_id","")=="underhand_shot":bountyhunter_armed_until=0;bountyhunter_arm_item=""
			if not special.is_empty() and not state.is_melee():shot.merge(special,true)
			var pose := muzzle_pose(i)
			if not dispatch_shot(shot,pose,weapons[i].visual.global_position,state.profile,state.is_melee()):continue
			if is_instance_valid(origin):
				var controller: XRController3D = origin.get_node("LeftHand" if dominant=="left" else "RightHand")
				controller.trigger_haptic_pulse("haptic",0,0.35,0.045,0)
	update_visuals()

func dispatch_shot(shot: Dictionary, pose: Transform3D, grip: Vector3, profile: Dictionary, melee: bool) -> bool:
	var immutable: Dictionary=shot.duplicate(true)
	immutable["item_id"]=str(profile.get("item_id",""))
	if not melee:
		immutable["local_ammo_spent"]=1
		immutable["delivery"]=str(profile.get("delivery","bolt"))
	if not melee and immutable.get("ability_id","") not in ["showdown","flurry_shot"] and immutable.get("aim_point") is Vector3:
		var direction:Vector3=immutable.aim_point-pose.origin
		if direction.length_squared()<.001:return false
		pose.basis=Basis.looking_at(direction.normalized())
	if is_instance_valid(squad_leader):immutable.merge(squad_leader.volley_intent(head.global_transform if melee else pose,float(shot.get("range",profile.get("core3",{}).get("maxRange",0))),str(immutable.get("target_id",""))))
	if not melee:
		pose=movement_spread.apply(pose,profile)
		immutable["movement_spread_degrees"]=movement_spread.degrees(profile)
	if shot_authority.is_valid():
		var authorized: Variant=shot_authority.call(immutable,head.global_transform if melee else pose,grip)
		if not authorized is Dictionary or authorized.is_empty():
			if not melee and (profile.get("native_family","")=="commando" or profile.get("delivery","") in ["scatter","guided_bolt"] or immutable.get("ability_id","") in ["double_tap","disarming_shot","showdown","crippling_shot","wild_shot","charge_shot","suppression_fire","lethal_shot","piercing_shot","flurry_shot","surprise_shot","sniper_shot","eye_shot","confusion_shot","fast_blast","underhand_shot","bleeding_shot"]) and selected>=0:weapons[selected].state.refund_rounds(1)
			return false
		immutable=authorized.duplicate(true)
	if not melee and immutable.get("ability_id","") in ["showdown","flurry_shot"] and int(immutable.get("volley_index",0))==0:
		showdown={"ability_id":str(immutable.ability_id),"item_id":str(immutable.item_id),"target_id":str(immutable.target_id),"volley_id":str(immutable.get("volley_id","")),"index":1,"wait":.25}
	if not melee and not str(immutable.get("ability_id","")).is_empty() and selected>=0:
		var state=weapons[selected].state
		state.next_shot=state.clock+float(immutable.get("ability",{}).get("interval_seconds",60.0/state.effective_rpm()))
	if immutable.get("native_direct",false):return true # Accepted receipt presents the cone/beam; no bolt or local damage.
	if not melee and profile.get("native_family","")=="commando" and not shot_authority.is_valid():immutable["cosmetic_only"]=true
	if not melee and profile.get("native_family","")=="commando" and str(profile.get("delivery","")) in ["cone","beam"]:
		rounds_sim.present_heavy(immutable,pose,grip,profile);return true
	if melee and shot_authority.is_valid():rounds_sim.play_melee_swing(immutable,pose)
	elif melee: rounds_sim.strike_melee(immutable,head.global_transform,pose)
	else: rounds_sim.spawn(immutable,pose,grip)
	return true

func commando_feedback(receipt:Dictionary)->void:
	if not is_instance_valid(rounds_sim) or not receipt.get("heavy_pose") is Transform3D or not receipt.get("heavy_grip") is Vector3:return
	rounds_sim.present_heavy(receipt,receipt.heavy_pose,receipt.heavy_grip,receipt.get("heavy_profile",{}))

func cancel_showdown()->void:
	showdown.clear();showdown_target=null

func fan_shot_feedback(receipt:Dictionary)->void:
	if not receipt.get("fan_pose") is Transform3D or not receipt.get("fan_grip") is Vector3 or not is_instance_valid(rounds_sim):return
	var shot:Dictionary=receipt.get("fan_profile",{}).duplicate(true)
	if shot.is_empty():return
	shot["cosmetic_only"]=true;shot.range=minf(12,float(shot.range))
	for angle:float in [-20.,0.,20.]:
		var pose:Transform3D=receipt.fan_pose
		pose.basis=pose.basis*Basis(Vector3.UP,deg_to_rad(angle))
		rounds_sim.spawn(shot,pose,receipt.fan_grip)

func step_showdown(delta:float,permitted:bool,posture:String)->void:
	if showdown.is_empty():return
	if not permitted or not is_finite(delta) or delta<=0 or delta>.1 or selected<0 or not target_abilities.actor_eligible(showdown_target) or str(weapons[selected].state.profile.get("item_id",""))!=str(showdown.item_id) or not volley_equipped(str(showdown.get("ability_id","showdown"))):cancel_showdown();return
	showdown.wait=float(showdown.wait)-delta
	if float(showdown.wait)>0:return
	if showdown_gate.is_valid():
		var status:=str(showdown_gate.call(str(showdown.volley_id)))
		if status=="invalid":cancel_showdown();return
		if status=="pending":return
	var state=weapons[selected].state
	var shot:Dictionary=state.showdown_round(two_hands,posture,false)
	if shot.is_empty():cancel_showdown();return
	shot.merge({"ability_id":str(showdown.get("ability_id","showdown")),"target_id":str(showdown.target_id),"volley_id":str(showdown.volley_id),"volley_index":int(showdown.index)})
	if not dispatch_shot(shot,muzzle_pose(selected),weapons[selected].visual.global_position,state.profile,false):
		cancel_showdown();return
	showdown.index=int(showdown.index)+1;showdown.wait=.25
	action_haptic("fire")
	if int(showdown.index)>=3:cancel_showdown()

func volley_equipped(id:String)->bool:
	for ability:Dictionary in active_profile().get("abilities",[]):
		if str(ability.get("id",""))==id:return preload("res://combat/loadout.gd").equipped(ability,active_profile().get("ability_loadout",{}))
	return false

func clear_bountyhunter()->void:
	bountyhunter_gestures.clear();bountyhunter_input_captured=false;bountyhunter_armed_until=0;bountyhunter_arm_item="";bountyhunter_arm_pending="";bountyhunter_arm_pending_shot="";bountyhunter_arm_pending_until=0

func configure_bountyhunter(context:Dictionary,callback:Callable,item_id:String,epoch:String)->void:
	var grants:Array=[]
	for id:String in context:
		if context[id] is Dictionary and context[id].get("learned",false):grants.append(id)
	grants.sort()
	var key:=JSON.stringify([epoch,item_id,grants,dominant])
	if key!=bountyhunter_key:clear_bountyhunter();bountyhunter_key=key
	bountyhunter_context=context.duplicate(true);bountyhunter_authority=callback

func bountyhunter_feedback(receipt:Dictionary)->void:
	if receipt.get("ability_id","")=="underhand_shot" and receipt.get("armed",false) and selected>=0 and not bountyhunter_arm_pending.is_empty() and str(receipt.get("shot_id",""))==bountyhunter_arm_pending_shot and Time.get_ticks_usec()<=bountyhunter_arm_pending_until and bountyhunter_arm_pending==str(weapons[selected].state.profile.get("item_id","")):
		bountyhunter_armed_until=Time.get_ticks_usec()+int(clampf(float(receipt.get("armed_remaining_seconds",1.5)),0,1.5)*1000000)
		bountyhunter_arm_item=str(weapons[selected].state.profile.get("item_id",""))
	bountyhunter_arm_pending="";bountyhunter_arm_pending_shot="";bountyhunter_arm_pending_until=0

func sample_bountyhunter_gestures(delta:float,head_tracked:bool)->void:
	bountyhunter_input_captured=false
	var permitted:bool=allowed and head_tracked and selected>=0 and bountyhunter_authority.is_valid() and combat_actions_allowed() and inventory_allows_combat() and showdown.is_empty() and not squad_input_captured and not dna_input_captured and not ability_ui.menu_open and not (is_instance_valid(datapad) and datapad.is_open) and not offhand_occupied
	if not permitted or not is_instance_valid(origin):clear_bountyhunter();return
	var state=weapons[selected].state
	var family:=str(state.profile.get("class",""))
	var compatible:bool=family in ["holdout","pistol","heavy_pistol","carbine","burst_carbine"] or str(state.profile.get("id",""))=="rifle_lightning"
	if not compatible or state.is_melee() or not state.certified() or state.reload_until>=0 or state.condition_max<2 or state.condition_damage>=state.condition_max:clear_bountyhunter();return
	var main:XRController3D=origin.get_node(dominant.capitalize()+"Hand")
	var offhand:="left" if dominant=="right" else "right"
	var support:XRController3D=origin.get_node(offhand.capitalize()+"Hand")
	if not HandInput.controller_tracked(main) or not HandInput.controller_tracked(support) or main.get_float("grip")<.65 or vehicle_hand_busy(dominant) or vehicle_hand_busy(offhand) or pet_trigger_reserved(dominant) or pet_trigger_reserved(offhand):clear_bountyhunter();return
	if not bountyhunter_arm_pending.is_empty():
		if Time.get_ticks_usec()>bountyhunter_arm_pending_until or support.get_float("grip")<.65 or not support_latched or main.get_float("trigger")>=.2 or support.get_float("trigger")>=.2:clear_bountyhunter()
		bountyhunter_input_captured=true;return
	if bountyhunter_armed_until>0:
		if Time.get_ticks_usec()>bountyhunter_armed_until or support.get_float("trigger")>=.2 or support.get_float("grip")<.65 or not support_latched or str(state.profile.get("item_id",""))!=bountyhunter_arm_item:clear_bountyhunter()
		return
	var available:Array=[]
	for id:String in ["duelist_stance","underhand_shot"]:
		var row:Dictionary=bountyhunter_context.get(id,{})
		if row.get("learned",false) and row.get("conditions_met",false) and not row.get("active",false) and float(row.get("cooldown_remaining_seconds",0))<=0 and float(abilities.cooldowns.get(id,0))<=0 and (id!="underhand_shot" or family in ["carbine","burst_carbine"]):available.append(id)
	var forward:Vector3=-head.global_basis.z;forward.y=0
	if forward.length_squared()<.1:clear_bountyhunter();return
	var frame:=Transform3D(Basis(Vector3.UP,atan2(-forward.x,-forward.z)),head.global_position)
	var gun:=controller_weapon_pose(main)
	var id:String=bountyhunter_gestures.sample(delta,frame.affine_inverse()*gun,frame.affine_inverse()*support.global_transform,origin.global_transform.affine_inverse()*head.global_position,main.get_float("trigger"),support.get_float("trigger"),main.get_float("grip"),support.get_float("grip"),support_latched,true,available)
	bountyhunter_input_captured=bountyhunter_gestures.capturing
	if bountyhunter_input_captured:physical_guard.clear()
	if not id.is_empty():
		pose_weapon(gun,support.global_transform)
		if bool(bountyhunter_authority.call(id,muzzle_pose(selected),dominant)):action_haptic("fire")

func configure_rifleman(context:Dictionary,callback:Callable,item_id:String)->void:
	var key:=JSON.stringify([item_id,context.get("rifleman_focus",{}).get("learned",false)])
	if key!=rifleman_key:rifleman_gestures.clear();rifleman_key=key;cancel_showdown()
	rifleman_context=context.duplicate(true);rifleman_authority=callback

func sample_squad_controls(delta:float,main:float,support:float,tracked:bool,support_tracked:bool)->void:
	squad_input_captured=false
	if not is_instance_valid(squad_leader):return
	if not tracked or not allowed or not combat_actions_allowed() or not inventory_allows_combat():
		squad_leader.close();squad_leader.ultimate_input.reset();return
	if squad_leader.sample(main):squad_input_captured=true;squad_release_pending=true;return
	if squad_release_pending:
		squad_input_captured=true
		if main<.25:squad_release_pending=false
		return
	if str(active_profile().get("ability_loadout",{}).get("ultimate",""))!="volley_fire":squad_leader.ultimate_input.reset();return
	# This command uses the same deliberate two-trigger chord for every weapon.
	# It consumes no ammunition and does not require a melee swing or support grip.
	var result:Dictionary=squad_leader.ultimate_input.sample(delta,main,support,support_tracked,squad_leader.permitted() and not dna_input_captured and not offhand_occupied)
	squad_input_captured=bool(result.reserved)
	if result.ultimate and squad_leader.ultimate(squad_leader.aim()):action_haptic("fire")

func sample_rifleman_gestures(delta:float,head_tracked:bool)->void:
	rifleman_input_captured=false
	var row:Dictionary=rifleman_context.get("rifleman_focus",{})
	var permitted:bool=allowed and head_tracked and selected>=0 and rifleman_authority.is_valid() and combat_actions_allowed() and inventory_allows_combat() and showdown.is_empty() and not squad_input_captured and not bountyhunter_input_captured and not dna_input_captured and not ability_ui.menu_open and not (is_instance_valid(datapad) and datapad.is_open) and not offhand_occupied and row.get("learned",false) and row.get("conditions_met",false) and not row.get("active",false) and float(row.get("cooldown_remaining_seconds",0))<=0 and float(abilities.cooldowns.get("rifleman_focus",0))<=0
	if not permitted or not is_instance_valid(origin):rifleman_gestures.clear();return
	var state=weapons[selected].state
	if state.is_melee() or not state.certified() or str(state.profile.get("class","")) not in ["rifle","marksman","repeater","bowcaster","slugthrower"] or state.reload_until>=0 or state.condition_max<2 or state.condition_damage>=state.condition_max:rifleman_gestures.clear();return
	var main:XRController3D=origin.get_node(dominant.capitalize()+"Hand")
	var offhand:="left" if dominant=="right" else "right"
	var support:XRController3D=origin.get_node(offhand.capitalize()+"Hand")
	if not HandInput.controller_tracked(main) or not HandInput.controller_tracked(support) or vehicle_hand_busy(dominant) or vehicle_hand_busy(offhand) or pet_trigger_reserved(dominant) or pet_trigger_reserved(offhand):rifleman_gestures.clear();return
	var frame:=origin.global_transform.affine_inverse()
	var id:String=rifleman_gestures.sample(delta,frame*controller_weapon_pose(main),frame*support.global_transform,frame*head.global_transform,dominant,main.get_float("trigger"),support.get_float("trigger"),main.get_float("grip"),support.get_float("grip"),support_latched,permitted)
	rifleman_input_captured=rifleman_gestures.capturing
	if rifleman_input_captured:physical_guard.clear()
	if not id.is_empty():
		if is_instance_valid(target_abilities):target_abilities.close()
		if bool(rifleman_authority.call(id,muzzle_pose(selected),dominant)):action_haptic("fire")

func configure_carbineer(context:Dictionary,callback:Callable,item_id:String)->void:
	var learned:Array=[]
	for id:String in context:
		if context[id].get("learned",false):learned.append(id)
	learned.sort()
	var key:=JSON.stringify([item_id,learned])
	if key!=carbineer_key:carbineer_gestures.clear();carbineer_key=key
	carbineer_context=context.duplicate(true);carbineer_authority=callback

func sample_carbineer_gestures(delta:float,head_tracked:bool)->void:
	carbineer_input_captured=false
	var permitted:bool=allowed and head_tracked and selected>=0 and carbineer_authority.is_valid() and combat_actions_allowed() and inventory_allows_combat() and not squad_input_captured and not bountyhunter_input_captured and not dna_input_captured and not ability_ui.menu_open and not (is_instance_valid(datapad) and datapad.is_open) and not offhand_occupied and support_latched
	if not permitted or not is_instance_valid(origin):carbineer_gestures.clear();return
	var state=weapons[selected].state
	if state.is_melee() or not state.certified() or str(state.profile.get("class","")) not in ["carbine","burst_carbine"]:carbineer_gestures.clear();return
	var main:XRController3D=origin.get_node(dominant.capitalize()+"Hand")
	var offhand:="left" if dominant=="right" else "right"
	var support:XRController3D=origin.get_node(offhand.capitalize()+"Hand")
	if not HandInput.controller_tracked(main) or not HandInput.controller_tracked(support) or main.get_float("grip")<.65 or support.get_float("grip")<.65 or vehicle_hand_busy(dominant) or vehicle_hand_busy(offhand) or pet_trigger_reserved(dominant) or pet_trigger_reserved(offhand):carbineer_gestures.clear();return
	var forward:Vector3=-head.global_basis.z;forward.y=0
	if forward.length_squared()<.1:carbineer_gestures.clear();return
	var frame:=Transform3D(Basis(Vector3.UP,atan2(-forward.x,-forward.z)),head.global_position)
	var gun:=controller_weapon_pose(main)
	var evidence:=Transform3D(origin.global_basis.inverse()*gun.basis,origin.global_basis.inverse()*(gun.origin-head.global_position))
	var support_evidence:Vector3=origin.global_basis.inverse()*(support.global_position-head.global_position)
	var available:Array=[]
	for id:String in ["full_auto_sweep","tactical_brace"]:
		var row:Dictionary=carbineer_context.get(id,{})
		if row.get("learned",false) and row.get("conditions_met",false) and not row.get("active",false) and float(row.get("cooldown_remaining_seconds",0))<=0 and float(abilities.cooldowns.get(id,0))<=0:available.append(id)
	var id:String=carbineer_gestures.sample(delta,frame.affine_inverse()*gun,frame.affine_inverse()*support.global_transform,evidence,support_evidence,main.get_float("trigger"),support.get_float("trigger"),permitted,available)
	carbineer_input_captured=carbineer_gestures.capturing
	if carbineer_input_captured:physical_guard.clear()
	if not id.is_empty():
		pose_weapon(gun,support.global_transform)
		if bool(carbineer_authority.call(id,muzzle_pose(selected),dominant)):action_haptic("fire")

func carbineer_feedback(receipt:Dictionary)->void:
	if receipt.get("ability_id","")=="tactical_brace":return
	if not receipt.get("area_pose") is Transform3D or not receipt.get("area_grip") is Vector3 or not is_instance_valid(rounds_sim):return
	var shot:Dictionary=receipt.get("area_profile",{}).duplicate(true)
	if shot.is_empty():return
	shot["cosmetic_only"]=true;shot.range=minf(20 if receipt.get("ability_id","")=="charge_blast" else 18,float(shot.range))
	for angle:float in [-25.,0.,25.]:
		var pose:Transform3D=receipt.area_pose
		pose.basis=pose.basis*Basis(Vector3.UP,deg_to_rad(angle))
		rounds_sim.spawn(shot,pose,receipt.area_grip)

func configure_pistoleer(context:Dictionary,callback:Callable,item_id:String)->void:
	var learned:Array=[]
	for id:String in context:
		if context[id].get("learned",false):learned.append(id)
	learned.sort()
	var key:=JSON.stringify([item_id,learned])
	if key!=pistoleer_key:pistoleer_gestures.clear();pistoleer_key=key;cancel_showdown()
	pistoleer_context=context.duplicate(true);pistoleer_authority=callback

func sample_pistoleer_gestures(delta:float,head_tracked:bool)->void:
	pistoleer_input_captured=false
	var permitted:bool=allowed and head_tracked and selected>=0 and pistoleer_authority.is_valid() and combat_actions_allowed() and inventory_allows_combat() and not squad_input_captured and not bountyhunter_input_captured and not dna_input_captured and showdown.is_empty() and not ability_ui.menu_open and not (is_instance_valid(datapad) and datapad.is_open) and not offhand_occupied and not support_latched
	if not permitted or not is_instance_valid(origin):pistoleer_gestures.clear();return
	var state=weapons[selected].state
	if state.is_melee() or not state.certified() or str(state.profile.get("class","")) not in ["holdout","pistol","heavy_pistol"]:pistoleer_gestures.clear();return
	var main:XRController3D=origin.get_node(dominant.capitalize()+"Hand")
	var offhand:="left" if dominant=="right" else "right"
	var support:XRController3D=origin.get_node(offhand.capitalize()+"Hand")
	if not HandInput.controller_tracked(main) or not HandInput.controller_tracked(support) or main.get_float("grip")<.65 or vehicle_hand_busy(dominant) or vehicle_hand_busy(offhand) or pet_trigger_reserved(offhand):pistoleer_gestures.clear();return
	var forward:Vector3=-head.global_basis.z;forward.y=0
	if forward.length_squared()<.1:pistoleer_gestures.clear();return
	var body_frame:=Transform3D(Basis(Vector3.UP,atan2(-forward.x,-forward.z)),head.global_position)
	var pistol_pose:=controller_weapon_pose(main)
	var available:Array=[]
	for id:String in pistoleer_context:
		var row:Dictionary=pistoleer_context[id]
		if row.get("learned",false) and row.get("conditions_met",false) and not row.get("active",false) and float(row.get("cooldown_remaining_seconds",0))<=0 and float(abilities.cooldowns.get(id,0))<=0:available.append(id)
	var id:String=pistoleer_gestures.sample(delta,body_frame.affine_inverse()*pistol_pose,body_frame.affine_inverse()*support.global_transform,dominant,main.get_float("trigger"),support.get_float("trigger"),support.get_float("grip"),permitted,available)
	pistoleer_input_captured=pistoleer_gestures.capturing
	if pistoleer_input_captured:physical_guard.clear()
	if not id.is_empty():
		# Current tracking pose supplies the muzzle, never yesterday's render pose.
		pose_weapon(pistol_pose,support.global_transform)
		if bool(pistoleer_authority.call(id,muzzle_pose(selected),dominant)):action_haptic("fire")

func swing_position(hand_position: Vector3) -> Vector3:
	# Cancel virtual locomotion/snap turning and whole-body translation. Only
	# tracked hand movement relative to head translation contributes distance.
	var relative := hand_position-head.global_position
	return origin.global_basis.inverse()*relative if is_instance_valid(origin) else relative

func update_visuals() -> void:
	update_hand_targets()
	update_unarmed_gloves()
	if is_instance_valid(ability_ui) and is_instance_valid(head):
		var profile := active_profile()
		abilities.reconcile(profile)
		var point: Vector3 = weapons[selected].visual.global_position if selected >= 0 else head.global_position - head.global_basis.z * 0.35 - Vector3.UP * 0.2
		var badge_tracked := true
		if is_instance_valid(origin):
			var hand: XRController3D = origin.get_node("LeftHand" if dominant == "left" else "RightHand")
			badge_tracked = HandInput.controller_tracked(hand)
			if selected < 0 and badge_tracked: point = hand.global_position
		# Never substitute a head-locked icon when a tracked hand disappears.
		ability_ui.update_badge(abilities.definition(profile), abilities.primed, float(abilities.cooldowns.get(abilities.selected, 0)), point + Vector3.UP * 0.23, allowed and inventory_allows_combat() and badge_tracked, abilities.reason)
	if reticle != null:
		var aim := Transform3D.IDENTITY
		if selected>=0: aim = head.global_transform if weapons[selected].state.is_melee() else muzzle_pose(selected)
		var fist_aim := unarmed_engaged("left") or unarmed_engaged("right")
		var melee_aim: bool = fist_aim or (selected>=0 and weapons[selected].state.is_melee())
		if melee_aim or taunt_input_captured: reticle.update_head_aim(head,allowed)
		else: reticle.update_aim(aim,allowed and selected>=0)
	for i in range(weapons.size()):
		var weapon := weapons[i]
		if i != selected: weapon.visual.global_transform = visual_stow_transform(i)
		var reserved := inventory_reserved_ids.has(str(weapon.state.profile.get("item_id","")))
		weapon.visual.visible = allowed and inventory_allows_combat() and (i==selected or (not reserved and not weapon.get("inventory_only",false)))
		var state = weapon.state
		weapon.label.visible = i == selected
		if state.is_melee():
			weapon.label.text = "Power %.0f · Recovery %.0f%s" % [state.melee_thresholds(two_hands).power,state.effective_recovery()," · combat ready" if state.swing_feedback.get("engaged",false) else " · at peace"]
		else:
			if state.profile.get("charge_limited",false):weapon.label.text="%d charges · %s · %.0f RPM"%[state.rounds,state.mode,state.effective_rpm()]
			else:weapon.label.text = "%d/%d · %s · %.0f RPM%s" % [state.rounds,int(state.profile.capacity),state.mode,state.effective_rpm()," · cooling" if state.reload_until>=0 else ""]
			if state.profile.get("native_family","")=="commando" and not shot_authority.is_valid():weapon.label.text+=" · Effects preview · Connect for combat"
			if str(state.profile.get("class","")) in ["holdout","pistol","heavy_pistol"]:
				weapon.label.text+=" · no movement penalty"
				if pistoleer_context.get("run_and_gun",{}).get("active",false):weapon.label.text+=" · Run and Gun"
			if str(state.profile.get("class","")) in ["rifle","marksman","repeater","bowcaster","slugthrower"] and rifleman_context.get("rifleman_focus",{}).get("active",false):weapon.label.text+=" · Rifleman’s Focus"
			if str(state.profile.get("class","")) in ["carbine","burst_carbine"] and carbineer_context.get("tactical_brace",{}).get("active",false):weapon.label.text+=" · Tactical Brace"
			if bountyhunter_context.get("duelist_stance",{}).get("active",false):weapon.label.text+=" · Duelist’s Stance"
			if bountyhunter_armed_until>Time.get_ticks_usec():weapon.label.text+=" · Underhand ready"

func inventory_allows_combat() -> bool:
	if interaction_blocker.is_valid() and bool(interaction_blocker.call()): return false
	return not is_instance_valid(inventory) or not inventory.blocks_combat()

func set_inventory_reserved(ids: Array) -> void:
	inventory_reserved_ids.clear()
	for id in ids: inventory_reserved_ids[str(id)] = true

func begin_inventory_item(profile: Dictionary) -> bool:
	# Only a freshly owner-verified real item may enter the existing combat path.
	var id := str(profile.get("item_id",""))
	if id.is_empty() or profile.get("source_kind","")!="core3_weapon_instance": return false
	var index := -1
	for i in range(weapons.size()):
		if str(weapons[i].state.profile.get("item_id",""))==id:
			if not weapons[i].state.refresh_instance(profile): return false
			index = i
			break
	if index<0:
		if not assets.catalog.get("weapons",{}).has(str(profile.get("id",""))): return false
		var state := WeaponState.new()
		state.ability_state = null if shot_authority.is_valid() else abilities
		if shot_authority.is_valid():state.wear_per_shot=0.0
		var certificates: Array = profile.core3.certificationsRequired if profile.get("certified",false) else []
		if not state.configure(profile,certificates,profile.get("condition",{})): return false
		var visual := make_visual(profile)
		if not is_instance_valid(visual): return false
		visual.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF
		add_child(visual)
		var label := Label3D.new(); label.font = preload("res://resources/fonts/Jupiteroid-Regular.ttf")
		label.font_size=20; label.pixel_size=0.00035; label.position=Vector3(0,0.14,0)
		label.modulate=Color(0.59,0.96,0.99,0.55); label.outline_size=1; label.billboard=BaseMaterial3D.BILLBOARD_ENABLED
		visual.add_child(label)
		weapons.append({"state":state,"visual":visual,"label":label,"bounds":visual_bounds(visual),"inventory_only":true})
		index=weapons.size()-1
	draw(index)
	inventory_item_id=id
	return true

func stop_inventory_item() -> void:
	if not inventory_item_id.is_empty(): stow()

func set_equipped_inventory_weapons(profiles: Array) -> void:
	# Current Core3 equipment alone supplies normal holsters. Cached inventory
	# appearances remain reusable, but cannot fire or appear as duplicate gear.
	stow()
	for weapon in weapons:
		if weapon.state.profile.get("source_kind","")=="core3_weapon_instance": weapon["inventory_only"]=true
	for profile: Dictionary in profiles:
		if begin_inventory_item(profile): weapons[selected]["inventory_only"]=false
	stow()
	update_visuals()

func controller_weapon_pose(controller: XRController3D) -> Transform3D:
	# A controller's grip -Z is not its firing direction. Preserve the physical
	# grip position for the handle, but use OpenXR's runtime-supplied aim basis.
	var pose := controller.global_transform
	var tracker = XRServer.get_tracker(controller.tracker)
	var aim: XRPose = tracker.get_pose("aim") if tracker != null else null
	if aim != null and aim.has_tracking_data:
		pose.basis = (origin.global_transform * aim.get_adjusted_transform()).basis.orthonormalized()
	else:
		# Runtime-neutral XR Tools fallback for controllers lacking aim tracking.
		pose.basis = (pose.basis * XRTools.get_palm_offset(XRTools.HandOffsetMode.HAND_OFFSET_AUTO,controller).basis).orthonormalized()
	return pose

func _process(_delta: float) -> void:
	refresh_render_pose()

func refresh_render_pose() -> void:
	# Gather current tracking before avatar IK (priority100). That solver owns
	# final visible hand+weapon presentation; no later gun-only pose overwrite.

	if not is_instance_valid(origin): return
	var main: XRController3D = origin.get_node("LeftHand" if dominant=="left" else "RightHand")
	var support: XRController3D = origin.get_node("RightHand" if dominant=="left" else "LeftHand")
	if not HandInput.controller_tracked(main): return
	pose_weapon(controller_weapon_pose(main),support.global_transform)
	update_visuals()
	if is_instance_valid(target_abilities):target_abilities.refresh()
	if is_instance_valid(squad_leader):squad_leader.refresh()


func configure_pikeman(context:Dictionary,callback:Callable,item_id:String,ultimate_id:String)->void:
	var learned:Array=[]
	for id:String in context:
		if context[id].get("learned",false):learned.append(id)
	learned.sort()
	var key:=JSON.stringify([item_id,learned,ultimate_id])
	if key!=pikeman_key:pikeman_gestures.clear();pikeman_key=key
	pikeman_context=context.duplicate(true);pikeman_authority=callback;pikeman_ultimate=ultimate_id

func sample_pikeman_gestures(delta:float,head_tracked:bool)->void:
	pikeman_input_captured=false
	var permitted:bool=allowed and head_tracked and selected>=0 and pikeman_authority.is_valid() and combat_actions_allowed() and inventory_allows_combat() and not squad_input_captured and not bountyhunter_input_captured and not dna_input_captured and not ability_ui.menu_open and not (is_instance_valid(datapad) and datapad.is_open)
	if not permitted or not is_instance_valid(origin):pikeman_gestures.clear();return
	var entry:Dictionary=weapons[selected]
	if not entry.state.is_melee() or str(entry.state.profile.get("class",""))!="melee_polearm" or not pikeman_context.values().any(func(row):return row.get("learned",false)):pikeman_gestures.clear();return
	var main:XRController3D=origin.get_node("LeftHand" if dominant=="left" else "RightHand")
	var support:XRController3D=origin.get_node("RightHand" if dominant=="left" else "LeftHand")
	var tracked:bool=HandInput.controller_tracked(main) and main.get_float("grip")>.65 and not vehicle_hand_busy(dominant) and not pet_trigger_reserved(dominant)
	var contact:bool=two_hands and HandInput.controller_tracked(support) and support.get_float("grip")>.65 and support.global_position.distance_to(support_point(selected))<.23 and not offhand_occupied and not vehicle_hand_busy("left" if dominant=="right" else "right")
	var available:Array=[]
	for id:String in pikeman_context:
		var row:Dictionary=pikeman_context[id]
		if row.get("learned",false) and row.get("conditions_met",false) and float(row.get("cooldown_remaining_seconds",0))<=0 and float(abilities.cooldowns.get(id,0))<=0:available.append(id)
	var forward:Vector3=origin.global_basis.inverse()*-head.global_basis.z
	forward.y=0
	if forward.length_squared()<.1:pikeman_gestures.clear();return
	if not pikeman_gestures.previous.is_finite():pikeman_basis=Basis(Vector3.UP,atan2(-forward.x,-forward.z))
	var basis:Basis=origin.global_basis*pikeman_basis
	var p:Vector3=basis.inverse()*((main.global_position+support.global_position)*.5-head.global_position)
	var id:String=pikeman_gestures.sample(delta,p,origin.to_local(head.global_position),main.get_float("trigger"),support.get_float("trigger") if HandInput.controller_tracked(support) else 0.0,tracked and contact,pikeman_ultimate=="whirlwind",available)
	pikeman_input_captured=pikeman_gestures.capturing
	if pikeman_input_captured:physical_guard.clear();overhead_warcry.clear();warcry_input_captured=false
	if not id.is_empty():pikeman_authority.call(id,head.global_transform,dominant)

func configure_fencer(context:Dictionary,callback:Callable,item_id:String,ultimate_id:String)->void:
	var learned:Array=[]
	for id:String in context:
		if context[id].get("learned",false):learned.append(id)
	learned.sort()
	var key:=JSON.stringify([item_id,learned,ultimate_id])
	if key!=fencer_key:fencer_gestures.clear();fencer_key=key
	fencer_context=context.duplicate(true);fencer_authority=callback;fencer_ultimate=ultimate_id

func sample_fencer_gestures(delta:float,head_tracked:bool)->void:
	fencer_input_captured=false
	var permitted:bool=allowed and head_tracked and selected>=0 and fencer_authority.is_valid() and combat_actions_allowed() and inventory_allows_combat() and not squad_input_captured and not bountyhunter_input_captured and not dna_input_captured and not ability_ui.menu_open and not (is_instance_valid(datapad) and datapad.is_open)
	if not permitted or not is_instance_valid(origin):fencer_gestures.clear();return
	var entry:Dictionary=weapons[selected]
	if not entry.state.is_melee() or int(entry.state.profile.get("hands",0))!=1 or not fencer_context.values().any(func(row):return row.get("learned",false)):fencer_gestures.clear();return
	var main:XRController3D=origin.get_node("LeftHand" if dominant=="left" else "RightHand")
	var support:XRController3D=origin.get_node("RightHand" if dominant=="left" else "LeftHand")
	var tracked:bool=HandInput.controller_tracked(main) and main.get_float("grip")>.65 and not vehicle_hand_busy(dominant) and not pet_trigger_reserved(dominant)
	var contact:bool=two_hands and HandInput.controller_tracked(support) and support.get_float("grip")>.65 and support.global_position.distance_to(main.global_position)<.23 and not offhand_occupied and not vehicle_hand_busy("left" if dominant=="right" else "right")
	var available:Array=[]
	for id:String in fencer_context:
		var row:Dictionary=fencer_context[id]
		if row.get("learned",false) and row.get("conditions_met",false) and float(row.get("cooldown_remaining_seconds",0))<=0 and float(abilities.cooldowns.get(id,0))<=0:available.append(id)
	var forward:Vector3=origin.global_basis.inverse()*-head.global_basis.z
	forward.y=0
	if forward.length_squared()<.1:fencer_gestures.clear();return
	if not fencer_gestures.previous.is_finite():fencer_basis=Basis(Vector3.UP,atan2(-forward.x,-forward.z))
	var basis:Basis=origin.global_basis*fencer_basis
	var p:Vector3=basis.inverse()*(main.global_position-head.global_position)
	var axis:Vector3=(basis.inverse()*entry.visual.global_basis[entry.bounds.size.max_axis_index()]).normalized()
	var id:String=fencer_gestures.sample(delta,p,origin.to_local(head.global_position),axis,main.get_float("trigger"),support.get_float("trigger") if HandInput.controller_tracked(support) else 0.0,tracked,contact,fencer_ultimate=="flawless_assault",available)
	fencer_input_captured=fencer_gestures.capturing
	if fencer_input_captured:physical_guard.clear();overhead_warcry.clear();warcry_input_captured=false
	if not id.is_empty():fencer_authority.call(id,head.global_transform,dominant)

func configure_swordsman(context:Dictionary,callback:Callable,item_id:String,ultimate_id:String)->void:
	var learned:Array=[]
	for id:String in context:
		if context[id].get("learned",false):learned.append(id)
	learned.sort()
	var key:=JSON.stringify([item_id,learned,ultimate_id])
	if key!=swordsman_key:swordsman_gestures.clear();swordsman_key=key
	swordsman_context=context.duplicate(true);swordsman_authority=callback;swordsman_ultimate=ultimate_id

func sample_swordsman_gestures(delta:float,head_tracked:bool)->void:
	swordsman_input_captured=false
	var permitted:bool=allowed and head_tracked and selected>=0 and swordsman_authority.is_valid() and combat_actions_allowed() and inventory_allows_combat() and not squad_input_captured and not dna_input_captured and not offhand_occupied and not ability_ui.menu_open and not (is_instance_valid(datapad) and datapad.is_open)
	if not permitted or not is_instance_valid(origin):swordsman_gestures.clear();return
	var state=weapons[selected].state
	if not state.is_melee() or int(state.profile.get("hands",0))!=2 or str(state.profile.get("class",""))=="melee_polearm" or not swordsman_context.values().any(func(row):return row.get("learned",false)):swordsman_gestures.clear();return
	var main:XRController3D=origin.get_node("LeftHand" if dominant=="left" else "RightHand")
	var support:XRController3D=origin.get_node("RightHand" if dominant=="left" else "LeftHand")
	var contact:bool=two_hands and HandInput.controller_tracked(main) and HandInput.controller_tracked(support) and main.get_float("grip")>.65 and support.get_float("grip")>.65 and support.global_position.distance_to(support_point(selected))<.23 and not vehicle_hand_busy(dominant) and not vehicle_hand_busy("left" if dominant=="right" else "right")
	var available:Array=[]
	for id:String in swordsman_context:
		var row:Dictionary=swordsman_context[id]
		if row.get("learned",false) and row.get("conditions_met",false) and float(row.get("cooldown_remaining_seconds",0))<=0 and float(abilities.cooldowns.get(id,0))<=0:available.append(id)
	# Origin-local displacement cancels virtual translation/rotation; no live HMD yaw rotation.
	var p:Vector3=origin.global_basis.inverse()*(main.global_position-head.global_position)
	var head_local:Vector3=origin.to_local(head.global_position)
	var id:String=swordsman_gestures.sample(delta,p,head_local,main.get_float("trigger"),support.get_float("trigger"),contact,available,swordsman_ultimate=="armour_break")
	if not id.is_empty():
		var target_id:=""
		if id=="armour_break":
			var special:Dictionary=target_abilities.attack(head.global_transform,true)
			if special.get("ability_id","")!=id:id=""
			else:target_id=str(special.target_id)
		if not id.is_empty():swordsman_authority.call(id,head.global_transform,dominant,target_id)
	swordsman_input_captured=swordsman_gestures.capturing
	if swordsman_input_captured:physical_guard.clear();overhead_warcry.clear();warcry_input_captured=false

func configure_tka(context:Dictionary,callback:Callable,item_id:String,ultimate_id:String)->void:
	var learned:Array=[]
	for id:String in context:
		if context[id].get("learned",false):learned.append(id)
	learned.sort()
	var key:=JSON.stringify([item_id,learned,ultimate_id])
	if key!=tka_key:tka_gestures.clear();tka_key=key
	tka_context=context.duplicate(true);tka_authority=callback;tka_ultimate=ultimate_id

func sample_tka_gestures(delta:float,head_tracked:bool)->void:
	tka_input_captured=false
	var permitted:bool=tka_context.values().any(func(row):return row.get("learned",false)) and allowed and head_tracked and selected<0 and unarmed.has(dominant) and tka_authority.is_valid() and combat_actions_allowed() and inventory_allows_combat() and not squad_input_captured and not bountyhunter_input_captured and not dna_input_captured and not ability_ui.menu_open and not (is_instance_valid(datapad) and datapad.is_open)
	if not permitted or not is_instance_valid(origin):tka_gestures.clear();return
	var forward:Vector3=origin.global_basis.inverse()*(-head.global_basis.z);forward.y=0
	if forward.length_squared()<.1:tka_gestures.clear();return
	if tka_gestures.previous.is_empty():tka_basis=Basis(Vector3.UP,atan2(-forward.x,-forward.z))
	var basis:Basis=origin.global_basis*tka_basis
	var hands:Dictionary={};var available:Array=[]
	for id:String in tka_context:
		var row:Dictionary=tka_context[id]
		if row.get("learned",false) and row.get("conditions_met",false) and float(row.get("cooldown_remaining_seconds",0))<=0:available.append(id)
	for side:String in ["left","right"]:
		var hand:XRController3D=origin.get_node(side.capitalize()+"Hand")
		hands[side]={"position":basis.inverse()*(hand.global_position-head.global_position),"grip":hand.get_float("grip"),"trigger":hand.get_float("trigger"),"tracked":HandInput.controller_tracked(hand),"free":not offhand_occupied and not vehicle_hand_busy(side) and not pet_trigger_reserved(side)}
	var id:String=tka_gestures.sample(delta,hands,permitted,available,tka_ultimate=="indomitable_focus")
	tka_input_captured=tka_gestures.capturing
	if tka_input_captured:physical_guard.clear()
	if not id.is_empty():tka_authority.call(id,Transform3D(basis,head.global_position),dominant)

func configure_brawler(context:Dictionary,callback:Callable,item_id:="")->void:
	if item_id!=brawler_weapon_id:brawler_gestures.clear();brawler_weapon_id=item_id
	brawler_context=context.duplicate(true);brawler_authority=callback

func sample_brawler_gestures(delta:float,head_tracked:bool)->void:
	brawler_input_captured=false
	var learned:bool=brawler_context.values().any(func(row):return row.get("learned",false))
	var permitted:bool=learned and allowed and head_tracked and not tka_input_captured and not swordsman_input_captured and not fencer_input_captured and not pikeman_input_captured and not pistoleer_input_captured and not carbineer_input_captured and not rifleman_input_captured and not bountyhunter_input_captured and brawler_authority.is_valid() and combat_actions_allowed() and inventory_allows_combat() and not squad_input_captured and not bountyhunter_input_captured and not dna_input_captured and not ability_ui.menu_open and not (is_instance_valid(datapad) and datapad.is_open) and not vehicle_hand_busy(dominant)
	if not permitted or not is_instance_valid(origin):brawler_gestures.clear();return
	var forward:Vector3=-head.global_basis.z;forward.y=0
	if forward.length_squared()<.1:brawler_gestures.clear();return
	var basis:=Basis(Vector3.UP,atan2(-forward.x,-forward.z))
	var hands:Dictionary={}
	var offhand:="left" if dominant=="right" else "right"
	for side:String in ["left","right"]:
		var hand:XRController3D=origin.get_node(side.capitalize()+"Hand")
		hands[side]={"position":basis.inverse()*(hand.global_position-head.global_position),"upright":hand.global_basis.y.dot(Vector3.UP),"grip":hand.get_float("grip"),"trigger":hand.get_float("trigger"),"tracked":HandInput.controller_tracked(hand),"free":not offhand_occupied and not support_latched and not vehicle_hand_busy(side) and not pet_trigger_reserved(side)}
	var ability:String=brawler_gestures.sample(delta,hands,offhand,permitted)
	brawler_input_captured=brawler_gestures.capturing
	if brawler_input_captured:physical_guard.clear()
	if not ability.is_empty():
		var context:Dictionary=brawler_context.get(ability,{})
		if context.get("learned",false) and context.get("conditions_met",false) and float(context.get("cooldown_remaining_seconds",0))<=0:brawler_authority.call(ability,offhand)

func configure_warcry(context:Dictionary,callback:Callable)->void:
	warcry_context=context.duplicate(true);warcry_authority=callback

func sample_overhead_warcry(delta:float,head_tracked:bool)->void:
	warcry_input_captured=false
	if swordsman_input_captured or fencer_input_captured or pikeman_input_captured or pistoleer_input_captured or carbineer_input_captured or rifleman_input_captured or bountyhunter_input_captured:overhead_warcry.clear();return
	var permitted:bool=allowed and head_tracked and selected>=0 and selected<weapons.size() and warcry_authority.is_valid() and bool(warcry_context.get("learned",false)) and bool(warcry_context.get("conditions_met",false)) and float(warcry_context.get("cooldown_remaining_seconds",0))<=0 and combat_actions_allowed() and inventory_allows_combat() and not squad_input_captured and not bountyhunter_input_captured and not dna_input_captured and not ability_ui.menu_open and not (is_instance_valid(datapad) and datapad.is_open) and not vehicle_hand_busy(dominant)
	if not permitted or not is_instance_valid(origin):overhead_warcry.clear();return
	var controller:XRController3D=origin.get_node(dominant.capitalize()+"Hand")
	var support:XRController3D=origin.get_node("LeftHand" if dominant=="right" else "RightHand")
	var forward:Vector3=-head.global_basis.z;forward.y=0
	if forward.length_squared()<.1:overhead_warcry.clear();return
	var basis:=Basis(Vector3.UP,atan2(-forward.x,-forward.z))
	var hand:Dictionary={"position":controller.global_position,"relative":basis.inverse()*(controller.global_position-head.global_position),"head_y":head.global_position.y,"item_id":str(weapons[selected].state.profile.get("item_id","")),"tracked":HandInput.controller_tracked(controller),"grip":controller.get_float("grip"),"trigger":controller.get_float("trigger"),"support_trigger":support.get_float("trigger")}
	var fired:bool=overhead_warcry.sample(delta,hand,permitted)
	warcry_input_captured=overhead_warcry.capturing
	if warcry_input_captured:physical_guard.clear()
	if fired:swordsman_gestures.clear();fencer_gestures.clear();pikeman_gestures.clear();warcry_authority.call(head.global_transform,dominant)

func configure_taunt(context:Dictionary,callback:Callable)->void:
	taunt_context=context.duplicate(true);taunt_authority=callback

func sample_chest_taunt(delta:float,head_tracked:bool)->void:
	taunt_input_captured=false
	var permitted:bool=allowed and head_tracked and not warcry_input_captured and not brawler_input_captured and not tka_input_captured and not swordsman_input_captured and not fencer_input_captured and not pikeman_input_captured and not pistoleer_input_captured and not carbineer_input_captured and not rifleman_input_captured and not bountyhunter_input_captured and taunt_authority.is_valid() and bool(taunt_context.get("learned",false)) and float(taunt_context.get("cooldown_remaining_seconds",0))<=0 and combat_actions_allowed() and inventory_allows_combat() and not squad_input_captured and not bountyhunter_input_captured and not dna_input_captured and not ability_ui.menu_open and not (is_instance_valid(datapad) and datapad.is_open)
	if not permitted or not is_instance_valid(origin):chest_taunt.clear();return
	var forward:Vector3=-head.global_basis.z;forward.y=0
	if forward.length_squared()<.1:chest_taunt.clear();return
	var basis:=Basis(Vector3.UP,atan2(-forward.x,-forward.z))
	var hands:Dictionary={}
	for side:String in ["left","right"]:
		var controller:XRController3D=origin.get_node(side.capitalize()+"Hand")
		var free_hand:bool=(selected<0 or side!=dominant) and not (side!=dominant and (offhand_occupied or support_latched)) and not vehicle_hand_busy(side) and not pet_trigger_reserved(side)
		hands[side]={"position":basis.inverse()*(controller.global_position-head.global_position),"tracked":HandInput.controller_tracked(controller),"free":free_hand,"grip":controller.get_float("grip"),"trigger":controller.get_float("trigger")}
	var side:String=chest_taunt.sample(delta,hands,permitted)
	taunt_input_captured=chest_taunt.capturing
	if taunt_input_captured:physical_guard.clear()
	if not side.is_empty():taunt_authority.call(head.global_transform,side)

func sample_physical_guard(delta:float)->void:
	if not is_instance_valid(origin) or not allowed or not inventory_allows_combat() or dna_input_captured or taunt_input_captured or warcry_input_captured or brawler_input_captured or tka_input_captured or swordsman_input_captured or fencer_input_captured or pikeman_input_captured or pistoleer_input_captured or carbineer_input_captured or rifleman_input_captured or bountyhunter_input_captured or offhand_occupied or ability_ui.menu_open or (is_instance_valid(datapad) and datapad.is_open):physical_guard.clear();return
	if is_instance_valid(body) and body.has_method("combat_actions_allowed") and not body.combat_actions_allowed():physical_guard.clear();return
	var left:XRController3D=origin.get_node("LeftHand")
	var right:XRController3D=origin.get_node("RightHand")
	var tracker:=XRServer.get_tracker("head")
	var head_pose:XRPose=tracker.get_pose("default") if tracker!=null else null
	if head_pose==null or not head_pose.has_tracking_data or not HandInput.controller_tracked(left) or not HandInput.controller_tracked(right) or vehicle_hand_busy("left") or vehicle_hand_busy("right") or pet_trigger_reserved("left") or pet_trigger_reserved("right"):physical_guard.clear();return
	var forward:Vector3=-head.global_basis.z;forward.y=0
	if forward.length_squared()<.1:physical_guard.clear();return
	forward=forward.normalized()
	var basis:=Basis(Vector3.UP,atan2(-forward.x,-forward.z))
	var l:Vector3=basis.inverse()*(left.global_position-head.global_position)
	var r:Vector3=basis.inverse()*(right.global_position-head.global_position)
	var mode:="boxing";var item:="";var axis:=Vector3.UP
	if selected>=0:
		var entry:Dictionary=weapons[selected]
		if not entry.state.is_melee() or not entry.state.certified() or (int(entry.state.profile.hands)==2 and not two_hands):physical_guard.clear();return
		mode="parry";item=str(entry.state.profile.get("item_id",""))
		var bounds:AABB=entry.bounds
		axis=(basis.inverse()*entry.visual.global_basis[bounds.size.max_axis_index()]).normalized()
	elif unarmed.is_empty() or maxf(left.get_float("grip"),left.get_float("trigger"))<.5 or maxf(right.get_float("grip"),right.get_float("trigger"))<.5:
		physical_guard.clear();return
	guard_sample_ms=Time.get_ticks_msec()
	guard_head=head.global_position;guard_forward=forward
	physical_guard.sample(delta,mode,l,r,axis,dominant,item)

func guard_payload(app:Node,native_weapon:Dictionary)->Dictionary:
	if not allowed or Time.get_ticks_msec()-guard_sample_ms>150:return {"mode":"none"}
	var value:Dictionary=physical_guard.current.duplicate(true)
	if value.mode=="none":return value
	if value.mode=="boxing":value.item_id=str(native_weapon.get("item_id",""))
	if str(value.item_id).is_empty():return {"mode":"none"}
	var p:Vector3=app.source_position_at(guard_head)
	var f:Vector3=(app.source_position_at(guard_head+guard_forward)-p).normalized()
	value.head=[p.x,p.y,p.z];value.forward=[f.x,f.y,f.z]
	return value

func action_haptic(kind:String,side:="")->void:
	if not allowed or not is_instance_valid(origin):return
	var hand:="left" if side=="left" else "right" if side=="right" else dominant
	var controller:XRController3D=origin.get_node(hand.capitalize()+"Hand")
	if HandInput.controller_tracked(controller):controller.trigger_haptic_pulse("haptic",0,.65 if kind=="hit" else .2,.065 if kind=="hit" else .025,0)

func guard_feedback(value:Dictionary)->void:
	var count:=int(value.get("blocks",0))
	if allowed and count>guard_feedback_blocks and guard_feedback_blocks>=0 and is_instance_valid(origin):
		for side:String in (["left","right"] if value.get("mode","")=="boxing" else [dominant]):
			var controller:XRController3D=origin.get_node(side.capitalize()+"Hand")
			if HandInput.controller_tracked(controller):controller.trigger_haptic_pulse("haptic",0,.55,.07,0)
	guard_feedback_blocks=count

func _physics_process(delta: float) -> void:
	if is_instance_valid(body) and body.get("feedback") != null:
		var scales: Dictionary = body.feedback.armour
		for entry: Dictionary in weapons: entry.state.observe_armour(scales)
		for state in unarmed.values(): state.observe_armour(scales)
	if not is_instance_valid(head): return
	abilities.tick(delta)
	if not is_instance_valid(origin):
		chest_taunt.clear();taunt_input_captured=false;overhead_warcry.clear();warcry_input_captured=false;brawler_gestures.clear();brawler_input_captured=false;tka_gestures.clear();tka_input_captured=false;swordsman_gestures.clear();swordsman_input_captured=false;fencer_gestures.clear();fencer_input_captured=false;pikeman_gestures.clear();pikeman_input_captured=false;melee_marker_previous.clear()
		physical_guard.clear();pistoleer_gestures.clear();pistoleer_input_captured=false;carbineer_gestures.clear();carbineer_input_captured=false;rifleman_gestures.clear();rifleman_input_captured=false;clear_bountyhunter();cancel_showdown()
		step_desktop(delta)
		return
	var main: XRController3D = origin.get_node("LeftHand" if dominant=="left" else "RightHand")
	var support: XRController3D = origin.get_node("RightHand" if dominant=="left" else "LeftHand")
	var head_tracker = XRServer.get_tracker("head")
	var head_pose: XRPose = head_tracker.get_pose("default") if head_tracker != null else null
	var tracked := head_pose != null and head_pose.has_tracking_data and HandInput.controller_tracked(main)
	var right: XRController3D = origin.get_node("RightHand")
	sample_ability_input(main.is_button_pressed("primary_click"), main.get_vector2("primary"), right.is_button_pressed("ax_button") and HandInput.controller_tracked(right), tracked)
	sample_dna_inputs(main.global_transform,support.global_transform,main.get_float("trigger"),support.get_float("trigger"),tracked,head_pose!=null and head_pose.has_tracking_data and HandInput.controller_tracked(support))
	sample_squad_controls(delta,main.get_float("trigger"),support.get_float("trigger"),tracked,HandInput.controller_tracked(support))
	sample_bountyhunter_gestures(delta,head_pose!=null and head_pose.has_tracking_data)
	sample_rifleman_gestures(delta,head_pose!=null and head_pose.has_tracking_data)
	sample_carbineer_gestures(delta,head_pose!=null and head_pose.has_tracking_data)
	sample_pistoleer_gestures(delta,head_pose!=null and head_pose.has_tracking_data)
	sample_pikeman_gestures(delta,head_pose!=null and head_pose.has_tracking_data)
	sample_fencer_gestures(delta,head_pose!=null and head_pose.has_tracking_data)
	sample_swordsman_gestures(delta,head_pose!=null and head_pose.has_tracking_data)
	sample_tka_gestures(delta,head_pose!=null and head_pose.has_tracking_data)
	sample_brawler_gestures(delta,head_pose!=null and head_pose.has_tracking_data)
	sample_overhead_warcry(delta,head_pose!=null and head_pose.has_tracking_data)
	sample_chest_taunt(delta,head_pose!=null and head_pose.has_tracking_data)
	sample(delta,controller_weapon_pose(main),support.global_transform,0.0 if vehicle_hand_busy(dominant) else main.get_float("grip"),0.0 if offhand_occupied or vehicle_hand_busy("left" if dominant=="right" else "right") else support.get_float("grip"),0.0 if vehicle_hand_busy(dominant) else main.get_float("trigger"),tracked and not vehicle_hand_busy(dominant),HandInput.controller_tracked(support),main.is_button_pressed("by_button"),support.get_float("trigger"))
	var posture := current_firing_posture()
	sample_unarmed(delta,dominant,main.global_transform,tracked,posture,main.get_float("trigger"))
	var offhand := "left" if dominant=="right" else "right"
	sample_unarmed(delta,offhand,support.global_transform,head_pose!=null and head_pose.has_tracking_data and HandInput.controller_tracked(support),posture,support.get_float("trigger"))
	sample_physical_guard(delta)
	update_visuals()

func step_desktop(delta: float) -> void:
	movement_spread.sample(body.velocity,head.position,delta,allowed)
	var posture := current_firing_posture()
	# Explicit debug harness; ranged VR aiming uses the weapon; melee uses the head.
	var permitted: bool = allowed and combat_actions_allowed() and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not ability_ui.menu_open
	sample_squad_controls(delta,1.0 if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) else 0.0,1.0 if Input.is_key_pressed(KEY_SHIFT) else 0.0,permitted,true)
	var debug_swing := desktop_swing_remaining>0
	desktop_swing_remaining=maxf(0,desktop_swing_remaining-delta)
	if selected >= 0:
		var offset := Vector3(0.18,-0.16,-0.3)
		if debug_swing and weapons[selected].state.is_melee(): offset.x += (0.35-desktop_swing_remaining)*2.0
		weapons[selected].visual.global_transform = head.global_transform * Transform3D(Basis.IDENTITY,offset)
	for i in range(weapons.size()):
		var state = weapons[i].state
		var trigger := 1.0 if not squad_input_captured and (Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or debug_swing) else 0.0
		var shot: Dictionary = state.sample_swing(delta,permitted and not squad_input_captured and selected==i and debug_swing,desktop_support,posture,swing_position(weapons[i].visual.global_position),Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)) if state.is_melee() else state.tick(delta,trigger,permitted and selected==i,desktop_support,posture)
		if not shot.is_empty():
			var pose := muzzle_pose(i)
			var grip: Vector3 = weapons[i].visual.global_position
			dispatch_shot(shot,pose,grip,state.profile,state.is_melee())
	if selected<0 and unarmed.has(dominant):
		var pose := head.global_transform*Transform3D(Basis.IDENTITY,Vector3(0.2+(0.35-desktop_swing_remaining)*2.0 if debug_swing else 0.2,-0.15,-0.3))
		sample_unarmed(delta,dominant,pose,permitted and debug_swing,posture,1.0 if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) else 0.0)
	two_hands = desktop_support
	update_visuals()

func _unhandled_key_input(event: InputEvent) -> void:
	if is_instance_valid(origin) or not allowed or not event.is_pressed() or event.is_echo(): return
	if event.keycode == KEY_F5: draw(0)
	elif event.keycode == KEY_F6 and weapons.size()>1: draw(1)
	elif event.keycode == KEY_F4: stow()
	elif event.keycode == KEY_F7: desktop_support = not desktop_support
	elif event.keycode == KEY_F8 and selected>=0: weapons[selected].state.cycle_mode()
	elif event.keycode == KEY_F9 and selected>=0: weapons[selected].state.reload()
	elif event.keycode == KEY_F10 and ((selected>=0 and weapons[selected].state.is_melee()) or (selected<0 and not unarmed.is_empty())): desktop_swing_remaining=0.35
	elif event.keycode == KEY_F11:
		sample_ability_input(true, Vector2.ZERO, false, true)
		sample_ability_input(false, Vector2.ZERO, false, true)
	elif event.keycode == KEY_UP and ability_ui.menu_open:
		sample_ability_input(false, Vector2.UP, false, true)
	elif event.keycode == KEY_F12:
		sample_ability_input(false, Vector2.ZERO, true, true)
		sample_ability_input(false, Vector2.ZERO, false, true)
	else: return
	get_viewport().set_input_as_handled()

func _exit_tree() -> void:
	stow()
	if is_instance_valid(body) and body.has_method("set_combat_capture"): body.set_combat_capture("", false)
	# Head-anchored UI is outside this rig subtree; release it with the rig.
	if is_instance_valid(reticle): reticle.queue_free()
