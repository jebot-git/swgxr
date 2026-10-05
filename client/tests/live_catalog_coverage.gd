extends SceneTree
## Bounded subprocess batch of exact original source appearances, no server connection.
const Actor=preload("res://combat/live_actor.gd")
const Assets=preload("res://scripts/inventory_assets.gd")
var args:Dictionary={}
func _initialize()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--"):
			var fields:=arg.substr(2).split("=",true,1);args[fields[0]]=fields[1] if fields.size()>1 else true
	call_deferred("run")
func run()->void:
	var sources_path:=str(args.get("sources",ProjectSettings.globalize_path("res://../runtime/assets/combat_population/tatooine_entities/sources.json")))
	var sources:Dictionary=Actor.Avatar.read_json(sources_path)
	var templates:Array=sources.get("appearance_templates",[]).duplicate();templates.sort()
	var first:=maxi(0,int(args.get("start",0)));var count:=clampi(int(args.get("count",16)),1,32)
	var errors:Array=[];var rows:Array=[]
	if templates.is_empty():errors.append("Source union missing or empty: "+sources_path)
	var assets:=Assets.new();assets.configure();var dead:=Assets.new();dead.configure(ProjectSettings.globalize_path("res://../runtime/assets/corpses/catalog.json"))
	var primary:=ProjectSettings.globalize_path("res://../runtime/assets/combat_population/mos_eisley_easy/catalog.json")
	for index in range(first,mini(first+count,templates.size())):
		var template:=str(templates[index]);var actor:=Actor.new();root.add_child(actor)
		var original:=actor.original_catalog(template,primary)
		var value:Dictionary={"id":"coverage-"+str(index),"kind":"creature","template":template,"name":template.get_file(),"position":[0,0,0],"heading_radians":0,"scale":1,"health":100,"max_health":100,"dead":false}
		var ok:=actor.configure(value,"offline-source-coverage",assets,dead,primary)
		var row:Dictionary={"template":template,"catalog":original,"status":actor.report.get("appearance_status","unavailable"),"missing_components":actor.report.get("missing_components",[]),"bones":0,"meshes":0,"source_outfit_parts":0,"loaded_outfit_parts":0,"original_incapacitated_pose":false}
		if not ok:errors.append(template+": projection initialization failed")
		if row.status=="unavailable":
			if actor.visual!=null or actor.collider!=null or actor.is_targetable():errors.append(template+": unavailable source acquired fabricated geometry/targetability")
			if not original.is_empty():errors.append(template+": imported descriptor could not construct any original geometry")
		else:
			var avatar=actor.visual;var bounds:AABB=actor.visual_bounds()
			row.bones=avatar.skeleton.get_bone_count();row.meshes=avatar.meshes.size();row.source_outfit_parts=avatar.race.get("default_outfit",[]).size();row.loaded_outfit_parts=avatar.loaded_parts.filter(func(part):return part.scope=="equipment").size()
			if row.bones<=0 or row.meshes<=0 or not bounds.position.is_finite() or not bounds.size.is_finite() or bounds.size.length()<=0.01:errors.append(template+": invalid original skinned bounds")
			if row.source_outfit_parts!=row.loaded_outfit_parts:errors.append(template+": CDF outfit records lost during construction")
			if not avatar.loaded_parts.all(func(part):return not part.model.get("parts",[]).is_empty()):errors.append(template+": imported source part contains no geometry records")
			if not avatar.meshes.all(func(mesh):return mesh.skin!=null and mesh.mesh!=null):errors.append(template+": missing original skin binding")
			if row.status=="partial" and row.missing_components.is_empty():errors.append(template+": unreported missing source components")
			if avatar.ensure_animation("idle"):avatar.animation_player.play("idle");avatar.animation_player.advance(0.0)
			row.original_incapacitated_pose=avatar.ensure_animation("incapacitated")
		rows.append(row);actor.queue_free();await process_frame
	var report:Dictionary={"passed":errors.is_empty(),"source_count":templates.size(),"start":first,"count":rows.size(),"actors":rows,"errors":errors,"gpu_tested":false,"headset_tested":false,"real_http_requests":0}
	var output:=str(args.get("out",ProjectSettings.globalize_path("res://../runtime/evidence/live-catalog-coverage-%04d.json"%first)))
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print(JSON.stringify({"passed":errors.is_empty(),"start":first,"count":rows.size(),"errors":errors}));quit(0 if errors.is_empty() else 1)
