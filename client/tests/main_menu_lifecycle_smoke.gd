extends SceneTree
class Host extends "res://scripts/main.gd":
	func _ready()->void:pass
	func _process(_delta:float)->void:pass
	func _physics_process(_delta:float)->void:pass
var checks:=0
var errors:Array[String]=[]
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:errors.append(label);push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	root.size=Vector2i(1440,1000)
	var app:=Host.new();root.add_child(app)
	app.player=app.PlayerScript.new();app.add_child(app.player);app.player.set_physics_process(false)
	app.make_ui();app.core3_ready=true
	app.world_ready=true;app.datapad_account="fixture";app.datapad_character_id="123"
	app.characters=[{"id":"123","name":"Lifecycle fixture"}];app.character_list.add_item("Lifecycle fixture");app.character_list.select(0)
	app.update_buttons()
	check(not app.logoff_button.disabled and not app.quit_button.disabled,"Loaded world exposes functional logoff and quit controls")
	check(app.create_button.disabled and app.enter_button.disabled,"Character cannot be replaced before native logout")
	app.resume_button.show();app.action_row.show()
	app.avatar=Node3D.new();app.add_child(app.avatar)
	for property in ["combat_rig","combat_target","ambient_npcs","portal_visibility","world_stream","terrain","stage"]:
		var node:=Node3D.new();app.add_child(node);app.set(property,node)
	var old_stage:Node=app.stage
	app.inventory_snapshot={"items":[{"id":"fixture"}]}
	app.clear_character_world();app.update_buttons()
	check(old_stage.is_queued_for_deletion() and old_stage.process_mode==Node.PROCESS_MODE_DISABLED and not old_stage.visible,"World presentation is disabled immediately while callback-safe teardown is queued")
	await process_frame
	check(not is_instance_valid(old_stage) and app.stage==null and app.avatar==null and app.world_stream==null,"Actual teardown removes world, avatar and streaming workers")
	check(app.datapad_character_id.is_empty() and app.inventory_snapshot.is_empty() and not app.world_ready,"Actual teardown clears character-owned client state")
	check(app.menu.visible and not app.resume_button.visible and not app.action_row.visible and app.logoff_button.disabled and not app.quit_button.disabled,"Roster remains usable after teardown with quit available")
	if OS.get_cmdline_user_args().has("--capture"):
		for i in range(5):await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://../runtime/evidence/gameplay-core1/main-menu.png")
	app.free()
	print(JSON.stringify({"checks":checks,"errors":errors,"mocked_world":true,"XR_tested":false}));quit(0 if errors.is_empty() else 1)
