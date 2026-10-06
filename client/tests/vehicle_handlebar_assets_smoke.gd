extends SceneTree
## Source-art partition and local yaw fixtures; no live tracking or driving claim.
const Assets=preload("res://scripts/inventory_assets.gd")
const Splitter=preload("res://vehicles/yoke_visual.gd")
var failures:Array[String]=[]
var checks:=0
func check(value:bool,message:String)->void:
	checks+=1
	if not value:failures.append(message);push_error(message)
func triangle_count(mesh:ArrayMesh)->int:
	var result:=0
	for i in mesh.get_surface_count():result+=mesh.surface_get_array_index_len(i)/3
	return result
func _initialize()->void:call_deferred("run")
func run()->void:
	var capture:=OS.get_cmdline_user_args().has("--capture")
	var assets:=Assets.new();assets.configure("res://../runtime/assets/vehicles/catalog.json")
	var splitter:=Splitter.new()
	var world:=Node3D.new();root.add_child(world)
	var camera:=Camera3D.new();world.add_child(camera);camera.fov=48;camera.make_current()
	var environment:=WorldEnvironment.new();environment.environment=Environment.new();environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color(.12,.14,.17);world.add_child(environment)
	root.size=Vector2i(1100,800)
	for name in ["speederbike","speederbike_swoop","speederbike_flash"]:
		var template:String="object/mobile/vehicle/"+name+".iff"
		var descriptor:Dictionary=assets.descriptor(template)
		var mesh:ArrayMesh=assets.model(template)
		var original_count:=triangle_count(mesh)
		var split:Dictionary=splitter.meshes(template,mesh,descriptor)
		check(not split.is_empty(),name+": original handlebar split exists")
		if split.is_empty():continue
		check(triangle_count(split.body)+triangle_count(split.yoke)==original_count and triangle_count(mesh)==original_count,name+": exact source triangle conservation")
		check(split.yoke.surface_get_material(0)==mesh.surface_get_material(int(descriptor.steering_geometry.surface)),name+": original steering texture/material retained")
		var source_arrays:Array=mesh.surface_get_arrays(int(descriptor.steering_geometry.surface))
		var steering_arrays:Array=split.yoke.surface_get_arrays(0)
		for channel in [Mesh.ARRAY_VERTEX,Mesh.ARRAY_NORMAL,Mesh.ARRAY_TEX_UV]:
			var preserved:bool=source_arrays[channel].size()==steering_arrays[channel].size()
			if preserved:
				for vertex in source_arrays[channel].size():
					if source_arrays[channel][vertex].distance_to(steering_arrays[channel][vertex])>(0.0003 if channel==Mesh.ARRAY_NORMAL else 0.000001):preserved=false;break
			check(preserved,name+": source vertex channel retained within normal packing precision "+str(channel))
		var hull:=MeshInstance3D.new();hull.mesh=split.body;world.add_child(hull)
		var bar:=MeshInstance3D.new();bar.mesh=split.yoke;world.add_child(bar)
		var p:Array=descriptor.steering_geometry.pivot
		var pivot:=Vector3(p[0],p[1],p[2])
		camera.position=pivot+Vector3(-.7,.65,1.1);camera.look_at(pivot+Vector3(0,-.12,0))
		for angle in [0.0,-0.4,0.4]:
			var basis:=Basis(Vector3.BACK if name=="speederbike_flash" else Vector3.UP,angle)
			bar.transform=Transform3D(basis,pivot-basis*pivot)
			check(bar.transform*pivot==pivot or (bar.transform*pivot).distance_to(pivot)<.000001,name+": source grip midpoint fixed")
			check(hull.transform==Transform3D.IDENTITY,name+": hull stays fixed during handle motion")
			if capture:
				for frame in range(3):await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("res://../runtime/evidence/"+name+"-handlebars-"+str(angle)+".png")
		hull.queue_free();bar.queue_free();await process_frame
	var report:={"passed":failures.is_empty(),"checks":checks,"failures":failures,"hardware_tested":false,"gpu_capture":capture and DisplayServer.get_name()!="headless","renderer":"dummy" if DisplayServer.get_name()=="headless" else RenderingServer.get_current_rendering_method()}
	FileAccess.open("res://../runtime/evidence/vehicle-handlebar-mesh-smoke.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print(JSON.stringify(report));world.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
