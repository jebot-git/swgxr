extends Node3D
## Weapon and rendered-hand orchestration; XR tracking stays untouched.
const WeaponState = preload("res://combat/weapon_state.gd")
const Projectiles = preload("res://combat/projectiles.gd")
const HandInput = preload("res://scripts/tracked_hand_input.gd")
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
var ability_click_down := false
var ability_prime_down := false
var ability_stick_latched := false
var dna_input_captured := false

func configure_player_combat(context: Dictionary) -> void:
	if is_instance_valid(body) and body.has_method("configure_player_combat"): body.configure_player_combat(context)
	else: abilities.refresh_context(context)

func combat_actions_allowed() -> bool:
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

func sample_ability_input(click: bool, stick: Vector2, prime: bool, tracked: bool) -> void:
	if is_instance_valid(body) and body.has_method("combat_actions_allowed") and is_instance_valid(body.feedback.performer) and body.feedback.performer.owns_controls():
		close_ability_menu()
		ability_click_down=click; ability_prime_down=prime
		return
	var permitted: bool = allowed and tracked and combat_actions_allowed() and inventory_allows_combat() and not (is_instance_valid(datapad) and datapad.is_open)
	var profile := active_profile()
	abilities.reconcile(profile)
	if not permitted:
		if not tracked: abilities.primed=false
		close_ability_menu()
		ability_stick_latched = false
	else:
		if click and not ability_click_down:
			if ability_ui.menu_open: close_ability_menu()
			else:
				ability_ui.open_on_hand(profile.get("abilities", []),origin.get_node(dominant.capitalize()+"Hand") if is_instance_valid(origin) else head,head)
			ability_stick_latched = true
		if ability_ui.menu_open:
			var choice: String = ability_ui.sample_stick(stick)
			if not choice.is_empty():
				abilities.select(profile, choice)
				if choice=="mask_scent": abilities.primed=true
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
		state.ability_state = abilities
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
		state.ability_state = abilities
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
	var permitted: bool = allowed and not dna_input_captured and not pet_trigger_reserved(side) and selected<0 and tracked and not vehicle_hand_busy(side) and not (offhand_occupied and side!=dominant) and combat_actions_allowed() and not ability_ui.menu_open and not (is_instance_valid(datapad) and datapad.is_open) and not (is_instance_valid(inventory) and inventory.interaction_active)
	var shot: Dictionary=unarmed[side].sample_swing(delta,permitted,false,posture,swing_position(pose.origin),is_finite(trigger) and trigger>=0.5)
	if not shot.is_empty():
		dispatch_shot(shot,pose,pose.origin,unarmed[side].profile,true)
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
	requested_weapon_pose=requested;have_weapon_request=true
	constrain_held_weapon()

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
		ability_stick_latched = false
		if is_instance_valid(body) and body.has_method("set_combat_capture"): body.set_combat_capture("", false)
		for weapon in weapons: weapon.state.block()
		if is_instance_valid(rounds_sim): rounds_sim.clear()
		stow()

func stow() -> void:
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

func sample(delta: float, main_pose: Transform3D, support_pose: Transform3D, grip: float, support_grip: float, trigger: float, tracked: bool, support_tracked: bool, action := false) -> void:
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
		if selected < 0 and main_grip_down and not previous_grip:
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
			if support_tracked and support_grip_down and not previous_support and support_pose.origin.distance_to(attach_point) < 0.18:
				support_latched = true
			# A pistol's rendered support hand stays attached until release; its
			# physical controller continues reporting input but cannot steer it.
			if long_gun and support_pose.origin.distance_to(main_pose.origin) > 0.65: support_latched = false
			two_hands = support_latched
			pose_weapon(main_pose,support_pose)
			if action and not action_down: weapon.state.cycle_mode()
	action_down = action
	var posture := current_firing_posture()
	for i in range(weapons.size()):
		var state = weapons[i].state
		var shot: Dictionary = state.sample_swing(delta,permitted and not dna_input_captured and selected==i and combat_actions_allowed() and not ability_ui.menu_open,two_hands,posture,swing_position(main_pose.origin),is_finite(trigger) and trigger>=0.5) if state.is_melee() else state.tick(delta,trigger,permitted and not dna_input_captured and selected==i and combat_actions_allowed() and not ability_ui.menu_open,two_hands,posture)
		if not shot.is_empty():
			var pose := muzzle_pose(i)
			dispatch_shot(shot,pose,weapons[i].visual.global_position,state.profile,state.is_melee())
			if is_instance_valid(origin):
				var controller: XRController3D = origin.get_node("LeftHand" if dominant=="left" else "RightHand")
				controller.trigger_haptic_pulse("haptic",0,0.35,0.045,0)
	update_visuals()

