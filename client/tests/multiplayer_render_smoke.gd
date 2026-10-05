extends SceneTree
const Players = preload("res://multiplayer/remote_players.gd")
const Peer = preload("res://multiplayer/remote_player.gd")
const Pulse = preload("res://multiplayer/survey_pulse.gd")
var checks := 0
var failures: Array = []
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); push_error(message)
func _initialize() -> void: call_deferred("run")
func row(id: String, point: Vector3) -> Dictionary:
	return {"id": id, "name": "Native peer " + id, "position": point, "heading_radians": 0.0, "posture": 0, "appearance": {"template": "object/creature/player/human_male.iff", "height": 1.0, "customization": {}, "equipment": []}}
func run() -> void:
	var host := Node3D.new(); root.add_child(host)
	host.position = Vector3(40, 3, 12); host.rotation.y = 0.5
	var manager := Players.new(); host.add_child(manager); manager.configure(); manager.set_process(false); manager.max_players = 2
	manager.apply_snapshot([row("self", Vector3.ZERO), row("near", Vector3.ZERO), row("second", Vector3(4, 0, 0)), row("far", Vector3(10, 0, 0)), row("culled", Vector3(500, 0, 0))], "self", Vector3.ZERO)
	check(manager.peers.is_empty() and manager.pending.size() == 2, "Appearance construction is queued and nearest interest set bounded")
	var timeout := Time.get_ticks_msec() + 15000
	while manager.peers.size() < 2 and Time.get_ticks_msec() < timeout:
		manager._process(0.001)
		await process_frame
	check(manager.peers.size() == 2 and manager.peers.has("near") and manager.peers.has("second"), "Worker-prepared source avatars publish only nearest two native identities")
	if manager.peers.size() < 2: quit(1); return
	var peer: Node3D = manager.peers.near
	var second: Node3D = manager.peers.second
	check(manager.appearance_cache.hits == 1 and manager.appearance_cache.entries.size() == 1, "Identical original appearance reuses bounded assembled geometry cache")
	check(peer.avatar.meshes[0].mesh == second.avatar.meshes[0].mesh, "Immutable original geometry is shared across remote instances")
	check(peer.avatar.skeleton != second.avatar.skeleton and peer.avatar.animation_player != second.avatar.animation_player, "Cached avatar owns independent source skeleton and animation playback")
	var wrist: int = peer.avatar.skeleton.find_bone("lwrist")
	var original_wrist: Quaternion = second.avatar.skeleton.get_bone_pose_rotation(wrist)
	peer.avatar.skeleton.set_bone_pose_rotation(wrist, Quaternion(Vector3.UP, 0.7))
	check(second.avatar.skeleton.get_bone_pose_rotation(wrist).is_equal_approx(original_wrist), "One player's tracked bone changes cannot modify another player")
	check(peer.avatar.meshes[0].get_active_material(0) != second.avatar.meshes[0].get_active_material(0), "Per-player material overrides remain independent on shared meshes")
	peer.avatar.meshes[0].get_active_material(0).set_meta("isolation_fixture", true)
	check(not second.avatar.meshes[0].get_active_material(0).has_meta("isolation_fixture"), "Material edits cannot leak between cached avatars")
	peer.avatar.animation_player.get_animation_library("").add_animation("isolation_fixture", Animation.new())
	check(not second.avatar.animation_player.has_animation("isolation_fixture"), "New source clips cannot mutate another animation library")
	check(peer.avatar != null and peer.avatar.race_id == "human_male", "Exact original player species rendered")
	var intrinsic := {"template":"object/weapon/melee/unarmed/unarmed_default_player.iff", "equipped_slots":["default_weapon"]}
	check(peer.avatar.equipment_selection([intrinsic]).failures.is_empty(), "Native intrinsic unarmed attack has no invented visible equipment")
	intrinsic.equipped_slots = ["hold_r"]
	check(not peer.avatar.equipment_selection([intrinsic]).failures.is_empty(), "Unarmed item outside exact logical default slot is not silently ignored")
	check(not peer.avatar.equipment_selection([{"template":"object/weapon/melee/unarmed/missing.iff", "equipped_slots":["default_weapon"]}]).failures.is_empty(), "Other unknown equipment remains diagnosed")
	check(peer.global_position.is_equal_approx(Vector3.ZERO), "World placement does not inherit transformed manager parent")
	check(not peer is CollisionObject3D and peer.find_children("*", "CollisionObject3D", true, false).is_empty(), "Remote presentation cannot drive local collision or movement")
	for mesh in peer.avatar.meshes: check(mesh.layers == 1, "Remote source head visible in world layer")
	peer.advance(0.1)
	var moved := row("near", Vector3(1, 0, 0)); peer.apply_peer(moved)
	check(peer.global_position.is_equal_approx(Vector3.ZERO), "New nearby position is not snapped")
	peer.advance(0.05)
	check(peer.global_position.x > 0.0 and peer.global_position.x < 1.0, "Position interpolates toward authoritative goal")
	check(peer.avatar.motion_state == "strafe_right", "Original locomotion follows interpolated sample direction")
	peer.advance(0.6)
	check(peer.avatar.motion_state == "idle", "Stale locomotion does not extrapolate forever")
	moved.position = Vector3(30, 0, 0); peer.apply_peer(moved)
	check(peer.global_position.is_equal_approx(moved.position), "Native long-distance transport snaps instead of flying through walls")
	var tracking := {}
	for pair in [["head", "head"], ["left_hand", "lwrist"], ["right_hand", "rwrist"]]:
		tracking[pair[0]] = peer.avatar.skeleton.global_transform * peer.avatar.skeleton.get_bone_global_pose(peer.avatar.skeleton.find_bone(pair[1]))
	moved.tracking = tracking; peer.apply_peer(moved); peer.advance(0.02)
	check(peer.pose_report.get("tracked", false) and peer.pose_report.get("left", {}).get("valid", false) and peer.pose_report.get("right", {}).get("valid", false), "Both original wrist poses and head retarget through bounded native IK")
	moved.physical_posture = 1; peer.apply_peer(moved); peer.advance(0.05)
	check(peer.avatar.motion_state == "crouch", "Fresh physical crouch drives original lower-body animation")
	moved.dead = true; moved.posture = 14; peer.apply_peer(moved); peer.advance(0.05)
	check(peer.life_state() == "dead" and peer.pose_report.get("frozen", false), "Native death locks original full-body pose despite tracked hand samples")
	moved.dead = false; moved.posture = 0; moved.physical_posture = 0; moved.pose_age_ms = 1000; peer.apply_peer(moved); peer.advance(0.05)
	check(not peer.pose_report.get("tracked", true), "Expired tracking cannot overwrite recovered native body")
	moved.tracking = {"left_hand": Transform3D(Basis.IDENTITY, Vector3(1000, 0, 0))}; moved.pose_age_ms = 0; peer.apply_peer(moved)
	check(peer.tracking_goal.is_empty(), "Unbounded distant hand target rejected")
	moved.appearance.template = "object/creature/player/unavailable.iff"; peer.apply_peer(moved)
	check(peer.avatar == null and "unavailable" in peer.label.text, "Missing original appearance diagnosed without substituting another player mesh")
	manager.apply_snapshot([], "self", Vector3.ZERO)
	check(manager.peers.is_empty() and manager.pending.is_empty(), "Absent full-snapshot IDs immediately removed including pending appearances")
	var pulse := Pulse.new(); host.add_child(pulse); pulse.set_process(false)
	check(pulse.play_confirmed(Vector3.ZERO, "receipt"), "Confirmed survey starts a source-style ground pulse")
	check(not pulse.play_confirmed(Vector3.ZERO, "receipt"), "Repeated confirmed receipt cannot duplicate pulse")
	check(not pulse.play_confirmed(Vector3.INF, "invalid"), "Nonfinite effect position rejected")
	for index in range(20): pulse.play_confirmed(Vector3.ZERO, "many%d" % index)
	check(pulse.pulses.size() == Pulse.MAX_PULSES, "Simultaneous survey effects obey hard shared cap")
	pulse.advance(0.9)
	check(is_equal_approx(float(pulse.pulses[0].node.get_instance_shader_parameter("pulse_phase")), 0.5), "Survey ring expands with fixed lifetime")
	pulse.advance(1.0)
	check(pulse.pulses.is_empty(), "Expired survey nodes released")
	var remote_tools := preload("res://multiplayer/remote_deployments.gd").new()
	check(not remote_tools.count_text({"resource_name": "Ore", "state": "sampling"}).contains("units"), "Public deployed tools never invent private resource quantities")
	check(remote_tools.nearest(Vector3.ZERO).is_empty(), "Remote tool cannot enter local pickup ownership")
	remote_tools.free()
	manager.effect_assets = preload("res://combat/original_assets.gd").new()
	manager.effect_assets.catalog = {"weapons":{"native_pistol":{"shared_template":"object/weapon/ranged/pistol/shared_pistol_cdef.iff", "effects":{"fire":"source-pistol-fire"}}}}
	manager.desired = {"shooter":{"appearance":{"equipment":[{"id":"native-item", "template":"object/weapon/ranged/pistol/pistol_cdef.iff", "equipped_slots":["hold_r"]}]}}}
	check(manager.event_weapon({"actor_id":"shooter", "weapon_id":"native-item"}).get("effects", {}).get("fire", "") == "source-pistol-fire", "Confirmed native weapon identity chooses exact original effect program")
	check(manager.event_weapon({"actor_id":"shooter", "weapon_id":"previous-item", "weapon_template":"object/weapon/ranged/pistol/pistol_cdef.iff"}).is_empty(), "Delayed effect cannot borrow a different equipped weapon after native item changes")
	check(manager.event_weapon({"actor_id":"unknown", "weapon_id":"native-item"}).is_empty(), "Unknown actor equipment is never replaced with generic blaster effects")
	var result := {"checks": checks, "failures": failures, "appearance_build_peak_ms_dummy": manager.build_peak_ms, "cached_appearance_build_peak_ms_dummy": manager.cached_build_peak_ms, "validation": "Original local assets; mocked authenticated multiplayer rows and dummy renderer. Not a live-server or headset test."}
	FileAccess.open(ProjectSettings.globalize_path("res://../runtime/evidence/multiplayer-render-smoke.json"), FileAccess.WRITE).store_string(JSON.stringify(result, "  "))
	print(JSON.stringify(result))
	host.queue_free(); await process_frame; await process_frame
	quit(0 if failures.is_empty() else 1)
