extends SceneTree
const Avatar=preload("res://scripts/avatar.gd")
const Actor=preload("res://combat/live_actor.gd")
var errors:Array=[]
func _initialize()->void:call_deferred("run")
func run()->void:
	var rows:Array=[["combat_population/mos_eisley_easy","object/mobile/worrt_hue.iff","action_worrt",.5],["ambient_npcs","object/mobile/dressed_commoner_tatooine_rodian_female_01.iff","action_pistol",1.],["ambient_npcs","object/mobile/dressed_commoner_tatooine_rodian_female_01.iff","action_heal",80./30.]]
	var profiles:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/assets/combat_actions/catalog.json"))
	var repaired:=0
	for folder in ["combat_population/tatooine_entities","ambient_npcs"]:
		var catalog:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/assets/"+folder+"/catalog.json"))
		for template in catalog.races:
			var profile:Dictionary=profiles.templates.get(template,{}).get("profiles",{}).get("unarmed",{})
			if profile.has("selection_basis"):
				rows.append([folder,template,"action_ground_unarmed",float(profile.duration)]);repaired+=1
	if repaired!=14:errors.append("Expected all 14 repaired droid templates, found "+str(repaired))
	for row in rows:
		var actor:=Actor.new();root.add_child(actor);actor.set_process(false);actor.record={"dead":false}
		var avatar:=Avatar.new();actor.add_child(avatar);avatar.load_catalog(ProjectSettings.globalize_path("res://../runtime/assets/"+str(row[0])+"/catalog.json"));avatar.configure(row[1]);actor.visual=avatar
		var event:Dictionary={"animation":row[2],"attack_id":"1","encounter_id":"1","phase":"windup","server_now":10.,"age_ms":0.,"delivery_at":11.,"active_at":11.,"animation_end_at":11.+float(row[3]),"role":"support"}
		var now:=Time.get_ticks_usec()/1000000.0;actor.action_pose.ingest(event,now);actor.present_action_pose()
		var first:=bones(avatar);actor.action_pose.local_anchor=now-.8;actor.present_action_pose()
		if not same(first,bones(avatar)):errors.append(str(row[2])+" first frame changed during hold")
		actor.action_pose.local_anchor=now-1.-float(row[3])*.5;actor.present_action_pose()
		if same(first,bones(avatar)):errors.append(str(row[2])+" original skeleton did not animate")
		if actor.global_transform!=Transform3D.IDENTITY:errors.append("Animation moved native actor transform")
		# The native preparation event deliberately owns the planted NPC pose.
		# Skeletal playback must preserve it; no tracked/player transform is used.
		var native_pose:=Transform3D(Basis(Vector3.UP,-.15),Vector3(2,0,3))
		actor.action_pose.event["_world_pose"]=native_pose;actor.present_action_pose()
		if not actor.global_transform.is_equal_approx(native_pose):errors.append("Body did not follow native warning aim")
		actor.action_pose.local_anchor=now-1.-float(row[3])*.7;actor.present_action_pose()
		if not actor.global_transform.is_equal_approx(native_pose):errors.append("Animation moved planted native pose")
		actor.action_pose.local_anchor=now-2.-float(row[3])
		if actor.present_action_pose():errors.append("Clip did not release locomotion")
		actor.free()
	print(JSON.stringify({"passed":errors.is_empty(),"errors":errors,"original_rigs":rows.size(),"repaired_droid_templates":repaired,"renderer":"dummy","headset_tested":false}));quit(0 if errors.is_empty() else 1)
func bones(avatar:Node)->Array:
	var result:Array=[]
	for index in avatar.skeleton.get_bone_count():result.append(avatar.skeleton.get_bone_pose_rotation(index))
	return result
func same(a:Array,b:Array)->bool:
	for i in a.size():
		if a[i].angle_to(b[i])>.001:return false
	return true
