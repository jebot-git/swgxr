extends SceneTree
## Original living/dead animal, native-lair source building, and FWG5 assets only.
const Avatar=preload("res://scripts/avatar.gd")
const Items=preload("res://scripts/inventory_assets.gd")
const Weapons=preload("res://combat/original_assets.gd")
var errors: Array[String]=[]
func check(ok:bool,message:String)->void:
	if not ok: errors.append(message); push_error(message)
func _initialize()->void: call_deferred("run")
func run()->void:
	var avatar:=Avatar.new(); root.add_child(avatar)
	avatar.load_catalog(ProjectSettings.globalize_path("res://../runtime/assets/combat_population/mos_eisley_easy/catalog.json"))
	var report:=avatar.configure("object/mobile/worrt_hue.iff",{"height":1.0,"customization":{"/private/index_color_1":3}})
	check(report.get("error","").is_empty() and avatar.skeleton.get_bone_count()==30,"Original living worrt skeleton unavailable")
	var states: Dictionary={}
	for key in ["idle","walk","run"]:
		check(avatar.animation_player.has_animation(key),"Original worrt clip missing: "+key)
		avatar.animation_player.play(key); avatar.animation_player.seek(0,true)
		var before: Array=[]
		for i in range(30): before.append(avatar.skeleton.get_bone_pose(i))
		avatar.animation_player.advance(0.31)
		var changed:=false
		for i in range(30): changed=changed or not before[i].is_equal_approx(avatar.skeleton.get_bone_pose(i))
		check(changed,"Original living worrt animation remains frozen: "+key); states[key]=changed
	var items:=Items.new(); items.configure()
	var template:="object/tangible/lair/base/poi_all_lair_dead_log_small.iff"
	var mesh:=items.model(template)
	check(mesh!=null,"Original passive lair source model missing")
	var descriptor:=items.descriptor(template)
	var bounds:=mesh.get_aabb() if mesh!=null else AABB()
	check(bounds.position.y< -1.9 and bounds.size.x>7,"Lair authored origin/meters replaced by preview-fit scaling")
	var population:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/assets/combat_population/mos_eisley_easy/sources.json"))
	var lairs:Dictionary={}
	for lair:Dictionary in population.get("lairs",{}).values():
		for source_template:String in lair.get("building_templates",[]): lairs[source_template]=true
	for source_template:String in lairs:
		var source_mesh:=items.model(source_template)
		check(source_mesh!=null and source_mesh.get_surface_count()>0,"Original beginner-group lair variant unavailable: "+source_template)
	var corpses:=Items.new(); corpses.configure(ProjectSettings.globalize_path("res://../runtime/assets/corpses/catalog.json"))
	check(corpses.model("object/mobile/worrt_hue.iff")!=null,"Dead worrt original pose missing")
	var weapons:=Weapons.new(); check(weapons.load_catalog(),"Original combat catalog unavailable")
	var pistol:=weapons.model("pistol_fwg5")
	check(pistol!=null and pistol.get_child_count()>0,"Original FWG5 presentation failed")
	check(weapons.muzzle("pistol_fwg5").distance_to(Vector3(0,0.05273598,-0.1965818))<0.00001,"Original FWG5 muzzle transform changed")
	var result:={"passed":errors.is_empty(),"errors":errors,"live_worrt_bones":30,"source_clip_motion":states,"lair_template":template,"source_group_lair_variants":lairs.size(),"lair_model_sha256":descriptor.get("model_sha256"),"weapon":"pistol_fwg5","server_combat_tested":false,"gpu_tested":false}
	FileAccess.open("res://../runtime/evidence/passive-lair-assets-smoke.json",FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	print(JSON.stringify(result)); avatar.queue_free(); if pistol!=null:pistol.free()
	await process_frame; quit(0 if errors.is_empty() else 1)
