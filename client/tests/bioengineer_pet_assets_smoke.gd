extends SceneTree
## Offline original models and clips; no native pet AI or GPU validation.
const Actor=preload("res://combat/live_actor.gd")
const Avatar=preload("res://scripts/avatar.gd")
var errors:Array[String]=[]
var checks:=0
func check(value:bool,message:String)->void:
	checks+=1
	if not value:errors.append(message);push_error(message)
func _initialize()->void:call_deferred("run")
func run()->void:
	var index:=Avatar.read_json(ProjectSettings.globalize_path("res://../runtime/assets/bioengineer/appearance_catalogs.json"))
	check(index.get("missing",["index missing"]).is_empty() and index.get("catalogs",{}).size()==69,"All original crafted creature appearances prepared")
	var selector:=Actor.new()
	for template:String in index.get("catalogs",{}):
		var path:=selector.original_catalog(template,"")
		check(not path.is_empty(),"Actor resolves original crafted creature: "+template)
		if path.is_empty():continue
		var avatar:=Avatar.new();root.add_child(avatar);avatar.load_catalog(path)
		var result:Dictionary=avatar.configure(template)
		check(str(result.get("error","")).is_empty() and avatar.skeleton!=null and not avatar.meshes.is_empty(),"Original skeleton and mesh load: "+template)
		for state in ["idle","walk","run"]:
			check(avatar.ensure_animation(state),"Original "+state+" clip: "+template)
			if avatar.animation_player!=null and avatar.animation_player.has_animation(state):
				avatar.animation_player.play(state);avatar.animation_player.advance(0.1)
				check(avatar.skeleton.get_bone_global_pose(0).is_finite(),"Finite original animated pose: "+template)
		avatar.free();await process_frame
	selector.free()
	var report:Dictionary={"passed":errors.is_empty(),"checks":checks,"errors":errors,"live_core3":false,"gpu_validation":false}
	FileAccess.open("res://../runtime/evidence/bioengineer-pet-assets-smoke.json",FileAccess.WRITE).store_string(JSON.stringify(report));print(JSON.stringify(report));quit(0 if errors.is_empty() else 1)
