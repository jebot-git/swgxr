extends SceneTree
const PetControls=preload("res://pets/commands.gd")
class Bag extends Node3D:
	var offhand_occupied:=false
class World extends Node3D:
	var actors:Dictionary={}
class Players extends Node3D:
	var peers:Dictionary={}
class Sync extends Node:
	var entities:World
	var players:Players
class App extends Node:
	var datapad_epoch:=1
	var datapad_character_id:="42"
	var combat_rig:Node3D
	var inventory:Bag
	var multiplayer_sync:Sync
	var live_combat:Node
	var avatar:Node3D
class Host extends Node:
	var app:Node
	var vehicles:Node3D
	var allowed:=true
	var generation:=1
class Vehicle extends Node3D:
	var body:CharacterBody3D
	var origin:XROrigin3D
	var head:Camera3D
	var left:XRController3D
	var right:XRController3D
	var age:=0.0
	var busy:=false
	var free_hand:=true
	var state:Dictionary={}
	var requests:Array=[]
	func available(_side:String)->bool:return free_hand
	func native_session()->Node:return self
	func world(p:Array)->Vector3:return Vector3(p[0],p[1],-p[2])
	func request(action:String,detail:Dictionary={})->void:requests.append({"action":action,"detail":detail.duplicate(true)})
class Actor extends Node3D:
	var record:Dictionary={"kind":"creature","dead":false,"incapacitated":false,"attackable":false,"droid":false}
	var visual:Node3D
	func _ready()->void:visual=Node3D.new();add_child(visual)
	func visual_bounds()->AABB:return AABB(Vector3(-.5,0,-.5),Vector3(1,1.5,1))
	func is_targetable()->bool:return not record.dead and not record.incapacitated
