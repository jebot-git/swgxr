extends SceneTree
const Avatar=preload("res://scripts/avatar.gd")
const Actor=preload("res://combat/live_actor.gd")
var errors:Array=[]
func _initialize()->void:call_deferred("run")
func run()->void:
	var rows:Array=[];var families:Dictionary={}
	var profiles:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/assets/combat_actions/catalog.json"))
	for source:String in profiles.catalogs:
		var path:=ProjectSettings.globalize_path("res://../"+source)
		var catalog:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path))
		for template:String in catalog.races:
			var profile:Dictionary=profiles.templates.get(template,{})
			if profile.is_empty() or families.has(profile.family):continue
			families[profile.family]=true
			var slot:String=profile.profiles.keys()[0]
			var base:Dictionary=profile.profiles[slot]
			rows.append([path,template,base.animation,float(base.duration),base.get("visual_fallback",false)])
			var bindings:Dictionary=profiles.special_bindings.get(profile.family,{})
			if not bindings.is_empty():
				var special:Dictionary=profiles.special_profiles[bindings.values()[0]]
				rows.append([path,template,special.animation,float(special.duration),false])
	if families.size()!=int(profiles.families):errors.append("Missing prepared families")
	for row in rows:
		var actor:=Actor.new();root.add_child(actor);actor.set_process(false);actor.record={"dead":false}
		var avatar:=Avatar.new();actor.add_child(avatar);avatar.load_catalog(str(row[0]));avatar.configure(row[1]);actor.visual=avatar
		var event:Dictionary={"animation":row[2],"attack_id":"1","encounter_id":"1","phase":"windup","server_now":10.,"age_ms":0.,"delivery_at":11.,"active_at":11.,"animation_end_at":11.+float(row[3]),"role":"support"}
		var now:=Time.get_ticks_usec()/1000000.0;actor.action_pose.ingest(event,now);actor.present_action_pose()
		var first:=bones(avatar);actor.action_pose.local_anchor=Time.get_ticks_usec()/1000000.0-.8;actor.present_action_pose()
		if not same(first,bones(avatar)):errors.append(str(row[1])+" "+str(row[2])+" first frame changed during hold")
		var animated:=false
		for fraction:float in [.1,.25,.5,.75,.9]:
			actor.action_pose.local_anchor=Time.get_ticks_usec()/1000000.0-1.-float(row[3])*fraction;actor.present_action_pose()
			animated=animated or not same(first,bones(avatar))
		if not animated and not row[4]:errors.append(str(row[1])+" "+str(row[2])+" original skeleton did not animate")
		if actor.global_transform!=Transform3D.IDENTITY:errors.append("Animation moved native actor transform")
		# The native preparation event deliberately owns the planted NPC pose.
		# Skeletal playback must preserve it; no tracked/player transform is used.
		var native_pose:=Transform3D(Basis(Vector3.UP,-.15),Vector3(2,0,3))
		actor.action_pose.event["_world_pose"]=native_pose;actor.present_action_pose()
		if not actor.global_transform.is_equal_approx(native_pose):errors.append("Body did not follow native warning aim")
		actor.action_pose.local_anchor=Time.get_ticks_usec()/1000000.0-1.-float(row[3])*.7;actor.present_action_pose()
		if not actor.global_transform.is_equal_approx(native_pose):errors.append("Animation moved planted native pose")
		actor.action_pose.local_anchor=Time.get_ticks_usec()/1000000.0-2.-float(row[3])
		if actor.present_action_pose():errors.append("Clip did not release locomotion")
		actor.free()
	var report:={"passed":errors.is_empty(),"errors":errors,"original_rigs":rows.size(),"families":families.size(),"renderer":"dummy","headset_tested":false}
	FileAccess.open("res://../runtime/evidence/global-ground-rig-smoke.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print(JSON.stringify(report));quit(0 if errors.is_empty() else 1)
func bones(avatar:Node)->Array:
	var result:Array=[]
	for index in avatar.skeleton.get_bone_count():result.append(avatar.skeleton.get_bone_pose(index))
	return result
func same(a:Array,b:Array)->bool:
	for i in a.size():
		if not a[i].is_equal_approx(b[i]):return false
	return true
