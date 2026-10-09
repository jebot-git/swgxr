extends SceneTree
const Scout=preload("res://scout/controller.gd")
class Controller extends Scout:
	var calls:Array=[]
	var reply:Dictionary={}
	func request(action:String,detail:Dictionary={}) -> Dictionary:
		calls.append({"action":action,"detail":detail.duplicate(true)})
		await get_tree().process_frame
		return reply.duplicate(true)
class Bag extends Node3D:
	var assets=preload("res://scripts/inventory_assets.gd").new()
	var held_model:Node3D
	var held_item:Dictionary={}
	var allowed:=true
	var is_open:=false
	var finished:Array=[]
	func finish_item_action(success:bool)->void:finished.append(success)
	func set_busy(_value:bool,_message:String)->void:pass
class Combat extends Node3D:
	var selected:=-1
	var weapons:Array=[]
	var rounds_sim:Node3D
class Host extends Node3D:
	var datapad_epoch:=1
	var world_ready:=true
	var stage:Node3D
	var combat_rig:Node3D
	var live_combat:Node3D
	var multiplayer_sync:Node
var checks:=0
var errors:Array=[]
func check(value:bool,label:String)->void:
	checks+=1
	if not value:errors.append(label);push_error(label)
func _initialize()->void:create_timer(15).timeout.connect(func():quit(2));call_deferred("run")
func run()->void:
	var app:=Host.new();root.add_child(app);app.stage=app
	var rig:=XROrigin3D.new();app.add_child(rig)
	var head:=Camera3D.new();head.name="XRCamera3D";rig.add_child(head);head.position=Vector3(0,1,0)
	var bag:=Bag.new();app.add_child(bag);bag.assets.configure();bag.held_model=Node3D.new();bag.add_child(bag.held_model);bag.held_model.position=Vector3(.2,1,-.3)
	var combat:=Combat.new();app.add_child(combat);app.combat_rig=combat
	combat.rounds_sim=preload("res://combat/projectiles.gd").new();combat.add_child(combat.rounds_sim)
	var assets=preload("res://combat/original_assets.gd").new();check(assets.load_catalog(),"Original combat effects load")
	combat.rounds_sim.configure_effects(assets,head)
	var manager:Node3D=combat.rounds_sim.effects.manager;manager.set_process(false);manager.set_view(head.global_transform,100,1.4)
	var scout:=Controller.new();app.add_child(scout);scout.set_process(false);scout.app=app;scout.rig=rig;scout.bag=bag;scout.last_reply=0
	scout.state={"targets":[{"id":"201","position":[0,0,5],"heading_radians":0,"bounds":{"center":[0,1,0],"radius":.5},"eligible":false,"grenade_eligible":true}],"grenade_cooldown":0}
	await physics_frame
	check(scout.target_under_reticle()=="" and scout.target_under_reticle(true)=="201","Grenades acquire hostile NPCs without admitting them to creature-only traps")
	scout.state.targets[0].position=[0,0,40]
	check(scout.target_under_reticle(true)=="","Grenade reticle excludes targets outside native 32-metre throw range")
	scout.state.targets[0].position=[0,0,5]
	var item:Dictionary={"id":"81","template":"object/weapon/ranged/grenade/grenade_cryoban.iff","tool_kind":"grenade","throwable_kind":"cryoban"};bag.held_item=item
	check(scout.trap_held(),"Held grenade shares throwable reticle and hand path")
	check(not scout.try_throw(item),"Grip release without throw motion cannot consume grenade")
	for i in range(20):
		scout.gestures.sample(.01,Transform3D.IDENTITY,Vector3.ZERO,Vector3.ZERO,1,1,true)
		scout.gestures.sample_throw(.01,Transform3D.IDENTITY,Vector3(0,0,-i*.02),true)
	var stamp:int=Time.get_unix_time_from_system()*1000
	scout.reply={"ok":true,"state":{"server_time_ms":stamp},"mutation":{"landing_position":[0,0,5],"fuse_seconds":2.,"detonation_at_ms":stamp+500}}
	check(scout.try_throw(item),"Valid throw motion releases native grenade action")
	await process_frame;await process_frame
	check(scout.calls.size()==1 and scout.calls[0].action=="grenade" and scout.calls[0].detail=={"item_id":"81","target_id":"201"},"Grenade uses inventory identity and server-selected landing instead of client damage data")
	check(bag.finished==[true],"Accepted grenade finishes held-item mutation once")
	check(scout.grenade_assets==null,"No explosion is presented before the accepted detonation deadline")
	await create_timer(.6).timeout
	check(scout.grenade_assets!=null,"Original grenade explosion is presented at the accepted deadline")
	for family:String in ["fragmentation_light","fragmentation","cryoban","glop","imperial","thermal","proton"]:
		manager.clear();var before:int=manager.statistics().events_admitted
		scout.grenade_detonation({"throwable_kind":family},Vector3(0,0,-5),app.datapad_epoch)
		manager.advance(.01)
		check(manager.statistics().events_admitted>before and manager.statistics().particles>0,"Original explosion particles emit for "+family)
	var before:int=manager.statistics().events_requested
	scout.grenade_detonation(item,Vector3(0,0,-5),0)
	check(manager.statistics().events_requested==before,"Expired character epoch suppresses delayed grenade effects")
	scout.state.grenade_cooldown=2.;check(not scout.try_throw(item),"Shared native recovery blocks another throwable intent")
	check(manager.styles.size()<=32 and manager.compiled_style_count<=48,"Grenade effects reuse bounded transient source styles")
	app.queue_free();manager.queue_free();await process_frame;await process_frame
	var report:Dictionary={"checks":checks,"errors":errors,"original_grenade_assets":true,"native_transport":"mocked","renderer":"dummy","live_xr":false};print(JSON.stringify(report));FileAccess.open("res://../runtime/evidence/grenade-client.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "));quit(0 if errors.is_empty() else 1)
