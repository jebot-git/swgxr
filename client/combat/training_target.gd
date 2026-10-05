extends StaticBody3D
## Deliberately separate from Core3 NPCs, rewards and persistent health.
var damage_received := 0.0
var wound_count := 0
var hit_count := 0
var knockdown_count := 0
var resistances := {"energy":25.0,"kinetic":10.0}
var armor_rating := 1
var label: Label3D

func _ready() -> void:
	collision_layer = 8
	collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.8,1.3,0.12)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	add_child(collision)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = shape.size
	mesh.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.15,0.5,0.65)
	mesh.material_override = material
	add_child(mesh)
	label = Label3D.new(); label.font = preload("res://resources/fonts/Jupiteroid-Regular.ttf")
	label.font_size = 28
	label.pixel_size = 0.002
	label.position = Vector3(0,0.9,0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label)
	refresh_label()

func combat_defenses() -> Dictionary:
	return {"resistances":resistances,"armor_rating":armor_rating}

func receive_local_hit(event: Dictionary) -> void:
	damage_received += float(event.damage)
	wound_count += 1 if event.wound else 0
	hit_count += 1
	knockdown_count += 1 if event.get("knockdown", false) else 0
	refresh_label()

func refresh_label() -> void:
	if label != null: label.text = "LOCAL TRAINING TARGET\n%d hits · %.0f damage · %d wounds\n%d knockdowns" % [hit_count,damage_received,wound_count,knockdown_count]
