extends SwgFirstPersonController
var combat_pools = preload("res://combat/ability_state.gd").new()
var feedback = preload("res://combat/player_feedback.gd").new()

func _enter_tree() -> void:
	call_deferred("prepare_feedback")

func prepare_feedback() -> void:
	if is_instance_valid(feedback.body): return
	feedback.configure(self, get_camera())
	cosmetic_jump_requested.connect(func(): feedback.request_jump())
	spawn_reset.connect(feedback.reset)
	var driver := preload("res://combat/desktop_feedback_driver.gd").new()
	add_child(driver)

func configure_player_combat(context: Dictionary) -> void:
	prepare_feedback()
	combat_pools.refresh_context(context)
	feedback.observe(context)

func combat_actions_allowed() -> bool:
	return not feedback.combat_blocked() and not (is_instance_valid(feedback.performer) and feedback.performer.is_performing())

func receive_combat_knockdown() -> bool:
	prepare_feedback()
	var accepted: bool = feedback.receive_knockdown()
	movement_locked = feedback.combat_blocked()
	return accepted

# Native GDExtension owns capsule setup, first-person camera input, locomotion,
# floor snapping and reset. Jump/recovery presentation uses the shared feedback
# model without lifting the collision body. This is the scene-facing resource;
# menus, HTTP orchestration and stage selection remain in GDScript.
