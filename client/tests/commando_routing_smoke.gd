extends SceneTree
const Rig=preload("res://combat/ranged_rig.gd")
const Gameplay=preload("res://multiplayer/gameplay_combat.gd")
class Host extends Node:
	var player:CharacterBody3D
	var stage:Node3D
	var datapad_account:="commando"
	var datapad_character_id:="1"
	var session_leaving:=false
	var world_ready:=true
	var reject:=false
	var calls:Array=[]
	var delay:=0.0
	func source_position_at(p:Vector3)->Vector3:return Vector3(p.x,p.y,-p.z)
	func api(_method:HTTPClient.Method,path:String,payload:Dictionary)->Dictionary:
		calls.append({"path":path,"payload":payload.duplicate(true)})
		if delay>0:await get_tree().create_timer(delay).timeout
		else:await get_tree().process_frame
		return {"mutation":{"success":not reject,"shot_id":payload.shot_id,"ability_id":payload.get("ability_id",""),"interval_seconds":.25,"damage":90}}
class Session extends Node:
	var live:=true
	var busy:=false
	var character_id:="1"
	var session_id:="commando-session"
	var sequence:=1
	var player_state:Dictionary={}
	var weapon_state:Dictionary={}
	var pending_transport:Dictionary={}
	var life_action_pending:=""
	var last_confirmed_ms:=Time.get_ticks_msec()
	var last_error:=""
	func authority_expired()->bool:return false
	func accept_native_response(_response:Dictionary)->bool:sequence+=1;last_confirmed_ms=Time.get_ticks_msec();return true
class Entities extends Node:
	var actors:Dictionary={}
class Sync extends Node:
	var entities:Entities
class Actor extends StaticBody3D:
	var snapshot_usec:=Time.get_ticks_usec()
	var session_id:="commando-session"
	var record:Dictionary={"id":"201","kind":"creature","relation":"hostile","dead":false,"incapacitated":false,"health":1000,"boss":false,"level":50,"melee_control_available":true,"knockdown_available":true}
	var visual:Node3D
	func is_targetable()->bool:return not record.dead
	func core3_identity()->Dictionary:return {"id":record.id,"session_id":"commando-session"}
	func visual_bounds()->AABB:return AABB(Vector3(-.4,0,-.3),Vector3(.8,1.8,.6))
var checks:=0
var errors:Array=[]
var rig:Node3D
var live:Node3D
var app:Host
var session:Session
var actor:Actor
var profiles:Array=[]
var head:Camera3D
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:errors.append(label);push_error(label)
func _initialize()->void:create_timer(30).timeout.connect(func():quit(2));call_deferred("run")
func equip(index:int)->void:
	live.queue.clear();live.shots.clear();live.next_launch_usec=0;rig.abilities.cooldowns.clear();rig.rounds_sim.clear();app.reject=false
	rig.draw(index);rig.main_grip_down=true;rig.support_grip_down=true;rig.support_latched=true;rig.two_hands=true
	var state=rig.weapons[index].state
	state.rounds=int(state.profile.capacity);state.reload_until=-1;state.next_shot=0;state.block()
	var profile:Dictionary=profiles[index].duplicate(true)
	session.weapon_state=profile.duplicate(true);session.weapon_state.merge({"kind":"ranged","certified":true,"fire_interval_seconds":60./float(profile.rpm),"max_range_m":float(profile.core3.maxRange),"projectile_speed":45.,"charges":40 if profile.charge_limited else -1,"conditions_met":true},true)
	session.player_state={"ham":[3000,1000,1000],"commando":{"overdrive":{"learned":true,"conditions_met":true,"active":false,"cooldown_remaining_seconds":0,"cooldown_seconds":120,"action_cost":80,"mind_cost":40,"interval_seconds":.25}}}
	session.last_confirmed_ms=Time.get_ticks_msec();live.refresh_authority()
	rig.abilities.apply_authoritative({"ham":[3000,1000,1000],"max_ham":[3000,1000,1000],"wounds":[0,0,0]})
func discharge(ability:="")->bool:
	var state=rig.weapons[rig.selected].state
	if not state.reserve_rounds(1):return false
	var shot:Dictionary=state.ranged_snapshot(true,"standing")
	if not ability.is_empty():shot.merge({"ability_id":ability,"target_id":"201","aim_point":actor.global_position+Vector3.UP})
	var pose:=Transform3D(Basis.IDENTITY,Vector3(0,1,-.4))
	return rig.dispatch_shot(shot,pose,pose.origin,state.profile,false)
