extends SceneTree
class Actor extends StaticBody3D:
	var record:Dictionary={"id":"201","kind":"creature","relation":"hostile","dead":false,"incapacitated":false}
	var visual:Node3D
	func is_targetable()->bool:return not record.dead
	func core3_identity()->Dictionary:return {"id":record.id,"session_id":"fixture"}
	func visual_bounds()->AABB:return AABB(Vector3(-.3,0,-.2),Vector3(.6,1.8,.4))
var checks:=0
var errors:Array=[]
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:errors.append(label);push_error(label)
func _initialize()->void:call_deferred("run")
func punch(rig:Node3D,start:Vector3,direction:Vector3,side:="",trigger:=1.0,step:=.04)->void:
	var pose:=Transform3D(Basis(Vector3.UP,PI/2),start)
	if side.is_empty():rig.sample(.02,pose,pose,1,0,0,true,true)
	else:rig.sample_unarmed(.02,side,pose,true,"standing",0)
	for i in range(12):
		pose.origin=start+direction*step*i
		if side.is_empty():rig.sample(.02,pose,pose,1,0,trigger,true,true)
		else:rig.sample_unarmed(.02,side,pose,true,"standing",trigger)
func run()->void:
	var world:=Node3D.new();root.add_child(world)
	var body:=CharacterBody3D.new();world.add_child(body)
	var head:=Camera3D.new();world.add_child(head);head.position=Vector3(0,1.5,0)
	var catalog:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/assets/combat/catalog.json"))
	var profile:Dictionary=catalog.weapons.knife_survival.duplicate(true);profile.item_id="99";profile.certified=true;profile.abilities=[{"id":"knockdown_strike","activation":"native_melee","base_sac":{"health":0,"action":10,"mind":10},"max_range_m":4,"cooldown_seconds":20}];profile.ability_loadout={"slots":["knockdown_strike","","",""],"ultimate":""}
	var rig:=preload("res://combat/ranged_rig.gd").new();world.add_child(rig);check(rig.configure(head,body,[profile]),"Production melee rig configures");rig.set_process(false);rig.set_physics_process(false);rig.set_allowed(true);rig.draw(0);rig.weapons[0].state.ability_state=null
	rig.abilities.apply_authoritative({"ham":[1000,1000,1000],"max_ham":[1000,1000,1000],"wounds":[0,0,0]})
	var actor:=Actor.new();world.add_child(actor);actor.position=Vector3(0,0,-1.5);actor.collision_layer=8
	var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=actor.visual_bounds().size;shape.shape=box;shape.position=actor.visual_bounds().get_center();actor.add_child(shape)
	head.look_at(actor.global_position+Vector3.UP)
	await physics_frame;await physics_frame
	var ui:Node3D=rig.target_abilities
	rig.sample_ability_input(true,Vector2.ZERO,false,true)
	check(ui.target==actor and ui.points.size()==1 and not rig.ability_ui.menu_open,"Melee stick opens anatomical marker without circle")
	var point:Vector3=ui.points[0].position
	check(ui.melee_attack(point+Vector3(0,0,.15),point-Vector3(0,0,.15)).get("ability_id","")=="knockdown_strike","Physical segment crossing selects bound melee ability")
	check(ui.melee_attack(point+Vector3.UP,point+Vector3.UP*1.1).is_empty(),"Swing elsewhere cannot invoke marker")
	check(ui.melee_attack(point+Vector3(0,0,1),point-Vector3(0,0,1)).is_empty(),"Tracking teleport cannot cross marker")
	check(ui.melee_swing({"kind":"melee"},point+Vector3(0,0,.4),point+Vector3(0,0,.3),"weapon",.02).is_empty(),"Qualified swing waits briefly for marker contact")
	var result:Dictionary=ui.melee_swing({},point+Vector3(0,0,.15),point-Vector3(0,0,.15),"weapon",.02)
	check(result.get("ability_id","")=="knockdown_strike" and result.get("target_id","")=="201","Later marker contact retains target identity")
	check(ui.melee_swing({},point,point,"weapon",.02).is_empty(),"Holding weapon on marker cannot repeat special")
	ui.melee_swing({"kind":"melee"},point+Vector3.UP,point+Vector3.UP,"weapon",.02)
	ui.melee_swing({},point,point,"weapon",.02,false)
	check(ui.melee_swing({},point,point,"weapon",.02).is_empty(),"Input/tracking cancellation clears qualified swing")
	rig.abilities.cooldowns.knockdown_strike=2;ui.refresh();check(ui.points.is_empty(),"Cooldown hides melee marker");rig.abilities.cooldowns.clear()
	rig.abilities.ham[3]=1;ui.refresh();check(ui.points.is_empty(),"Insufficient SAC hides melee marker");rig.abilities.ham[3]=1000
	actor.record.melee_control_available=false;ui.refresh();check(ui.points.is_empty(),"Native shared control recovery hides melee special markers")
	actor.record.melee_control_available=true
	var wall:=StaticBody3D.new();world.add_child(wall);wall.position=Vector3(0,1,-.6);wall.collision_layer=1
	var wall_shape:=CollisionShape3D.new();var wall_box:=BoxShape3D.new();wall_box.size=Vector3(4,4,.1);wall_shape.shape=wall_box;wall.add_child(wall_shape)
	await physics_frame;await physics_frame;ui.refresh();check(ui.points.is_empty(),"Environment occlusion hides melee marker");wall.free()
	ui.refresh();point=ui.points[0].position
	var dispatched:Array=[]
	rig.shot_authority=func(shot,_pose,_grip):dispatched.append(shot.duplicate(true));return {}
	var muzzle_offset:Vector3=rig.melee_tip_local(0)
	var start_point:Vector3=point+Vector3(0,0,.55)
	var hand_pose:=Transform3D(Basis.IDENTITY,start_point-muzzle_offset)
	rig.sample(.02,hand_pose,hand_pose,1,0,0,true,true)
	for i in range(24):
		hand_pose.origin=start_point+Vector3(0,0,-.04*i)-muzzle_offset
		rig.sample(.02,hand_pose,hand_pose,1,0,1,true,true)
	check(dispatched.any(func(shot):return shot.get("ability_id","")=="knockdown_strike" and shot.get("target_id","")=="201"),"Actual qualified weapon swing routes marker special through shot authority")
	actor.position.z=-2.5;await physics_frame;await physics_frame
	dispatched.clear();ui.refresh();point=ui.points[0].position
	var fist_start:=Vector3(.2,1.2,-.15)
	var direction:Vector3=(point-fist_start).normalized()
	punch(rig,fist_start,direction)
	check(dispatched.size()==1 and dispatched[0].get("ability_id","")=="knockdown_strike" and dispatched[0].get("item_id","")=="99","Weapon-hand punch selects distant marker using held weapon identity")
	check((fist_start+direction*.44).distance_to(point)>.5,"Directional punch does not require physical marker contact")
	dispatched.clear();punch(rig,fist_start,direction,"",1,0)
	check(dispatched.is_empty(),"Stationary controller pointing cannot activate punch special")
	punch(rig,fist_start,direction,"",0)
	check(dispatched.is_empty(),"Punch without trigger readiness cannot activate special")
	punch(rig,fist_start,direction,"",1,.008)
	check(dispatched.is_empty(),"Slow hand movement cannot qualify a punch")
	ui.punch_history.clear()
	for i in range(8):ui.sample_punch("weapon",fist_start-direction*.04*i,.02,true)
	check(ui.punch_attack("weapon",fist_start-direction*.28).is_empty(),"Pulling fist back cannot project a punch at the marker")
	ui.punch_history.clear()
	for i in range(8):
		head.position.x+=.04
		ui.sample_punch("weapon",fist_start+Vector3(.04*(i+1),0,0),.02,true)
	check(ui.punch_attack("weapon",fist_start+Vector3(.32,0,0)).is_empty(),"Whole-body translation supplies no directional punch travel")
	head.position.x=0
	ui.punch_history.clear()
	for i in range(8):ui.sample_punch("weapon",fist_start+direction*.04*i,.02,true)
	ui.sample_punch("weapon",fist_start+direction*.32,.02,false)
	check(ui.punch_attack("weapon",fist_start+direction*.32).is_empty(),"Tracking or input cancellation discards punch history")
	for i in range(8):ui.sample_punch("weapon",fist_start+direction*.04*i,.02,true)
	ui.sample_punch("weapon",fist_start+direction*2,.02,true)
	check(ui.punch_attack("weapon",fist_start+direction*2).is_empty(),"Controller teleport discards punch history")
	for i in range(8):ui.sample_punch("weapon",fist_start+direction*.04*i,.02,true)
	ui.sample_punch("weapon",fist_start+direction*.32,.2,true)
	check(ui.punch_attack("weapon",fist_start+direction*.32).is_empty(),"Frame gap cannot retain a projected punch")
	for i in range(8):ui.sample_punch("weapon",fist_start+direction*.04*i+Vector3(.003 if i%2 else -.003,0,0),.02,true)
	check(ui.punch_attack("weapon",fist_start+direction*.28).get("ability_id","")=="knockdown_strike","Small hand jitter preserves intended marker selection")
	rig.abilities.cooldowns.knockdown_strike=2
	check(ui.punch_attack("weapon",fist_start+direction*.28).is_empty(),"Directional punch cannot bypass ability cooldown")
	rig.abilities.cooldowns.clear()
	actor.position.z=-1.5
	rig.stow();check(rig.configure_unarmed(catalog.unarmed),"Unarmed states configure")
	for state in rig.unarmed.values():
		state.ability_state=null
		state.profile.item_id="88";state.profile.abilities=[];state.profile.ability_loadout={"slots":["knockdown_strike","unarmed_stun","unarmed_blind",""],"ultimate":""}
		for id:String in ["knockdown_strike","unarmed_stun","unarmed_blind"]:state.profile.abilities.append({"id":id,"activation":"native_melee","base_sac":{"health":0,"action":10,"mind":10},"max_range_m":2,"cooldown_seconds":15})
	await physics_frame;await physics_frame
	rig.sample_ability_input(false,Vector2.ZERO,false,true);rig.sample_ability_input(true,Vector2.ZERO,false,true)
	check(ui.points.size()==3,"Unarmed stick presents knockdown, stun and blind markers")
	if not ui.points.is_empty():
		var p:Vector3=ui.points[0].position
		check(not ui.melee_attack(p+Vector3(0,0,.1),p-Vector3(0,0,.1)).is_empty(),"Unarmed punch contact uses same marker path")
	for side:String in ["left","right"]:
		for id:String in ["knockdown_strike","unarmed_stun","unarmed_blind"]:
			ui.refresh()
			var marker:Vector3=ui.points.filter(func(row):return row.ability.id==id)[0].position
			fist_start=Vector3(-.2 if side=="left" else .2,1.2,-.15)
			dispatched.clear();punch(rig,fist_start,(marker-fist_start).normalized(),side)
			check(dispatched.size()==1 and dispatched[0].get("ability_id","")==id and dispatched[0].get("target_id","")=="201" and dispatched[0].get("hand","")==side,"%s fist reliably selects %s without reaching marker"%[side,id])
	for state in rig.unarmed.values():
		state.profile.ability_loadout.slots[3]="challenging_strike"
		state.profile.abilities.append({"id":"challenging_strike","activation":"native_melee","requires_control_available":false,"base_sac":{"health":0,"action":40,"mind":20},"sac_policy":"fixed","max_range_m":2,"cooldown_seconds":15})
	actor.record.melee_control_available=false;ui.refresh()
	check(ui.points.size()==1 and ui.points[0].ability.id=="challenging_strike","Challenging Strike remains available during enemy control immunity")
	dispatched.clear();fist_start=Vector3(.2,1.2,-.15)
	punch(rig,fist_start,(ui.points[0].position-fist_start).normalized(),"right")
	check(dispatched.size()==1 and dispatched[0].get("ability_id","")=="challenging_strike","Physical punch targets the TKA threat strike")
	check(rig.abilities.costs({"base_sac":{"health":0,"action":40,"mind":20},"sac_policy":"fixed"})==[0.0,40.0,20.0],"Fixed threat-strike SAC is not discounted by legacy attributes")
	actor.record.melee_control_available=true
	actor.position.z=-3;await physics_frame;await physics_frame;ui.refresh();check(ui.points.is_empty(),"Unarmed reach excludes distant target")
	world.free();await process_frame
	var report:Dictionary={"checks":checks,"errors":errors,"renderer":"dummy","tracking":"mocked","native_transport":"mocked"};FileAccess.open("res://../runtime/evidence/brawler-targeting.json",FileAccess.WRITE).store_string(JSON.stringify(report));print(JSON.stringify(report));quit(0 if errors.is_empty() else 1)
