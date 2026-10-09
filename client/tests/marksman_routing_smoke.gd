extends SceneTree
const Rig=preload("res://combat/ranged_rig.gd")
const Live=preload("res://combat/live_world.gd")
class Host extends Node:
	func source_position_at(p:Vector3)->Vector3:return Vector3(p.x,p.y,-p.z)
class Actor extends StaticBody3D:
	var record:Dictionary={"id":"201","kind":"creature","relation":"hostile","dead":false,"incapacitated":false,"health":1000,"boss":false,"level":50,"melee_control_available":true}
	var visual:Node3D
	func is_targetable()->bool:return not record.dead
	func core3_identity()->Dictionary:return {"id":record.id,"session_id":"marksman-session"}
	func visual_bounds()->AABB:return AABB(Vector3(-.4,0,-.3),Vector3(.8,1.8,.6))
var checks:=0
var errors:Array=[]
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:errors.append(label);push_error(label)
func _initialize()->void:call_deferred("run")
func pose(from:Vector3,to:Vector3)->Transform3D:return Transform3D(Basis.looking_at((to-from).normalized()),from)
func run()->void:
	var catalog:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/assets/combat/catalog.json"))
	for family:String in ["pistol_fwg5","carbine_cdef"]:
		var world:=Node3D.new();root.add_child(world)
		var body:=CharacterBody3D.new();world.add_child(body)
		var head:=Camera3D.new();world.add_child(head);head.position=Vector3(0,1.6,0)
		var profile:Dictionary=catalog.weapons[family].duplicate(true);profile.item_id="99";profile.certified=true;profile.abilities=[]
		var special:="bleeding_shot" if family=="pistol_fwg5" else "controlled_burst"
		var ids:Array=["suppression_fire","warning_shot",special,"lethal_shot"]
		profile.ability_loadout={"family":"pistols" if family=="pistol_fwg5" else "carbines","slots":ids.duplicate(),"ultimate":""}
		for id:String in ids:
			profile.abilities.append({"id":id,"label":id,"activation":"native_ranged","ultimate":false,"sac_policy":"fixed","base_sac":{"health":0,"action":75,"mind":20},"cooldown_seconds":18,"max_range_m":float(profile.core3.maxRange),"requires_control_available":id in ["suppression_fire","warning_shot"],"excludes_bosses":id=="warning_shot","conditions_met":true})
		var rig:=Rig.new();world.add_child(rig);check(rig.configure(head,body,[profile]),"Configure "+family)
		rig.set_process(false);rig.set_physics_process(false);rig.set_allowed(true);rig.draw(0);rig.two_hands=true;rig.weapons[0].state.ability_state=null
		rig.abilities.apply_authoritative({"ham":[1000,1000,1000],"max_ham":[1000,1000,1000],"wounds":[0,0,0]})
		var live:=Live.new();world.add_child(live);live.set_process(false);live.rig=rig;live.app=Host.new();world.add_child(live.app);live.player=body;live.live=true;live.native_ready=true;live.session_id="marksman-session";live.owner_account="fixture";live.owner_character="1"
		live.weapon={"item_id":"99","certified":true,"max_range_m":float(profile.core3.maxRange),"projectile_speed":100.,"fire_interval_seconds":1.,"abilities":profile.abilities,"ability_loadout":profile.ability_loadout.duplicate(true)}
		var actor:=Actor.new();world.add_child(actor);actor.position=Vector3(0,0,-8);actor.collision_layer=8
		var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=actor.visual_bounds().size;shape.shape=box;shape.position=actor.visual_bounds().get_center();actor.add_child(shape);live.actors["201"]=actor
		await physics_frame;await physics_frame
		var ui:Node3D=rig.target_abilities
		var gun:=Vector3(0,1.2,-.2)
		ui.toggle(pose(gun,actor.global_position+Vector3.UP))
		check(ui.points.size()==4,"Four equipped markers on "+family)
		for point:Dictionary in ui.points.duplicate():
			var request:Dictionary=ui.attack(pose(gun,point.position))
			check(request.get("ability_id","")==point.ability.id and request.get("target_id","")=="201","Physical marker resolves "+str(point.ability.id))
			var shot:Dictionary={"item_id":"99","kind":"ranged","speed":100.,"range_scale":rig.weapons[0].state.range_scale(true),"two_hands":true,"firing_posture":"standing"};shot.merge(request)
			var registered:Dictionary=live.register_shot(shot,pose(gun,actor.global_position+Vector3.UP),Vector3.ZERO)
			check(not registered.is_empty() and live.queue.size()==1 and live.queue[0].payload.ability_id==point.ability.id,"Native fire routing "+str(point.ability.id))
			if registered.is_empty():continue
			check(not live.queue[0].payload.has("damage") and not live.queue[0].payload.has("hit_count"),"Server owns burst count and damage")
			live.contact(registered,actor.core3_identity(),actor.global_position+Vector3.UP,Vector3.BACK,8)
			live.contact(registered,actor.core3_identity(),actor.global_position+Vector3.UP,Vector3.BACK,8)
			check(live.queue.size()==2 and live.queue[1].kind=="impact" and actor.record.health==1000,"Exactly one contact receipt; no local damage")
			live.next_launch_usec=0
			check(live.register_shot(shot,pose(gun,actor.global_position+Vector3.UP),Vector3.ZERO).is_empty(),"Cooldown blocks repeat")
			live.rejected_fire(registered.shot_id);check(float(rig.abilities.cooldowns.get(str(point.ability.id),-1))==0,"Rejected launch rolls back cooldown")
			live.queue.clear();live.shots.clear();live.next_launch_usec=0
		actor.record.melee_control_available=false;ui.refresh();check(ui.points.size()==2,"Ranged controls share melee control recovery")
		actor.record.melee_control_available=true;actor.record.boss=true;ui.refresh();check(ui.points.size()==3 and not ui.points.any(func(p):return p.ability.id=="warning_shot"),"Boss removes Warning Shot")
		actor.record.boss=false;actor.record.ability_target_available={special:false};ui.refresh();check(ui.points.size()==3,"Native immunity hides marker")
		actor.record.ability_target_available={};rig.abilities.ham[3]=75;ui.refresh();check(ui.points.is_empty(),"Exact Action cost is unaffordable")
		rig.abilities.ham[3]=1000;rig.abilities.ham[6]=20;ui.refresh();check(ui.points.is_empty(),"Exact Mind cost is unaffordable")
		rig.abilities.ham[6]=1000;rig.weapons[0].state.profile.ability_loadout.slots[2]="";ui.refresh();check(ui.points.size()==3,"Unequipped ability hidden")
		rig.weapons[0].state.profile.ability_loadout.slots[2]=special
		var range_m:float=profile.core3.maxRange
		actor.position.z=-range_m*(1.05 if family=="pistol_fwg5" else .5)
		rig.two_hands=false;check(not ui.ability_ready(profile.abilities[2],actor),"One-hand range respected")
		rig.two_hands=true;check(ui.ability_ready(profile.abilities[2],actor),"Two-hand range respected")
		check(ui.attack(pose(gun,actor.global_position+Vector3.UP),true).is_empty(),"Marksman has no ultimate")
		world.free();await process_frame
	var report:Dictionary={"passed":errors.is_empty(),"checks":checks,"errors":errors,"native_transport":"mocked","renderer":"dummy","live_xr":false}
	FileAccess.open("res://../runtime/evidence/marksman-routing-client.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "));print(JSON.stringify(report));quit(0 if errors.is_empty() else 1)
