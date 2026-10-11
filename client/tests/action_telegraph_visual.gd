extends SceneTree
## Isolated Forward+ inspection of the production warning geometry, not a stage/XR test.
const Controller=preload("res://combat/action_combat.gd")
class Mapping extends Node:
	func world(p:Array)->Vector3:return Vector3(p[0],p[1],p[2])
func _initialize()->void:call_deferred("run")
func run()->void:
	var world:=Node3D.new();root.add_child(world)
	var mapping:=Mapping.new();world.add_child(mapping)
	var controller:=Controller.new();world.add_child(controller);controller.sync=mapping;controller.set_process(false)
	var camera:=Camera3D.new();world.add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=34
	camera.position=Vector3(12,30,7);camera.rotation_degrees=Vector3(-90,0,0);camera.current=true
	var env:=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color(.035,.045,.065);world.add_child(env)
	var ui:=CanvasLayer.new();world.add_child(ui)
	var title:=Label.new();title.text="GROUND PvE  /  PREPARATION → DELIVERY";title.position=Vector2(30,18);title.add_theme_font_size_override("font_size",26);ui.add_child(title)
	var footer:=Label.new();footer.text="Filled area = elapsed preparation time     •     Full outline = danger footprint\nOriginal attack animation starts at 100%; the fill stays full through delivery.";footer.position=Vector2(30,625);footer.add_theme_font_size_override("font_size",20);ui.add_child(footer)
	for role:String in ["ranged","melee"]:
		for i in 5:
			var o:=[i*6,0,0 if role=="ranged" else 9]
			var event:Dictionary={"role":role,"origin":o,"direction":[0,0,1],"range":6 if role=="ranged" else 3.,"radius":.55,"cosine":.5,"start":10.,"delivery_at":11.,"active_at":11.333,"aim_revision":1}
			var warning:=controller.draw_warning(event);controller.update_fill(warning,event,10.+float(i)/4,Color(1,.12,.08) if i==4 else Color(1,.55,.08))
			var label:Label3D=warning.get_node("TargetCue");label.text=str(i*25)+"%";label.position=Vector3(i*6,0,-1 if role=="ranged" else 7.8);label.font_size=64;label.pixel_size=.012
	for i in 12:await process_frame
	await RenderingServer.frame_post_draw
	var args:=OS.get_cmdline_user_args();var dest:=args[0] if not args.is_empty() else "/tmp/action-telegraphs.png"
	var error:=root.get_texture().get_image().save_png(dest)
	print(JSON.stringify({"saved":dest,"error":error,"renderer":RenderingServer.get_current_rendering_method(),"driver":RenderingServer.get_current_rendering_driver_name(),"headset_tested":false}));quit(error)
