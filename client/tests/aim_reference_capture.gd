extends SceneTree
## Real Forward+ depth/transparent-order regression; never run as headset evidence.
const Aim = preload("res://combat/aim_reference.gd")
const Assets = preload("res://combat/original_assets.gd")
func _initialize() -> void: call_deferred("run")
func frame_image() -> Image:
	for i in range(3): await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()
func run() -> void:
	if DisplayServer.get_name()=="headless":
		push_error("Reticle occlusion capture requires Forward+ Vulkan")
		quit(2)
		return
	root.size=Vector2i(960,640)
	var world:=Node3D.new()
	root.add_child(world)
	var camera:=Camera3D.new()
	world.add_child(camera)
	camera.make_current()
	var blocker:=MeshInstance3D.new()
	var box:=BoxMesh.new()
	box.size=Vector3(4,4,0.1)
	blocker.mesh=box
	blocker.position.z=-1
	var surface:=StandardMaterial3D.new()
	surface.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	surface.albedo_color=Color(0.12,0.035,0.025)
	blocker.material_override=surface
	world.add_child(blocker)
	var assets:=Assets.new()
	if not assets.load_catalog(): quit(2); return
	var aim:=Aim.new()
	world.add_child(aim)
	aim.configure(assets.texture(assets.catalog.reticle.path))
	var measurements:=[]
	var passed:=true
	for transparent in [false,true]:
		surface.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA if transparent else BaseMaterial3D.TRANSPARENCY_DISABLED
		surface.albedo_color.a=0.95 if transparent else 1.0
		surface.render_priority=100 if transparent else 0
		aim.visible=false
		var before:=await frame_image()
		aim.update_aim(camera.global_transform,true)
		var after:=await frame_image()
		var changed:=0
		for y in range(240,400):
			for x in range(400,560):
				var a:=before.get_pixel(x,y)
				var b:=after.get_pixel(x,y)
				if absf(a.g-b.g)+absf(a.b-b.b)>0.01: changed+=1
		passed=passed and changed>20
		measurements.append({"transparent_occluder":transparent,"changed_reticle_pixels":changed,"occluder_distance_m":1,"reticle_distance_m":3})
		after.save_png("res://../runtime/evidence/reticle-over-%s.png" % ("transparent" if transparent else "opaque"))
	# Reticle must stay at identical view pixels when head poses update after
	# combat. A uniform background isolates the overlay from moving scenery.
	blocker.visible=false
	aim.update_head_aim(camera,true)
	var anchored:=await frame_image()
	camera.transform=Transform3D(Basis.from_euler(Vector3(0.35,1.2,0.13)),Vector3(4,1.7,-2))
	var moved:=await frame_image()
	var maximum_error:=0.0
	for y in range(240,400):
		for x in range(400,560):
			var a:=anchored.get_pixel(x,y); var b:=moved.get_pixel(x,y)
			maximum_error=maxf(maximum_error,maxf(absf(a.r-b.r),maxf(absf(a.g-b.g),absf(a.b-b.b))))
	passed=passed and maximum_error<0.01
	measurements.append({"head_anchored":true,"maximum_view_pixel_error_after_head_motion":maximum_error})
	moved.save_png("res://../runtime/evidence/reticle-head-stable.png")
	var result:={"test":"forward_plus_reticle_over_occluders","passed":passed,"cases":measurements,"headset_tested":false,"renderer":RenderingServer.get_current_rendering_method(),"driver":RenderingServer.get_current_rendering_driver_name()}
	FileAccess.open("res://../runtime/evidence/reticle-occlusion-render.json",FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	print(JSON.stringify(result))
	world.queue_free()
	await process_frame
	quit(0 if passed else 1)