func dispatch_shot(shot: Dictionary, pose: Transform3D, grip: Vector3, profile: Dictionary, melee: bool) -> bool:
	var immutable: Dictionary=shot.duplicate(true)
	immutable["item_id"]=str(profile.get("item_id",""))
	if shot_authority.is_valid():
		if melee: return false # This bounded live milestone supports original ranged weapons only.
		var authorized: Variant=shot_authority.call(immutable,pose,grip)
		if not authorized is Dictionary or authorized.is_empty(): return false
		immutable=authorized.duplicate(true)
	if melee: rounds_sim.strike_melee(immutable,head.global_transform,pose)
	else: rounds_sim.spawn(immutable,pose,grip)
	return true

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
		if melee_aim: reticle.update_head_aim(head,allowed)
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
			weapon.label.text = "%d/%d · %s · %.0f RPM%s" % [state.rounds,int(state.profile.capacity),state.mode,state.effective_rpm()," · cooling" if state.reload_until>=0 else ""]

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
		state.ability_state = abilities
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

func _physics_process(delta: float) -> void:
	if not is_instance_valid(head): return
	abilities.tick(delta)
	if not is_instance_valid(origin):
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
	sample(delta,controller_weapon_pose(main),support.global_transform,0.0 if vehicle_hand_busy(dominant) else main.get_float("grip"),0.0 if offhand_occupied or vehicle_hand_busy("left" if dominant=="right" else "right") else support.get_float("grip"),0.0 if vehicle_hand_busy(dominant) else main.get_float("trigger"),tracked and not vehicle_hand_busy(dominant),HandInput.controller_tracked(support),main.is_button_pressed("by_button"))
	var posture := current_firing_posture()
	sample_unarmed(delta,dominant,main.global_transform,tracked,posture,main.get_float("trigger"))
	var offhand := "left" if dominant=="right" else "right"
	sample_unarmed(delta,offhand,support.global_transform,head_pose!=null and head_pose.has_tracking_data and HandInput.controller_tracked(support),posture,support.get_float("trigger"))
	update_visuals()

func step_desktop(delta: float) -> void:
	var posture := current_firing_posture()
	# Explicit debug harness; ranged VR aiming uses the weapon; melee uses the head.
	var permitted: bool = allowed and combat_actions_allowed() and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not ability_ui.menu_open
	var debug_swing := desktop_swing_remaining>0
	desktop_swing_remaining=maxf(0,desktop_swing_remaining-delta)
	if selected >= 0:
		var offset := Vector3(0.18,-0.16,-0.3)
		if debug_swing and weapons[selected].state.is_melee(): offset.x += (0.35-desktop_swing_remaining)*2.0
		weapons[selected].visual.global_transform = head.global_transform * Transform3D(Basis.IDENTITY,offset)
	for i in range(weapons.size()):
		var state = weapons[i].state
		var trigger := 1.0 if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or debug_swing else 0.0
		var shot: Dictionary = state.sample_swing(delta,permitted and selected==i and debug_swing,desktop_support,posture,swing_position(weapons[i].visual.global_position),Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)) if state.is_melee() else state.tick(delta,trigger,permitted and selected==i,desktop_support,posture)
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
