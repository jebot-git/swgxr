extends SceneTree
class Harness extends "res://scripts/main.gd":
	func _ready() -> void: pass
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var snapshot: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/evidence/crafting-live-snapshot.json"))
	assert(snapshot.backend=="core3" and not snapshot.weapons.is_empty())
	var app := Harness.new()
	root.add_child(app)
	app.args={"desktop":true,"combat-items":true,"no-world":true,"no-terrain":true}
	app.screenshot_path="test-harness"
	app.stage_path=ProjectSettings.globalize_path("res://../runtime/assets/mos_eisley/scene.json")
	app.configure_inputs(); app.make_environment()
	app.player=app.PlayerScript.new(); app.add_child(app.player); app.make_ui()
	await app.enter_stage(true)
	app.configure_combat_lab(snapshot)
	assert(is_instance_valid(app.combat_rig) and app.combat_rig.weapons.size()==2)
	for weapon in app.combat_rig.weapons:
		var state=weapon.state
		assert(state.profile.source_kind=="core3_weapon_instance")
		assert(snapshot.weapons.any(func(item):return item.item_id==state.profile.item_id and ((item.power==state.profile.power and item.stance_recovery==state.profile.stance_recovery) if state.is_melee() else (item.rpm==state.profile.rpm and item.capacity==state.profile.capacity))))
		assert(state.certified())
	assert(app.combat_rig.unarmed.size()==2 and app.combat_rig.unarmed.right.profile==snapshot.unarmed)
	assert(app.session_mode.contains("CORE3 WEAPONS"))
	# Exercise the no-supported-items branch using the real player profile and
	# an explicitly filtered inventory fixture; this is not an inventory mutation.
	app.combat_rig.free(); app.combat_target.free()
	var empty_inventory:Dictionary=snapshot.duplicate(true); empty_inventory.weapons=[]
	app.configure_combat_lab(empty_inventory)
	assert(is_instance_valid(app.combat_rig) and app.combat_rig.weapons.is_empty())
	assert(app.combat_rig.unarmed.size()==2 and app.combat_rig.unarmed.right.profile==snapshot.unarmed)
	print("CRAFTED_WEAPON_MAIN_PASS · real item snapshot, actual stage, headset not tested")
	app.queue_free(); await process_frame; quit()
