extends SceneTree
## Original public-building scenery with its native housing-discovery overlap.
const World=preload("res://scripts/world_stream.gd")
class Services extends Node:
	var origin:=Vector3.ZERO
	func world(p:Array)->Vector3:return Vector3(p[0]-origin.x,p[1]-origin.y,origin.z-p[2])
class Host extends Node3D:
	var world_stream:Node3D
	var stage:Node3D
	var services:Node
func _initialize()->void:call_deferred("run")
func run()->void:
	if DisplayServer.get_name()=="headless" or RenderingServer.get_current_rendering_method()!="forward_plus" or RenderingServer.get_current_rendering_driver_name()!="vulkan":quit(1);return
	root.size=Vector2i(1600,1000)
	RenderingServer.global_shader_parameter_set("swg_environment_tint",Color.WHITE);RenderingServer.global_shader_parameter_set("swg_indoor_tint",Color(.95,.92,.86));RenderingServer.global_shader_parameter_set("swg_daylight",1.0)
	var host:=Host.new();root.add_child(host);host.services=Services.new();host.add_child(host.services)
	var stream:=World.new();host.add_child(stream);host.world_stream=stream;stream.render_distance=100;stream.collision_distance=100
	if not stream.configure(ProjectSettings.globalize_path("res://../runtime/assets/tatooine_world/world.json")):quit(1);return
	host.stage=stream.cell_owner;var origin:Array=stream.manifest.origin;host.services.origin=Vector3(origin[0],origin[1],origin[2])
	var center:=Vector3(-4736.443325,8.154404,-1280.624565)
	var camera:=Camera3D.new();host.add_child(camera);camera.current=true;camera.position=center+Vector3(-1,2.1,2.2);camera.look_at(center+Vector3.UP*.75)
	stream.cell_owner.set_observer(camera);stream.update_observer(camera.position)
	var deadline:=Time.get_ticks_msec()+60000
	while not stream.report.get("ready",false):
		if Time.get_ticks_msec()>deadline:push_error("Bestine stream timeout");quit(1);return
		await process_frame
	var chunk:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(stream.directory.path_join(stream.manifest.chunks["-19:-5"].path)))
	var rows:Array=[];var building:Basis=stream.authored_basis("1028590")
	for row:Dictionary in chunk.instances:
		if row.get("cell_id")!="1028590:10" or not str(row.get("source_template","")).begins_with("object/tangible/furniture/"):continue
		var p:Array=row.position;var values:Array=row.quaternion;var q:Quaternion=(building.inverse()*Basis(Quaternion(values[0],values[1],values[2],values[3]))).get_rotation_quaternion()
		rows.append({"id":str(int(row.object_id)),"template":str(row.source_template).replace("/shared_","/"),"building_id":"1028590","cell_index":10,"position":[p[0]+origin[0],p[1]+origin[1],origin[2]-p[2]],"quaternion":[-q.x,-q.y,q.z,q.w],"recoverable":false})
	var before:bool="--before" in OS.get_cmdline_user_args()
	if before:host.world_stream=null
	var housing:=preload("res://housing/world.gd").new();host.add_child(housing);housing.setup(host);housing.apply({"structures":[],"items":rows})
	if rows.size()!=2 or housing.items.size()!=(2 if before else 0):push_error("Bestine furniture ownership mismatch");quit(1);return
	var label:=Label.new();root.add_child(label);label.position=Vector2(25,25);label.add_theme_font_size_override("font_size",25);label.text="Bestine · "+("BEFORE · duplicate housing scenery" if before else "AFTER · one original scenery instance")
	for i in range(15):await process_frame
	await RenderingServer.frame_post_draw
	var path:="res://../runtime/evidence/rec-inspection/bestine-"+("before" if before else "after")+".png"
	root.get_texture().get_image().save_png(path)
	print(JSON.stringify({"native_connection":false,"headset_tested":false,"renderer":"Vulkan Forward+","snapshot_furniture":rows.size(),"duplicate_visuals":housing.items.size(),"capture":path}))
	host.free();await process_frame;quit()