func run()->void:
	var world:=Node3D.new();root.add_child(world)
	head=Camera3D.new();world.add_child(head);head.position=Vector3(0,1.7,0)
	var body:=CharacterBody3D.new();world.add_child(body)
	var catalog:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/assets/combat/catalog.json"))
	profiles=[]
	for key:String in ["rifle_flame_thrower","rifle_acid_beam","heavy_particle_beam","heavy_acid_beam","heavy_lightning_beam","heavy_rocket_launcher","pistol_launcher"]:
		var profile:Dictionary=catalog.weapons[key].duplicate(true);profile.item_id=str(99+profiles.size());profile.certified=true
		profile.abilities=[{"id":"focused_discharge","activation":"native_ranged","conditions_met":true,"sac_policy":"fixed","base_sac":{"health":0,"action":60,"mind":20},"interval_seconds":1.,"cooldown_seconds":12.,"ammo_cost":1,"max_range_m":float(profile.core3.maxRange)}]
		if key=="rifle_acid_beam":profile.abilities.append({"id":"acid_spray","activation":"native_ranged","conditions_met":true,"sac_policy":"fixed","base_sac":{"health":0,"action":60,"mind":20},"interval_seconds":1.,"cooldown_seconds":6.,"ammo_cost":1,"max_range_m":14.})
		profile.abilities.append({"id":"overdrive","activation":"commando_ultimate","ultimate":true})
		profile.ability_loadout={"family":"heavy","slots":["focused_discharge","acid_spray","",""],"ultimate":"overdrive"};profiles.append(profile)
	rig=Rig.new();world.add_child(rig);check(rig.configure(head,body,profiles),"All seven original Commando profiles configure");
	check(preload("res://combat/movement_spread.gd").maximum(profiles[6])==0 and preload("res://combat/movement_spread.gd").maximum(profiles[0])==6,"Pistol launcher retains zero movement spread while long Commando weapons use heavy spread");rig.set_process(false);rig.set_physics_process(false);rig.set_allowed(true)
	app=Host.new();world.add_child(app);app.player=body;app.stage=world
	session=Session.new();world.add_child(session)
	var sync:=Sync.new();world.add_child(sync);sync.entities=Entities.new();sync.add_child(sync.entities)
	actor=Actor.new();world.add_child(actor);actor.position=Vector3(0,0,-8);actor.collision_layer=8
	var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=actor.visual_bounds().size;shape.shape=box;shape.position=actor.visual_bounds().get_center();actor.add_child(shape);sync.entities.actors["201"]=actor
	live=Gameplay.new();world.add_child(live);live.attach(app,rig,session,sync);live.set_process(false)
	await physics_frame;await physics_frame
	var manager:Node3D=rig.rounds_sim.effects.manager;manager.set_process(false);manager.set_view(head.global_transform,100,1.4)
	for index in range(7):
		equip(index);manager.clear()
		var state=rig.weapons[index].state
		check(discharge(),"Certified supported discharge queues "+str(state.profile.id))
		var direct:bool=index<5
		check(live.queue.size()==1 and live.queue[0].kind==("commando" if direct else "fire"),"Delivery action matches original weapon "+str(index))
		check(not live.queue[0].payload.has("damage") and live.queue[0].payload.two_hands,"Native owns heavy damage and shape victims "+str(index))
		check(rig.rounds_sim.bolts.is_empty() if direct else rig.rounds_sim.bolts.size()==1,"Direct shape never creates an ordinary bolt "+str(index))
		var before:int=rig.rounds_sim.fired_presentations
		await live.pump()
		check(app.calls.back().path==("/combat/session/commando" if direct else "/combat/session/fire"),"Production HTTP transport uses heavy action "+str(index))
		if direct:check(rig.rounds_sim.fired_presentations==before+1 and live.shots.is_empty(),"Accepted shape presents once and retires receipt "+str(index))
		manager.advance(.01)
		check(manager.statistics().particles>0 or manager.statistics().tracers>0,"Original heavy source emits native presentation "+str(index))
		if state.profile.charge_limited:
			state.rounds=0;check(not state.reload(),"Consumable heavy charges cannot reload "+str(index))
		var source:Dictionary=rig.assets.catalog.weapons[state.profile.id]
		if source.get("muzzle_hardpoint","")=="muzzle2":check(rig.assets.muzzle(state.profile.id).z<-.3 and absf(rig.assets.muzzle(state.profile.id).y)<.02,"Heavy source shaft/muzzle is aligned to aimed -Z "+str(index))
	equip(0);var capacity:int=rig.weapons[0].state.rounds;check(discharge(),"Prepare rejected heavy action");var rejected:Dictionary=live.queue[0].duplicate(true);app.reject=true;await live.pump()
	check(rig.weapons[0].state.rounds==capacity and live.shots.is_empty(),"Confirmed native rejection refunds one local reservation")
	live.combat_receipt(rejected,{"mutation":{"success":false,"shot_id":rejected.shot_id}});check(rig.weapons[0].state.rounds==capacity,"Duplicate rejection cannot mint rounds")
	equip(0);check(discharge("focused_discharge"),"Focused discharge uses shared VATS native action");check(live.queue[0].payload.target_id=="201" and live.queue[0].kind=="commando","Focused shape binds designated native enemy");await live.pump()
	equip(1);check(discharge("acid_spray") and live.queue[0].kind=="commando","Acid rifle unlocks alternate wider spray");await live.pump()
	equip(5);check(discharge("focused_discharge") and live.queue[0].kind=="fire","Focused rocket preserves physical travel");await live.pump()
	equip(5);check(discharge(),"Prepare rocket world collision");await live.pump();var shot:Dictionary=live.shots.values()[0].shot.duplicate(true)
	var wall:=StaticBody3D.new();world.add_child(wall)
	rig.rounds_sim.resolve_hit(shot,{"collider":wall,"position":Vector3(0,1,-4),"normal":Vector3.BACK},3.6)
	check(live.queue.size()==1 and live.queue[0].kind=="impact" and live.queue[0].payload.target_id=="0","World rocket contact delivers native blast centre, never fake creature damage")
	equip(0);var pose:=Transform3D(Basis.IDENTITY,Vector3(0,1,-.4));check(live.register_commando("overdrive",pose,"right"),"Equipped Master ultimate queues self action")
	check(not live.queue[0].payload.has("target_id") and rig.weapons[0].state.rounds==int(profiles[0].capacity),"Overdrive has no enemy requirement or ammunition cost");await live.pump()
	check(rig.abilities.cooldowns.overdrive==120 and live.shots.is_empty(),"Overdrive native receipt retires and preserves cooldown")
	equip(0)
	rig.weapons[0].visual.global_transform=pose
	var support:=Transform3D(Basis.IDENTITY,rig.support_point(0))
	rig.sample(.02,pose,support,1,1,0,true,true,false,0)
	rig.sample(.02,pose,support,1,1,1,true,true,false,1)
	check(live.queue.size()==1 and live.queue[0].kind=="commando" and live.queue[0].payload.ability_id=="overdrive","Supported simultaneous triggers route actual Master ultimate without target")
	check(rig.rounds_sim.bolts.is_empty() and rig.weapons[0].state.rounds==int(profiles[0].capacity),"Ultimate chord suppresses ordinary weapon discharge")
	equip(0);rig.two_hands=false;check(not live.register_commando("overdrive",pose,"right"),"Ultimate requires deliberate supported chord")
	var state=rig.weapons[0].state;state.block();state.tick(.02,0,true,false);check(state.tick(.02,1,true,false).is_empty(),"Long heavy weapons require physical support before local reservation")
	equip(6);state=rig.weapons[6].state;state.block();state.tick(.02,0,true,false);check(not state.tick(.02,1,true,false).is_empty(),"Pistol launcher retains one-hand use")
	# Native consumable uses are independent of a crafted magazine statistic.
	equip(2);state=rig.weapons[2].state;state.profile.capacity=20;state.rounds=20;state.charge_observation.clear()
	session.weapon_state.charges=40;session.sequence+=1;live.refresh_authority()
	check(state.rounds==40 and not state.reload(),"Forty native charges remain usable with crafted magazine capacity twenty")
	rig.update_visuals();check(rig.weapons[2].readout.report.capacity==40 and rig.weapons[2].readout.report.fraction==1,"Consumable HUD displays actual charges rather than a false magazine fraction")
	var equipment:Dictionary=state.profile.duplicate(true);equipment.source_kind="core3_weapon_instance";equipment.erase("charges");equipment.capacity=20
	check(state.refresh_instance(equipment) and state.rounds==40,"Re-equipping a charged item does not truncate uses to crafted capacity")
	var before_ham:Array=rig.abilities.ham.duplicate()
	check(discharge() and state.rounds==39,"Pending discharge reserves one actual charge")
	check(rig.abilities.ham==before_ham,"Ordinary live Commando discharge does not charge local HAM")
	session.sequence+=1;live.refresh_authority();check(state.rounds==39,"Fresh unrelated snapshot preserves outstanding charge reservation")
	var pending_id:String=live.queue[0].shot_id
	session.weapon_state.charges=39;session.sequence+=1;live.refresh_authority()
	var committed_sequence:int=session.sequence
	live.combat_receipt(live.queue[0],{"mutation":{"success":true,"shot_id":pending_id,"ability_id":"","interval_seconds":1.}});live.queue.clear()
	check(state.rounds==39,"Accepted native consumption does not subtract a second charge")
	session.weapon_state.charges=40;session.sequence=committed_sequence-1;live.refresh_authority();check(state.rounds==39,"An older native observation cannot refill a committed charge")
	session.weapon_state.charges=39;session.sequence=committed_sequence;live.refresh_authority()
	rig.stow();rig.draw(0);rig.stow();rig.draw(2);live.refresh_authority();check(state.rounds==39,"Stowing and item switching cannot refill native consumable uses")
	rig.two_hands=true;rig.support_latched=true;live.next_launch_usec=0
	check(discharge() and state.rounds==38,"Prepare ambiguous uncommitted charge reservation")
	live.queue.clear();live.shots.clear();session.sequence+=1;live.refresh_authority()
	check(state.rounds==39,"Fresh authoritative observation restores an uncertain uncommitted reservation")
	session.weapon_state.charges=0;session.sequence+=1;live.refresh_authority()
	check(state.rounds==0 and not state.reserve_rounds(1) and not state.reload(),"Native depletion cannot fire or manufacture charges through reload")
	state.refund_rounds(1);check(state.rounds==0,"A stale rejection cannot refund beyond the latest native remaining charges")
	session.weapon_state.charges=40;session.sequence-=1;live.refresh_authority();check(state.rounds==0,"Older item observation cannot refill an exhausted consumable")
	# The equip path must disable prediction before the next physics frame, not
	# wait for Gameplay's process callback to discover the new WeaponState.
	equip(0);var fresh:Dictionary=profiles[0].duplicate(true);fresh.item_id="900";fresh.source_kind="core3_weapon_instance"
	check(rig.begin_inventory_item(fresh),"Fresh owned heavy item enters the live rig")
	var new_state=rig.weapons[rig.selected].state
	check(new_state.ability_state==null and new_state.wear_per_shot==0,"New live equipment immediately disables local HAM and wear prediction")
	before_ham=rig.abilities.ham.duplicate();new_state.tick(.02,0,true,true);new_state.tick(.02,1,true,true)
	check(rig.abilities.ham==before_ham and new_state.condition_damage==0,"First input frame after equip cannot double-charge local HAM or wear")
	# One-hand pistol firing and the supported two-trigger ultimate share the
	# same physical grip rules; the ultimate still deliberately requires support.
	equip(6);pose=Transform3D(Basis.IDENTITY,Vector3(0,1,-.4));rig.weapons[6].visual.global_transform=pose
	support=Transform3D(Basis.IDENTITY,pose.origin+Vector3(-.035,-.025,.015))
	rig.sample(.02,pose,support,1,1,0,true,true,false,0);rig.sample(.02,pose,support,1,1,1,true,true,false,1)
	check(live.queue.size()==1 and live.queue[0].payload.ability_id=="overdrive" and live.queue[0].payload.two_hands,"Pistol launcher supports the deliberate two-hand Overdrive chord")
	# Offline source inspection is explicit and never substitutes bolt damage
	# for native shape or explosive delivery.
	equip(0);rig.shot_authority=Callable();var cosmetic_count:int=rig.rounds_sim.fired_presentations
	check(discharge() and rig.rounds_sim.bolts.is_empty() and rig.rounds_sim.fired_presentations==cosmetic_count+1,"Offline flamethrower uses source shape effects without a projectile bolt")
	rig.update_visuals();check(rig.weapons[0].visual.find_children("*","Label3D",true,false).is_empty(),"Offline inspection also uses the compact held display; inspection status remains in the lab UI")
	equip(6);rig.shot_authority=Callable();check(discharge() and rig.rounds_sim.bolts.size()==1 and rig.rounds_sim.bolts[0].shot.get("cosmetic_only",false),"Offline rocket remains physical presentation with no substitute local damage")
	var flight:Dictionary=preload("res://scout/controller.gd").grenade_flight({"landing_position":[1,2,3],"fuse_seconds":2.,"detonation_at_ms":12000},10500.)
	check(flight.remaining==1.5 and flight.progress==.25,"Grenade arc skips elapsed receipt latency")
	check(preload("res://scout/controller.gd").grenade_flight({"landing_position":[1,2,3],"fuse_seconds":2.,"detonation_at_ms":12000},13000.).remaining==0,"Late grenade receipt never delays detonation presentation")
	check(preload("res://scout/controller.gd").grenade_flight({"landing_position":[1,2],"fuse_seconds":2.,"detonation_at_ms":12000},10500.).is_empty(),"Malformed grenade receipt cannot invent a landing point")
	check(manager.styles.size()<=32 and manager.compiled_style_count<=48,"All seven heavy sources remain inside native style/program caps")
	world.queue_free();manager.queue_free();await process_frame;await process_frame
	var report:Dictionary={"checks":checks,"errors":errors,"renderer":"dummy","native_transport":"mocked","live_xr":false,"original_heavy_assets":true};print(JSON.stringify(report));FileAccess.open("res://../runtime/evidence/commando-client.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "));quit(0 if errors.is_empty() else 1)
