extends Node
## GDExtension owns the player's native virtual callbacks. Run presentation
## after its physics tick without overriding or duplicating native movement.
var body: CharacterBody3D
func _ready() -> void:
	body = get_parent()
	process_physics_priority = body.process_physics_priority + 1
func _physics_process(delta: float) -> void:
	if not body.is_physics_processing(): return
	body.feedback.advance(delta)
	body.movement_locked = body.feedback.combat_blocked()
