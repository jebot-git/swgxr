extends SceneTree
class Player extends CharacterBody3D:
	func set_interface_capture(_move:bool,_turn:bool)->void:pass
func _initialize()->void:call_deferred("run")
func run()->void:
	root.size=Vector2i(1280,900)
	var world:=Node3D.new();root.add_child(world)
	var environment:=WorldEnvironment.new();var config:=Environment.new();config.background_mode=Environment.BG_COLOR;config.background_color=Color("081525");environment.environment=config;world.add_child(environment)
	var rig:=XROrigin3D.new();world.add_child(rig)
	var head:=XRCamera3D.new();head.name="XRCamera3D";rig.add_child(head);head.position=Vector3(.03,1.65,.15);head.current=true;head.fov=74
	for side in ["LeftHand","RightHand"]:
		var hand:=XRController3D.new();hand.name=side;rig.add_child(hand)
	rig.get_node("LeftHand").position=Vector3(-.32,1.05,-.6);rig.get_node("RightHand").position=Vector3(.45,1.15,-.48)
	rig.get_node("LeftHand").rotation=Vector3(.8,.4,1.25)
	var player:=Player.new();world.add_child(player)
	var bag:=preload("res://scripts/xr_inventory.gd").new();world.add_child(bag);bag.configure(rig,player);bag.set_process(false);bag.set_allowed(true)
	var tool:Dictionary={"id":"101","name":"Mineral survey tool","template":"object/tangible/survey_tool/survey_tool_mineral.iff","tool_kind":"survey","container_id":"bag"}
	bag.set_snapshot({"inventory":{"id":"bag","capacity":80,"occupied":2},"items":[tool,{"id":"102","name":"Generic crafting tool","template":"object/tangible/crafting/station/generic_tool.iff","container_id":"bag"}]})
	bag.take_item(tool);bag.set_open(true)
	bag.global_transform=Transform3D(Basis.IDENTITY,Vector3(-.28,1.03,-.68));bag.pose_bag();head.look_at(Vector3(.06,1.19,-.65))
	var caption:=Label.new();root.add_child(caption);caption.position=Vector2(20,20);caption.text="OPEN INVENTORY + HELD ORIGINAL SURVEY TOOL\nMocked poses · desktop Forward+ Vulkan · XR disabled"
	for i in range(10):await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../runtime/evidence/headset-grab/inventory-backpack-vulkan.png"))
	print(JSON.stringify({"bag_visible":bag.surfaces[0].mesh.visible,"survey_hidden":not bag.surfaces[bag.survey_surface].mesh.visible,"held_original_tool":bag.held_model!=null,"renderer":"Forward+ Vulkan","headset_tested":false}));quit()
