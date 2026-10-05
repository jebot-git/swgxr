extends SceneTree
const Actor=preload("res://combat/live_actor.gd")
const Assets=preload("res://scripts/inventory_assets.gd")
const Ambient=preload("res://scripts/ambient_npcs.gd")
const Live=preload("res://combat/live_world.gd")
var errors:Array=[]
var checks:=0
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:errors.append(message);push_error(message)
func _initialize()->void:call_deferred("run")
func run()->void:
	var ambient:=Ambient.new();root.add_child(ambient);ambient.set_process(false);ambient.configure(ProjectSettings.globalize_path("res://../runtime/assets/ambient_npcs/placements.json"))
	var assets:=Assets.new();assets.configure();var dead:=Assets.new();dead.configure(ProjectSettings.globalize_path("res://../runtime/assets/corpses/catalog.json"))
	var primary:=ProjectSettings.globalize_path("res://../runtime/assets/combat_population/mos_eisley_easy/catalog.json")
	var live:=Live.new();root.add_child(live);live.set_process(false);live.configure_ambient(ambient)
	var values:Array=[];var expected:Dictionary={}
	for mobile:String in ["doikk_nats","stormtrooper_rifleman"]:
		var entry:Dictionary=ambient.manifest.instances.filter(func(e):return e.mobile==mobile)[0]
		values.append({"id":mobile,"template":entry.template,"kind":"creature","position":entry.source_world_xyz,"heading_radians":0,"scale":1,"health":100,"max_health":100,"dead":false,"name":mobile})
		expected[mobile]=entry
	for value:Dictionary in live.source_visual_records(values):
		var actor:=Actor.new();live.add_child(actor);check(actor.configure(value,"mock-native",assets,dead,primary),"Exact source variant constructs: "+value.id)
		var entry:Dictionary=expected[value.id];var descriptor:Dictionary=ambient.catalog.races[entry.appearance_id]
		check(actor.record.template==value.template and actor.visual.race_id==entry.appearance_id,"Native template identity remains separate from source placement appearance variant")
		check(actor.report.get("source_variant_ready",false) and actor.report.equipment_provenance=="source_placement_equipment" and not actor.report.native_equipment_authoritative,"Source-derived visual equipment provenance is explicit")
		check(actor.visual.loaded_parts.filter(func(p):return p.scope=="equipment").size()==descriptor.default_outfit.size() and actor.visual.skeleton.get_bone_count()>30,"Source CDF/outfit clothing and original skeleton remain intact")
		check(actor.rigid_equipment.size()==1 and actor.rigid_equipment[0].source.template==descriptor.rigid_equipment[0].template,"Original band instrument or T21 mesh attached to source skeleton")
		check(actor.rigid_equipment[0].attachment.bone_name==descriptor.rigid_equipment[0].bone and not actor.rigid_equipment[0].attachment.override_pose,"Equipment follows original bone without driving skeleton pose")
		live.actors[str(value.id)]=actor
	live.synchronize_ambient(values)
	check(ambient.live_suppressed.size()==2,"Local counterparts suppressed only after complete matching source equipment construction")
	var body:Dictionary=live.actors.doikk_nats.record.duplicate(true);body.dead=true
	var corpse:=Actor.new();root.add_child(corpse);check(corpse.configure(body,"mock-native",assets,dead,primary) and corpse.report.source_variant_ready and corpse.rigid_equipment.size()==1 and not corpse.visual.animation_player.is_playing(),"Source-clothed band corpse keeps instrument and frozen original incapacitated pose")
	live.actors.doikk_nats.report.source_variant_ready=false;live.synchronize_ambient(values)
	check(ambient.live_suppressed.size()==1,"Failed replacement restores corresponding original local presentation")
	live.reset("test stopped");check(ambient.live_suppressed.is_empty(),"Stop restores all source placements")
	var report:Dictionary={"passed":errors.is_empty(),"checks":checks,"errors":errors,"real_http_requests":0,"gpu_tested":false,"equipment_provenance":"source_placement_equipment"}
	print(JSON.stringify(report));FileAccess.open("res://../runtime/evidence/live-source-outfits-smoke.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	corpse.queue_free();live.queue_free();ambient.queue_free();await process_frame;quit(0 if errors.is_empty() else 1)
