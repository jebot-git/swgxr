extends SceneTree
const Targets=preload("res://combat/target_abilities.gd")
const Chord=preload("res://combat/ultimate_input.gd")
class Actor extends StaticBody3D:
	var record:Dictionary={"id":"201","kind":"creature","relation":"hostile","dead":false,"incapacitated":false}
	var visual:Node3D
	func is_targetable()->bool:return not record.dead
	func core3_identity()->Dictionary:return {"id":record.id,"session_id":"fixture"}
	func visual_bounds()->AABB:return AABB(Vector3(-.4,0,-.3),Vector3(.8,1.8,.6))
var checks:=0
var errors:Array[String]=[]
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:errors.append(label);push_error(label)
func _initialize()->void:
	create_timer(60).timeout.connect(func():quit(2));call_deferred("run")
func pose(from:Vector3,to:Vector3)->Transform3D:return Transform3D(Basis.looking_at((to-from).normalized()),from)
func run()->void:
	for hz in [45.0,72.0,90.0,120.0]:
		for mode in ["together","main_first","support_first","main_only","one_hand","untracked","held_on_grip"]:
			var chord:=Chord.new();var ultimates:=0;var ordinary_edges:=0;var down:=false
			if mode!="held_on_grip":chord.sample(1/hz,0,0,true,true)
			for i in range(int(hz*.7)):
				var t:float=i/hz
				var main:=1.0 if mode!="support_first" or t>=.045 else 0.0
				var support:=0.0 if mode=="main_only" else 1.0 if mode!="main_first" or t>=.045 else 0.0
				var input:=chord.sample(1/hz,main,support,mode!="one_hand",mode!="untracked")
				if input.ultimate:ultimates+=1
				if input.trigger>=.75 and not down:ordinary_edges+=1
				down=input.trigger>=.75
			check(ultimates==(1 if mode in ["together","main_first","support_first"] else 0),"One ultimate with fresh dual-trigger chord: %s / %s Hz"%[mode,hz])
			check(ordinary_edges==(1 if mode in ["main_only","one_hand"] else 0),"No ordinary shot before or after ultimate chord: %s / %s Hz"%[mode,hz])
	var chord:=Chord.new();chord.sample(.01,0,0,true,true);chord.sample(.01,1,1,true,true)
	check(chord.sample(.01,1,1,false,true).trigger==0,"Separating support hand after ultimate cannot fabricate ordinary trigger edge")
	chord.sample(.01,0,0,false,true);chord.sample(.01,0,0,true,true)
	check(chord.sample(.01,1,1,true,true).ultimate,"Observed released triggers rearm a later ultimate")
	var world:=Node3D.new();root.add_child(world)
	var body:=CharacterBody3D.new();world.add_child(body)
	var head:=Camera3D.new();world.add_child(head);head.position=Vector3(0,1.5,0)
	var catalog:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/combat/catalog.json"))
	var profile:Dictionary=catalog.weapons.pistol_fwg5.duplicate(true);profile.item_id="99";profile.source_kind="core3_weapon_instance";profile.certified=true;profile.abilities=[]
	for id:String in ["concussion_shot_improved","lethal_shot","low_blow","restraining_shot","last_ditch"]:
		profile.abilities.append({"id":id,"activation":"native_ranged","base_sac":{"health":0,"action":10,"mind":10},"cooldown_seconds":30,"max_range_m":40,"conditions_met":true})
	profile.ability_loadout={"family":"pistols","slots":["concussion_shot_improved","lethal_shot","low_blow","restraining_shot"],"ultimate":"last_ditch","revision":1}
	var rig:=preload("res://combat/ranged_rig.gd").new();world.add_child(rig)
	check(rig.configure(head,body,[profile]),"Production rig loads original gun")
	rig.set_process(false);rig.set_physics_process(false);rig.set_allowed(true);rig.draw(0);rig.weapons[0].state.ability_state=null
	rig.abilities.apply_authoritative({"ham":[1000,1000,1000],"max_ham":[1000,1000,1000],"wounds":[0,0,0]})
	var actor:=Actor.new();world.add_child(actor);actor.position=Vector3(0,0,-8);actor.collision_layer=8
	var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=actor.visual_bounds().size;shape.shape=box;shape.position=actor.visual_bounds().get_center();actor.add_child(shape)
	var gun_origin:=Vector3(0,1.2,-.2)
	rig.weapons[0].visual.global_transform=pose(gun_origin,actor.global_position+Vector3.UP)
	await physics_frame;await physics_frame
	var ui:Node3D=rig.target_abilities
	rig.sample_ability_input(true,Vector2.ZERO,false,true)
	check(ui.target==actor and ui.points.size()==4 and not rig.ability_ui.menu_open and not rig.abilities.primed,"Weapon joystick click opens four local body markers without circle or priming")
	rig.sample_ability_input(false,Vector2.ZERO,true,true)
	check(not rig.abilities.primed,"A cannot prime a ranged ability")
	var basis:Basis=ui.points[0].basis;var depth:float=ui.points[0].position.dot(basis.z)
	check(ui.points.all(func(point):return absf(point.position.dot(basis.z)-depth)<.0001),"All body markers share one world-space target-depth plane")
	var positions:Dictionary={}
	for point:Dictionary in ui.points:positions[point.ability.id]=point.position
	check(positions.concussion_shot_improved.y>positions.lethal_shot.y and positions.lethal_shot.y>positions.low_blow.y and positions.low_blow.y>positions.restraining_shot.y,"Head/heart/pelvis/knees retain anatomical ordering")
	check(ui.widgets.values().all(func(widget):return not widget.get_child(0).material_override.no_depth_test),"Markers use depth testing, not through-wall rendering")
	for point:Dictionary in ui.points:
		var request:Dictionary=ui.attack(pose(gun_origin,point.position))
		check(request.get("ability_id","")==point.ability.id and request.get("target_id","")=="201","Shooting marker selects its ability and fixed actor: "+str(point.ability.id))
	check(ui.attack(pose(gun_origin,actor.global_position+Vector3.UP),true).get("ability_id","")=="last_ditch","Both-trigger action resolves Last Ditch directly against aimed actor")
	rig.weapons[0].state.profile.ability_loadout.slots[0]="";ui.refresh()
	check(ui.points.size()==3 and not ui.points.any(func(point):return point.ability.id=="concussion_shot_improved"),"Unequipped learned ability has no target marker")
	rig.weapons[0].state.profile.ability_loadout.ultimate=""
	check(ui.attack(pose(gun_origin,actor.global_position+Vector3.UP),true).is_empty(),"Dual-trigger chord cannot invoke an unequipped ultimate")
	rig.weapons[0].state.profile.ability_loadout.slots[0]="concussion_shot_improved";rig.weapons[0].state.profile.ability_loadout.ultimate="last_ditch";ui.refresh()
	for id:String in Targets.POINTS:
		rig.abilities.cooldowns[id]=1;ui.refresh()
		check(not ui.points.any(func(point):return point.ability.id==id),"Recovering ability marker disappears: "+id)
		rig.abilities.cooldowns.clear()
	rig.abilities.ham[3]=5;ui.refresh();check(ui.points.is_empty(),"Insufficient Action suppresses all unaffordable markers")
	rig.abilities.ham[3]=1000;rig.abilities.ham[6]=5;ui.refresh();check(ui.points.is_empty(),"Insufficient Mind suppresses markers")
	rig.abilities.ham[6]=1000
	rig.weapons[0].state.profile.abilities[0].conditions_met=false;ui.refresh();check(ui.points.size()==3,"Native state prerequisites filter individual marker")
	rig.weapons[0].state.profile.abilities[0].conditions_met=true
	var maximum:float=rig.weapons[0].state.core.maxRange;rig.weapons[0].state.core.maxRange=2;ui.refresh();check(ui.points.is_empty(),"Weapon range suppresses all markers")
	rig.weapons[0].state.core.maxRange=maximum
	rig.weapons[0].state.profile.abilities[0].max_range_m=2;ui.refresh();check(ui.points.size()==3,"Ability-specific range filters its marker")
	rig.weapons[0].state.profile.abilities[0].max_range_m=40
	var wall:=StaticBody3D.new();world.add_child(wall);wall.collision_layer=1;wall.position=Vector3(0,1,-4)
	var wall_shape:=CollisionShape3D.new();var wall_box:=BoxShape3D.new();wall_box.size=Vector3(4,4,.15);wall_shape.shape=wall_box;wall.add_child(wall_shape)
	await physics_frame;await physics_frame
	ui.refresh();check(ui.points.is_empty() and ui.acquire(pose(gun_origin,actor.global_position+Vector3.UP))==null,"Scenery blocks both acquisition and existing markers")
	wall.free();await physics_frame;await physics_frame
	actor.position.x=1;await physics_frame;await physics_frame;ui.refresh()
	check(ui.points.size()==4 and ui.points[0].position.x>positions.concussion_shot_improved.x+.5,"Markers follow moving actor, not a stale screen position")
	actor.record.relation="friendly";ui.refresh();check(ui.target==null and ui.points.is_empty(),"Newly ineligible actor closes overlay")
	actor.record.relation="hostile";ui.toggle(pose(gun_origin,actor.global_position+Vector3.UP))
	var dispatched:Array=[]
	rig.shot_authority=func(shot,_pose,_grip):dispatched.append(shot.duplicate(true));return {}
	var point:Dictionary=ui.points[0]
	var main_pose:=pose(gun_origin,point.position)
	for i in range(3):main_pose.basis=Basis.looking_at((point.position-main_pose*rig.assets.muzzle(str(profile.id))).normalized())
	rig.sample(.01,main_pose,main_pose,1,0,0,true,true)
	rig.sample(.01,main_pose,main_pose,1,0,1,true,true)
	check(dispatched.size()==1 and dispatched[0].get("ability_id","")==point.ability.id and dispatched[0].get("target_id","")=="201","Production weapon trigger routes marker ability and bound actor through shot authority")
	dispatched.clear();rig.weapons[0].state.next_shot=0
	main_pose=pose(gun_origin,actor.global_position+Vector3.UP)
	rig.sample(.01,main_pose,main_pose,1,0,0,true,true)
	rig.sample(.01,main_pose,main_pose,1,1,0,true,true)
	rig.sample(.01,main_pose,main_pose,1,1,1,true,true,false,1)
	for i in range(100):rig.sample(.01,main_pose,main_pose,1,1,1,true,true,false,1)
	check(dispatched.size()==1 and dispatched[0].get("ability_id","")=="last_ditch" and dispatched[0].get("target_id","")=="201","Production two-hand both-trigger chord dispatches exactly one Last Ditch without an ordinary shot")
	rig.stow();check(ui.target==null,"Stowing weapon clears target")
	world.free();await process_frame
	var report:Dictionary={"passed":errors.is_empty(),"checks":checks,"errors":errors,"tracking":"mocked","native_transport":"mocked","renderer":"dummy","live_xr":false}
	FileAccess.open("res://../runtime/evidence/target-abilities-client.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "));print(JSON.stringify(report));quit(0 if errors.is_empty() else 1)
