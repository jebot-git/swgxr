extends SceneTree
## Replays rows produced by real local native placement, with original assets.
class Services extends Node:
	var origin:=Vector3.ZERO
	func world(p:Array)->Vector3:return Vector3(p[0]-origin.x,p[1]-origin.y,origin.z-p[2])
class Host extends Node3D:
	var terrain:Node3D
	var stage:Node3D
	var services:Node
var checks:=0
var errors:Array[String]=[]
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:errors.append(label);push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	create_timer(120).timeout.connect(func():push_error("Native structure replay timed out");quit(2))
	var fixture:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/evidence/structure-placement/native-world.json"))
	var housing:Dictionary=fixture.housing
	var camps:Array=fixture.scout.camps
	check(not housing.structures.is_empty() and not camps.is_empty(),"Actual placement fixture contains buildings and camps")
	if not errors.is_empty():quit(1);return
	var camp:Dictionary=camps[0]
	var origin:=Vector3(camp.position[0],0,camp.position[2])
	var host:=Host.new();root.add_child(host)
	host.services=Services.new();host.services.origin=origin;host.add_child(host.services)
	host.stage=preload("res://scripts/cell_stage.gd").new();host.stage.set_meta("manifest",{"origin":[origin.x,origin.y,origin.z]});host.add_child(host.stage)
	host.terrain=preload("res://scripts/terrain_stream.gd").new();host.add_child(host.terrain)
	check(host.terrain.configure("res://../runtime/assets/terrain/tatooine.json",origin),"Original planet terrain loads")
	var base:=SwgTerrainEvaluator.new();base.configure(host.terrain.source_manifest)
	var scenery:=preload("res://housing/world.gd").new();host.add_child(scenery);scenery.setup(host);scenery.apply(housing)
	for row:Dictionary in housing.structures:
		var id:=str(row.id)
		check(scenery.structures.has(id),"Original structure appears for native ID "+id)
		if not scenery.structures.has(id):continue
		var model:Node3D=scenery.structures[id]
		check(model.global_position.distance_to(host.services.world(row.position))<.002,"Structure uses server foundation height")
		check(host.stage.cell_regions.has("house:"+id),"Structure collision region registered")
		var manifest:Dictionary=model.get_meta("manifest",{})
		var authored_solid:=false
		for collision:Dictionary in manifest.get("collisions",{}).values():
			if str(collision.get("extent",{}).get("type","null"))!="null":authored_solid=true
		for cell:Dictionary in manifest.get("cells",{}).values():
			if not cell.get("floor_indices",[]).is_empty():authored_solid=true
		var has_bodies:=not model.find_children("*","StaticBody3D",true,false).is_empty()
		check(has_bodies==authored_solid,"Collision follows original solid/null and fall-through definitions: "+str(row.template))
		if str(row.get("terrain_modification_file",""))=="":
			check(absf(host.terrain.evaluator.sample_height(row.position[0],row.position[2])-base.sample_height(row.position[0],row.position[2]))<.001,"No synthetic terrain flattening beneath foundation-only template")
	# Use production camp replication to install both visuals and terrain layer.
	var rig:XROrigin3D=load("res://xr/player_rig.tscn").instantiate();host.add_child(rig)
	var body:CharacterBody3D=rig.get_node("PlayerBody");body.set_physics_process(false)
	var bag:=preload("res://scripts/xr_inventory.gd").new();host.add_child(bag);bag.configure(rig,body);bag.set_process(false)
	var scout:=preload("res://scout/controller.gd").new();host.add_child(scout);scout.set_process(false);scout.app=host;scout.bag=bag
	scout.camp_catalog=JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/assets/scout/catalog.json"))
	# The native harness captures sequential deployments, not overlapping camps.
	scout.state={"camps":[camp]};scout.sync_camps()
	check(scout.models.has(str(camp.id)),"Native camp original model renders")
	check(host.terrain.modification_groups.get("camps",[]).size()==1,"Native camp row installs its original terrain layer")
	var location:Vector3=host.services.world(camp.position)
	host.terrain.update_observer(location)
	while not host.terrain.ready_near(location,1):await process_frame
	for i in 3:await physics_frame
	var maximum_gap:=0.0
	for x in [-6.0,0.0,6.0]:
		for z in [-6.0,0.0,6.0]:
			var p:=location+Vector3(x,0,z)
			var ray:=PhysicsRayQueryParameters3D.create(p+Vector3.UP*40,p-Vector3.UP*40,2)
			var hit:Dictionary=host.get_world_3d().direct_space_state.intersect_ray(ray)
			check(not hit.is_empty(),"Camp support collision exists across footprint")
			if not hit.is_empty():maximum_gap=maxf(maximum_gap,absf(hit.position.y-location.y))
	check(maximum_gap<.003,"Actual native camp elevation matches rebuilt collision")
	if "--capture" in OS.get_cmdline_user_args():
		check(RenderingServer.get_current_rendering_method()=="forward_plus","Evidence uses Vulkan Forward+")
		# Isolate the camp view; distant structures can precede their terrain LOD.
		for model:Node3D in scenery.structures.values():model.hide()
		var environment:=WorldEnvironment.new();var settings:=Environment.new();settings.background_mode=Environment.BG_COLOR;settings.background_color=Color("74899b");environment.environment=settings;host.add_child(environment)
		var camera:=Camera3D.new();host.add_child(camera);camera.position=location+Vector3(26,18,30);camera.look_at(location+Vector3.UP);camera.current=true;camera.far=2000
		root.size=Vector2i(1280,800)
		var label:=Label.new();root.add_child(label);label.position=Vector2(20,20);label.text="Original camp + terrain · actual local Core3 placement · desktop replay"
		for i in 8:await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://../runtime/evidence/structure-placement/camp-terrain.png")
		var house:Dictionary=housing.structures[0]
		var house_center:Vector3=host.services.world(house.position)
		host.terrain.update_observer(house_center)
		while not host.terrain.ready_near(house_center,1):await process_frame
		scenery.structures[str(house.id)].show()
		camera.position=house_center+Vector3(30,18,35);camera.look_at(house_center+Vector3.UP*2)
		label.text="Original house foundation + terrain · actual local Core3 placement · desktop replay"
		for i in 8:await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://../runtime/evidence/structure-placement/house-terrain.png")
	# Exercise each later native deployment separately, replacing the prior layer.
	for next_camp:Dictionary in camps.slice(1):
		scout.state={"camps":[next_camp]};scout.sync_camps()
		var center:Vector3=host.services.world(next_camp.position)
		host.terrain.update_observer(center)
		while not host.terrain.ready_near(center,0):await process_frame
		for i in 3:await physics_frame
		check(scout.models.has(str(next_camp.id)) and host.terrain.modification_groups.camps.size()==1,"Each native camp tier replaces previous model and layer")
		var ray:=PhysicsRayQueryParameters3D.create(center+Vector3.UP*40,center-Vector3.UP*40,2)
		var hit:Dictionary=host.get_world_3d().direct_space_state.intersect_ray(ray)
		check(not hit.is_empty() and absf(hit.position.y-center.y)<.003,"Each native camp tier matches actual terrain collision")
		check(absf(host.terrain.evaluator.sample_height(next_camp.position[0]+80,next_camp.position[2])-base.sample_height(next_camp.position[0]+80,next_camp.position[2]))<.001,"Each native camp preserves terrain outside authored bounds")
	var before:float=base.sample_height(camp.position[0]+6,camp.position[2])
	scout.state={"camps":[]};scout.sync_camps()
	host.terrain.update_observer(location)
	while not host.terrain.ready_near(location,0):await process_frame
	check(absf(host.terrain.evaluator.sample_height(camp.position[0]+6,camp.position[2])-before)<.001,"Native camp removal restores original terrain")
	check(scout.models.is_empty(),"Camp removal clears replicated visuals")
	scenery.clear();check(host.stage.cell_regions.is_empty(),"Structure removal clears authored collision regions")
	var report:Dictionary={"passed":errors.is_empty(),"checks":checks,"errors":errors,"native_fixture_replay":true,"max_camp_collision_gap_m":maximum_gap,"gpu_tested":"--capture" in OS.get_cmdline_user_args(),"headset_tested":false}
	FileAccess.open("res://../runtime/evidence/structure-placement/client-world.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "));print(JSON.stringify(report))
	host.queue_free();await process_frame;quit(0 if errors.is_empty() else 1)
