extends SceneTree
const Actor=preload("res://combat/live_actor.gd")
const Assets=preload("res://scripts/inventory_assets.gd")
var checks:=0
var errors:Array[String]=[]
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:errors.append(message);push_error(message)
func _initialize()->void:call_deferred("run")
func run()->void:
	var assets:=Assets.new();assets.configure()
	var dead:=Assets.new();dead.configure(ProjectSettings.globalize_path("res://../runtime/assets/corpses/catalog.json"))
	var primary:=ProjectSettings.globalize_path("res://../runtime/assets/combat_population/mos_eisley_easy/catalog.json")
	var npc:=Actor.new();root.add_child(npc)
	var template:="object/mobile/dressed_commoner_tatooine_rodian_female_01.iff"
	var record:Dictionary={"id":"source_catalog_fixture","kind":"creature","template":template,"name":"Source dressed NPC","position":[0,0,0],"heading_radians":0,"scale":1,"health":100,"max_health":100,"dead":false}
	check(npc.configure(record,"mock-session",assets,dead,primary),"Exact dressed source template loads through ambient NPC catalog")
	check(npc.report.get("source_catalog","").ends_with("ambient_npcs/catalog.json") and npc.visual.race_id==template,"Source ID remains exact, without same-race substitution")
	var outfit_count:int=npc.visual.race.get("default_outfit",[]).size()
	var loaded:int=npc.visual.loaded_parts.filter(func(part):return part.scope=="equipment").size()
	check(outfit_count>=3 and loaded==outfit_count,"All original CDF equipment parts survive live projection")
	check(npc.visual.skeleton.get_bone_count()>30 and npc.visual.meshes.all(func(mesh):return mesh.skin!=null),"Original dressed NPC meshes retain skeleton skin binding")
	var unknown:=Actor.new();root.add_child(unknown);var absent:=record.duplicate(true);absent.template="object/mobile/unimported_source_template.iff"
	check(unknown.configure(absent,"mock-session",assets,dead,primary) and unknown.visual==null and unknown.collider==null and not unknown.is_targetable() and unknown.label.text.contains("unavailable"),"Unavailable original appearance retains explicit identity without replacement art or collider")
	check(npc.original_catalog("object/mobile/worrt_hue.iff",primary)==primary,"Original beginner creature retains primary source catalog")
	var henchman:=Actor.new();root.add_child(henchman);var current:=record.duplicate(true);current.template="object/mobile/dressed_tatooine_valarian_henchman.iff"
	check(henchman.configure(current,"mock-session",assets,dead,primary),"Actual failed-launch henchman loads exact newly imported source appearance")
	check(henchman.visual.skeleton.get_bone_count()==53 and henchman.visual.loaded_parts.filter(func(part):return part.scope=="equipment").size()==2,"Actual henchman retains original53-bone skeleton and both CDF wearables")
	var dead_henchman:=Actor.new();root.add_child(dead_henchman);current.dead=true
	check(dead_henchman.configure(current,"mock-session",assets,dead,primary),"Dead dressed NPC uses exact authored incapacitated animation")
	check(dead_henchman.visual.loaded_parts.filter(func(part):return part.scope=="equipment").size()==2 and not dead_henchman.visual.animation_player.is_playing(),"Frozen native corpse retains both original CDF wearables")
	check(str(dead_henchman.report.get("corpse_pose",{}).get("source","")).ends_with("all_b_incapacitated_face_up.ans"),"Corpse pose provenance names original incap clip, without claiming a dedicated death animation")
	var rejected:=Actor.new();root.add_child(rejected);var partial:=record.duplicate(true);partial.template="object/mobile/desert_demon_leader.iff"
	var broad:=ProjectSettings.globalize_path("res://../runtime/assets/combat_population/tatooine/catalog.json")
	if FileAccess.file_exists(broad):
		var catalog:Dictionary=Actor.Avatar.read_json(broad)
		for key:String in catalog.get("races",{}):
			if not catalog.races[key].get("appearance_complete",true):partial.template=key;break
		check(rejected.configure(partial,"mock-session",assets,dead,primary) and rejected.report.appearance_status=="partial" and rejected.visual!=null and not rejected.report.missing_components.is_empty(),"Available original body and clothing remain visible with explicit missing-component report")
	rejected.queue_free();dead_henchman.queue_free();henchman.queue_free()
	var output:Dictionary={"passed":errors.is_empty(),"checks":checks,"errors":errors,"server_mocked":true,"gpu_tested":false}
	print(JSON.stringify(output));FileAccess.open("res://../runtime/evidence/live-actor-catalog-smoke.json",FileAccess.WRITE).store_string(JSON.stringify(output,"  "))
	npc.queue_free();unknown.queue_free();await process_frame;quit(0 if errors.is_empty() else 1)
