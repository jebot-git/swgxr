extends SceneTree
const Avatar=preload("res://scripts/avatar.gd")
const Actor=preload("res://combat/live_actor.gd")
const Assets=preload("res://scripts/inventory_assets.gd")
const Entities=preload("res://multiplayer/world_entities.gd")
const LiveWorld=preload("res://combat/live_world.gd")
class Source extends Node3D:
	var catalog_path:String
	func set_live_suppressed(_value:Dictionary)->void:pass
const Bindings=preload("res://combat/live_ambient_bindings.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	var reports:Array=[];var passed:=true;var total:=0
	var counts:={"tatooine":9,"corellia":7,"naboo":10,"rori":5,"talus":5,"dantooine":4,"dathomir":7,"endor":3,"lok":4,"yavin4":4}
	for planet:String in counts:
		var report:Dictionary=await test_planet(planet,counts[planet]);reports.append(report);passed=passed and report.passed;total+=int(report.heralds)
	FileAccess.open("res://../runtime/evidence/herald-outfit-smoke.json",FileAccess.WRITE).store_string(JSON.stringify({"passed":passed,"heralds":total,"planets":reports,"renderer":"dummy","headset_tested":false},"  "))
	print(JSON.stringify({"passed":passed,"heralds":total}));quit(0 if passed else 1)
func test_planet(planet:String,expected_count:int)->Dictionary:
	var directory:String="res://../runtime/assets/ambient_npcs" if planet=="tatooine" else "res://../runtime/assets/planets/"+planet+"/ambient"
	var manifest:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/placements.json"))
	var catalog:=ProjectSettings.globalize_path(directory+"/catalog.json")
	var assets:=Assets.new();assets.configure()
	var dead:=Assets.new();dead.configure(ProjectSettings.globalize_path("res://../runtime/assets/corpses/catalog.json"))
	var rows:Array=[];var expected:Dictionary={}
	for entry:Dictionary in manifest.instances:
		if entry.selection.kind not in ["heraldList","multiDestHeraldList"]:continue
		var id:String=entry.mobile+str(rows.size())
		rows.append({"id":id,"template":entry.template,"kind":"creature","position":[entry.source_world_xyz[0]+12,entry.source_world_xyz[1],entry.source_world_xyz[2]+8],"herald_home_position":entry.source_world_xyz,"heading_radians":0,"scale":1,"health":100,"max_health":100,"dead":false,"building_id":entry.building_object_id,"cell_index":int(str(entry.get("cell_id","0:0")).get_slice(":",1)),"name":entry.label})
		expected[id]=entry
	var bindings:=Bindings.new();bindings.configure(manifest);bindings.update(rows)
	var errors:Array=[];var reports:Array=[];var variants:Dictionary={}
	var source:=Source.new();source.catalog_path=catalog
	var entities:=Entities.new();entities.ambient=source
	var live_world:=LiveWorld.new();live_world.ambient_source=source
	for row:Dictionary in rows:
		var entry:Dictionary=expected[row.id]
		if bindings.bindings.get(row.id)!=entry.id:errors.append("Herald exact binding failed: "+entry.mobile);continue
		row.source_placement_visual={"placement_id":entry.id,"appearance_id":entry.appearance_id,"catalog":catalog,"cell_id":entry.cell_id}
		var actor:=Actor.new();root.add_child(actor)
		var ready:bool=actor.configure(row,"test",assets,dead,catalog)
		var clothing:int=actor.visual.loaded_parts.filter(func(p):return p.scope=="equipment").size() if ready and is_instance_valid(actor.visual) and actor.visual is Avatar else 0
		if not ready or not actor.report.get("source_variant_ready",false):errors.append("Incomplete original herald: "+entry.mobile)
		if entry.mobile=="herald_lorne_prestar" and clothing<5:errors.append("Lorne Prestar original five-piece outfit missing")
		reports.append({"mobile":entry.mobile,"clothing_parts":clothing,"report":actor.report})
		if "--capture" in OS.get_cmdline_user_args() and entry.mobile=="herald_lorne_prestar":
			var camera:=Camera3D.new();root.add_child(camera);camera.position=Vector3(0,1.15,3);camera.look_at(Vector3(0,1,0));camera.current=true
			var environment:=WorldEnvironment.new();environment.environment=Environment.new();environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color("16202b");environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color.WHITE;environment.environment.ambient_light_energy=.8;root.add_child(environment)
			var sun:=DirectionalLight3D.new();root.add_child(sun);sun.rotation_degrees=Vector3(-30,-30,0)
			var ui:=CanvasLayer.new();root.add_child(ui);var caption:=Label.new();ui.add_child(caption);caption.position=Vector2(20,20);caption.text="Lorne Prestar — original herald outfit / isolated desktop Vulkan inspection"
			for frame in 8:await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://../runtime/evidence/herald-lorne-prestar.png")
			camera.queue_free();environment.queue_free();sun.queue_free();ui.queue_free()

		actor.queue_free();await process_frame
		for template:String in entry.source_templates:
			var variant:=row.duplicate(true);variant.erase("source_placement_visual");variant.template=template
			entities.bindings.configure({"instances":[entry]});entities.accept([variant],"test",entities.revision+1)
			live_world.ambient_bindings.configure({"instances":[entry]})
			var projected:Array=live_world.source_visual_records([variant])
			var appearance:String=template if entry.source_templates.size()>1 else entry.appearance_id
			for value:Dictionary in [entities.desired.get(row.id,{}),projected[0]]:
				if value.get("source_placement_visual",{}).get("appearance_id","")!=appearance:errors.append("Native variant projection failed: "+entry.mobile+" / "+template)
				if value.get("position")!=row.position:errors.append("Wandering herald position changed: "+entry.mobile)
			if variants.has(appearance):continue
			var model:=Actor.new();root.add_child(model)
			var complete:bool=model.configure(projected[0],"test",assets,dead,catalog) and model.report.get("source_variant_ready",false)
			variants[appearance]=complete
			if not complete:errors.append("Incomplete herald pool appearance: "+appearance)
			model.queue_free();await process_frame
	entities.free();live_world.free();source.free()
	var report:={"planet":planet,"passed":errors.is_empty() and rows.size()==expected_count,"heralds":rows.size(),"errors":errors,"actors":reports,"appearance_variants":variants.size(),"renderer":"dummy","headset_tested":false}
	print(JSON.stringify({"planet":planet,"passed":report.passed,"heralds":rows.size(),"appearance_variants":variants.size(),"errors":errors}));return report
