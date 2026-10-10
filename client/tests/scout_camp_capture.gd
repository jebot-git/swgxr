extends SceneTree
class Host extends Node3D:
	var datapad_epoch:=1
	var datapad_account:="fixture"
	var datapad_character_id:="fixture"
	var world_ready:=true
	var inventory_request_pending:=false
	var inventory_snapshot: Dictionary={}
	var stage: Node3D
	var combat_rig: Node3D
	var live_combat: Node3D
	var player: Node3D
	var gathering: Node
	var inventory: Node3D
	var terrain: Node3D
	func source_position_at(value: Vector3) -> Vector3:return Vector3(value.x+5000,value.y,-5400-value.z)
	func reconcile_inventory_presentations() -> void:pass
	func update_inventory_presentation() -> void:inventory.set_snapshot(inventory_snapshot)
	func api(_method: HTTPClient.Method,_path: String,_payload: Dictionary={}) -> Dictionary:return {"ok":false}
	func owned_inventory_item(_id: String) -> Dictionary:return {}
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var host:=Host.new();root.add_child(host)
	host.stage=Node3D.new();host.add_child(host.stage);host.stage.set_meta("manifest",{"origin":[5000,0,-5400]})
	var rig: XROrigin3D=load("res://xr/player_rig.tscn").instantiate();host.add_child(rig)
	host.player=rig.get_node("PlayerBody");host.player.set_physics_process(false);host.player.active=true
	var head: Camera3D=rig.get_node("XRCamera3D");head.position=Vector3(0,2,6);head.current=true
	host.inventory=load("res://scripts/xr_inventory.gd").new();host.add_child(host.inventory);host.inventory.configure(rig,host.player);host.inventory.set_process(false);host.inventory.set_allowed(true)
	host.gathering=load("res://scripts/resource_gathering.gd").new();host.add_child(host.gathering);host.gathering.configure(host,host.inventory);host.gathering.set_process(false)
	var scout=load("res://scout/controller.gd").new();host.add_child(scout);scout.setup(host,host.inventory);scout.set_process(false)
	var record: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/server/scout-camp.json"))
	scout.state=record.state;host.datapad_character_id=record.state.character_id;host.inventory_snapshot=record.state.inventory
	scout.sync_items();scout.sync_camps()
	var camp: Dictionary=record.state.camps[0];var terminal: Vector3=scout.world(camp.terminal_position)
	host.player.global_position=terminal+Vector3(0,0,1);head.global_position=terminal+Vector3(0,1.2,0.85);head.look_at(terminal+Vector3(0,1.0,0))
	scout.update_camp_ui()
	var environment:=WorldEnvironment.new();var settings:=Environment.new();settings.background_mode=Environment.BG_COLOR;settings.background_color=Color("101b27");environment.environment=settings;host.add_child(environment)
	var caption:=Label.new();caption.text="Original CoreCU camp and terminal · desktop Vulkan · mocked tracking";caption.position=Vector2(20,20);host.add_child(caption)
	for i in range(8):await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://../runtime/evidence/scout-camp-vulkan.png")
	head.global_position=scout.world(camp.position)+Vector3(8,5,8);head.look_at(scout.world(camp.position)+Vector3(1,0.6,0))
	for i in range(8):await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://../runtime/evidence/scout-camp-overview-vulkan.png")
	print(JSON.stringify({"original_camp_models":scout.models.size(),"camp_objects":camp.objects.size()+1,"terminal_ui_visible":scout.is_open,"disband_enabled":not scout.disband.disabled,"live_headset":false}))
	host.free();await process_frame;quit()