var checks:=0
var failures:Array=[]
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);push_error(label)
func _initialize()->void:create_timer(30).timeout.connect(func():quit(2));call_deferred("run")
func tracker(side:String)->XRControllerTracker:
	var t:=XRControllerTracker.new();t.type=XRServer.TRACKER_CONTROLLER;t.name=side+"_hand"
	t.hand=XRPositionalTracker.TRACKER_HAND_LEFT if side=="left" else XRPositionalTracker.TRACKER_HAND_RIGHT
	for key in ["primary_click","ax_button","by_button"]:t.set_input(key,false)
	t.set_input("trigger",0.0);t.set_input("grip",0.0);t.set_input("primary",Vector2.ZERO)
	var pose:=Transform3D(Basis.IDENTITY,Vector3(-.2 if side=="left" else .2,1.2,-.4))
	t.set_pose("grip",pose,Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH);t.set_pose("aim",pose,Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	XRServer.add_tracker(t);return t
func select_in_wheel(widget:Node,index:int)->void:
	widget.frame(0,Vector2.ZERO,true,{})
	var angle:float=TAU*index/widget.wheel.entries.size()
	widget.frame(0,Vector2(sin(angle),cos(angle)),true,{})
func run()->void:
	var head_tracker:=XRPositionalTracker.new();head_tracker.type=XRServer.TRACKER_HEAD;head_tracker.name="head"
	head_tracker.set_pose("default",Transform3D(Basis.IDENTITY,Vector3(0,1.7,0)),Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH);XRServer.add_tracker(head_tracker)
	var left:=tracker("left");var right:=tracker("right")
	var app:=App.new();root.add_child(app);app.inventory=Bag.new();app.add_child(app.inventory)
	app.multiplayer_sync=Sync.new();app.add_child(app.multiplayer_sync);app.multiplayer_sync.entities=World.new();app.add_child(app.multiplayer_sync.entities);app.multiplayer_sync.players=Players.new();app.add_child(app.multiplayer_sync.players)
	var origin:XROrigin3D=load("res://xr/player_rig.tscn").instantiate();app.add_child(origin)
	var body=origin.get_node("PlayerBody");body.active=true;body.set_physics_process(false)
	var vehicle:=Vehicle.new();app.add_child(vehicle);vehicle.origin=origin;vehicle.body=body;vehicle.head=origin.get_node("XRCamera3D");vehicle.left=origin.get_node("LeftHand");vehicle.right=origin.get_node("RightHand")
	var host:=Host.new();app.add_child(host);host.app=app;host.vehicles=vehicle
	var widget:=PetControls.new();app.add_child(widget);widget.setup(host);widget.set_physics_process(false);widget.set_process(false)
	var follow:Dictionary={"id":"pet_1","command_id":1,"label":"Follow me","source_command":"follow","requires_target":false,"target_kind":"","range_m":64}
	var attack:Dictionary={"id":"pet_3","command_id":3,"label":"Attack","source_command":"animalattack","requires_target":true,"target_kind":"hostile","range_m":64}
	var pet:Dictionary={"id":"10","device_id":"20","owned":true,"pet_kind":"creature","position":[0,0,.4],"commands":[follow,attack]}
	vehicle.state={"pets":[pet]}
	var companion:=Actor.new();app.multiplayer_sync.entities.add_child(companion);companion.position=Vector3(0,0,-.4);app.multiplayer_sync.entities.actors["10"]=companion
	var enemy:=Actor.new();app.multiplayer_sync.entities.add_child(enemy);enemy.position=Vector3(-.2,0,-3);enemy.record.attackable=true;app.multiplayer_sync.entities.actors["30"]=enemy
	await process_frame
	check(widget.near_pet(vehicle.left.global_position).get("id")=="10","Offhand contact finds visible owned creature")
	widget.frame(1,Vector2.ZERO,true,pet)
	check(not widget.wheel.menu_open,"Held trigger at activation cannot open menu")
	widget.frame(0,Vector2.ZERO,true,pet);widget.frame(1,Vector2.ZERO,true,pet)
	check(widget.wheel.menu_open and vehicle.requests.is_empty(),"Fresh trigger over pet opens standard wheel without commanding")
	check(widget.blocks_trigger("left") and not widget.blocks_trigger("right"),"Only offhand trigger is reserved")
	var before:Vector3=widget.wheel.panel.global_position;origin.position.x+=2;widget.wheel.follow_controller()
	check(widget.wheel.panel.global_position.is_equal_approx(before+Vector3.RIGHT*2),"Pet wheel follows controller during locomotion")
	origin.position.x-=2
	select_in_wheel(widget,0)
	check(body.pet_stick_side=="left","Selection keeps stick captured until neutral to prevent locomotion jump")
	check(widget.state.selection.id=="pet_1" and not widget.wheel.menu_open and vehicle.requests.is_empty(),"Selecting prepares command without executing")
	widget.frame(0,Vector2.ZERO,true,{});widget.frame(1,Vector2.ZERO,true,{})
	check(vehicle.requests.size()==1 and vehicle.requests[0].detail.command_id==1 and not vehicle.requests[0].detail.has("target_id"),"Untargeted command uses one click without adopting weapon target")
	check(widget.state.selection.is_empty() and widget.blocks_trigger("left"),"Dispatch consumes selection and retains trigger until release")
	widget.frame(1,Vector2.ZERO,true,{})
	check(vehicle.requests.size()==1,"Held trigger never repeats command")
	widget.frame(0,Vector2.ZERO,true,pet);widget.frame(1,Vector2.ZERO,true,pet);select_in_wheel(widget,1)
	widget.frame(0,Vector2.ZERO,true,{});widget.frame(1,Vector2.ZERO,true,{})
	widget._process(0)
	check(widget.state.aiming and widget.reticle.visible and vehicle.requests.size()==1,"First targeted click shows reticle without sending command")
	var reticle_before:=widget.reticle.global_position
	vehicle.left.position+=Vector3.RIGHT*.1;widget._process(0)
	check(widget.reticle.global_position.distance_to(reticle_before)>.09,"Reticle follows hand pose")
	vehicle.left.position-=Vector3.RIGHT*.1
	check(widget.target_id()=="30","Offhand ray acquires first eligible creature")
	var wall:=StaticBody3D.new();wall.collision_layer=1;var collision:=CollisionShape3D.new();var shape:=BoxShape3D.new();shape.size=Vector3(2,2,.15);collision.shape=shape;wall.add_child(collision);app.add_child(wall);wall.position=Vector3(0,1,-1.8)
	await physics_frame
	widget.frame(0,Vector2.ZERO,true,{});widget.frame(1,Vector2.ZERO,true,{})
	check(vehicle.requests.size()==1 and widget.state.aiming,"Obstruction rejects target while keeping aiming selection")
	wall.free();await physics_frame
	widget.frame(0,Vector2.ZERO,true,{});widget.frame(1,Vector2.ZERO,true,{})
	check(vehicle.requests.size()==2 and vehicle.requests.back().detail.target_id=="30" and widget.state.selection.is_empty(),"Second valid targeted click dispatches captured target and consumes selection")
	widget.state.select(attack,"20","10");widget.frame(0,Vector2.ZERO,true,{})
	widget.frame(1,Vector2.ZERO,false,{})
	check(not widget.state.aiming and not widget.state.selection.is_empty(),"Occupied or unavailable offhand preserves selection but cannot execute")
	widget.frame(1,Vector2.ZERO,true,{})
	check(not widget.state.aiming,"Restored hand requires release and fresh click")
	widget.frame(0,Vector2.ZERO,true,{});vehicle.busy=true;widget.frame(1,Vector2.ZERO,true,{});vehicle.busy=false;widget.frame(1,Vector2.ZERO,true,{})
	check(not widget.state.aiming and vehicle.requests.size()==2,"Busy transport never queues delayed command")
	app.inventory.offhand_occupied=true;check(not widget.hand_empty(),"Medical/tool ownership excludes pet controls")
	app.inventory.offhand_occupied=false
	widget.reset();companion.position=Vector3(-.2,0,-3)
	var group:Dictionary={"id":"pet_15","command_id":15,"label":"Group","source_command":"group","requires_target":false,"range_m":64}
	for kind:String in ["creature","droid"]:
		pet.pet_kind=kind;pet.commands=[follow,group];widget.available_now=true
		check(not widget.button("primary_click","right"),"Main-hand click stays independent for "+kind)
		check(widget.button("primary_click","left") and widget.wheel.menu_open,"Joystick click opens aimed "+kind+" menu")
		check(widget.wheel.entries[1].label=="Invite / remove from party","Party command clearly labels native membership toggle")
		select_in_wheel(widget,1)
		var sent:=vehicle.requests.size()
		widget.frame(0,Vector2.ZERO,true,{});widget.frame(1,Vector2.ZERO,true,{})
		check(vehicle.requests.size()==sent+1 and vehicle.requests.back().action=="pet_command" and vehicle.requests.back().detail.command_id==15 and vehicle.requests.back().detail.device_id=="20","Party invitation dispatches native trained command for "+kind)
		widget.reset()
	widget.available_now=true;pet.owned=false
	check(not widget.button("primary_click","left"),"Cannot open another player's pet menu")
	pet.owned=true;pet.commands=[follow]
	check(widget.menu_entries(pet).size()==1,"Untrained group command is never invented by client")
	wall=StaticBody3D.new();wall.collision_layer=1;collision=CollisionShape3D.new();collision.shape=shape;wall.add_child(collision);app.add_child(wall);wall.position=Vector3(0,1,-1.8)
	await physics_frame
	check(not widget.button("primary_click","left"),"Joystick pet targeting cannot cross a wall")
	wall.free();await physics_frame
	widget.available_now=false
	check(not widget.button("primary_click","left"),"Stale or unavailable pet controls cannot open wheel")
	companion.position=Vector3(0,0,-.4);pet.commands=[follow,attack]
	var fixture:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/evidence/professions/fixture.json"))
	var combat:=preload("res://combat/ranged_rig.gd").new();origin.add_child(combat);app.combat_rig=combat
	check(combat.configure(vehicle.head,body,[fixture.weapons.pistol_cdef],"right",origin),"Actual original weapon rig remains configured alongside pets")
	combat.set_physics_process(false);combat.set_process(false);combat.configure_player_combat(fixture.player_combat);combat.set_allowed(true);combat.draw(0)
	combat.abilities.select(combat.active_profile(),"lethal_shot");var selection: String=combat.abilities.selected
	widget.state.select(follow,"20","10");widget.frame(0,Vector2.ZERO,true,{});widget.frame(1,Vector2.ZERO,true,{})
	check(combat.abilities.selected==selection,"Pet command does not replace main-hand ability")
	check(combat.pet_trigger_reserved("left") and not combat.pet_trigger_reserved("right"),"Combat rig honors offhand pet capture independently")
	combat.support_latched=true;check(not widget.hand_empty(),"Supporting a two-hand weapon makes offhand occupied");combat.support_latched=false
	widget.state.select(attack,"20","10");vehicle.state.pets=[];widget.reconcile()
	check(widget.state.selection.is_empty(),"Recovered, despawned or transferred pet invalidates selection")
	vehicle.state.pets=[pet];widget.state.select(attack,"20","10");widget.reset()
	check(widget.state.selection.is_empty() and not widget.state.aiming,"Character/session reset clears pet command state")
	check(PetControls.target_eligible("corpse",{"kind":"creature","dead":true}) and not PetControls.target_eligible("hostile",{"kind":"creature","dead":true,"attackable":true}),"Dead creatures can be harvested but cannot be attacked")
	check(PetControls.target_eligible("droid",{"droid":true}) and not PetControls.target_eligible("droid",{"droid":false}),"Droid support commands filter recipient type")
	vehicle.state.pets=[pet];widget.state.select(attack,"20","10");vehicle.state.pets[0].commands=[follow];widget.reconcile()
	check(widget.state.selection.is_empty(),"Loss of trained command invalidates prepared ability")
	vehicle.state.pets[0].commands=[follow,attack]
	widget.frame(0,Vector2.ZERO,true,pet);widget.frame(1,Vector2.ZERO,true,pet)
	check(body.pet_stick_side=="left" and widget.button("primary_click","left") and body.pet_stick_side.is_empty(),"Offhand stick click closes pet wheel and releases movement capture")
	check(widget.wheel.texture("follow")!=null and widget.wheel.texture("animalattack")!=null,"Original command artwork is available")
	widget.free();body.dominant_hand="left"
	var swapped:=PetControls.new();app.add_child(swapped);swapped.setup(host);swapped.set_physics_process(false);swapped.set_process(false)
	check(swapped.side=="right" and swapped.hand==vehicle.right,"Left-dominant players use right offhand for pet controls")
	swapped.available_now=true;swapped.state.select(follow,"20","10")
	check(swapped.blocks_trigger("right") and not swapped.blocks_trigger("left"),"Left-dominant capture leaves main hand independent")
	app.queue_free();XRServer.remove_tracker(left);XRServer.remove_tracker(right);XRServer.remove_tracker(head_tracker);await process_frame;await process_frame
	var report:Dictionary={"passed":failures.is_empty(),"checks":checks,"failures":failures,"native":"mocked","tracking":"mocked","renderer":"headless dummy","live_headset":false}
	print(JSON.stringify(report));FileAccess.open("res://../runtime/evidence/pet-commands-client.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "));quit(0 if failures.is_empty() else 1)
