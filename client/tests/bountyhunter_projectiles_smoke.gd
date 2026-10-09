extends SceneTree
const Projectiles=preload("res://combat/projectiles.gd")
class Actor extends StaticBody3D:
	var record:Dictionary={"id":"201","kind":"creature","relation":"hostile","dead":false}
	func core3_identity()->Dictionary:return {"id":record.id,"session_id":"bounty-projectiles"}
	func is_targetable()->bool:return not record.dead
var world:Node3D
var sim:Node3D
var target:Actor
var other:Actor
var wall:StaticBody3D
var contacts:Array=[]
var checks:=0
var errors:Array=[]
var report:Dictionary={}
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:errors.append(label);push_error(label)
func actor(id:String,position:Vector3,size:Vector3)->Actor:
	var value:=Actor.new();world.add_child(value);value.record=value.record.duplicate();value.record.id=id;value.position=position;value.collision_layer=8
	var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=size;shape.shape=box;shape.position=Vector3.UP;value.add_child(shape);return value
func shot(delivery:String)->Dictionary:return {"weapon_id":"rifle_lightning" if delivery=="guided_bolt" else "pistol_scatter","sequence":1,"shot_id":"test","live_session":"bounty-projectiles","delivery":delivery,"speed":160.,"range":32.}
func collect(value:Dictionary,identity:Dictionary,p:Vector3,_n:Vector3,_d:float)->void:contacts.append({"shot":value,"identity":identity,"position":p})
func settle()->void:await physics_frame;await physics_frame
func launch(delivery:String,offset:float,speed:float,guided:=false,bound:="")->Array:
	sim.clear();contacts.clear();target.position=Vector3(offset,0,-20);other.position=Vector3(100,0,-20);await settle()
	var value:=shot(delivery)
	if guided:value["guided_target_id"]="201";value["guidance_actor"]=target
	if not bound.is_empty():value["target_id"]=bound
	sim.spawn(value,Transform3D(Basis.IDENTITY,Vector3.UP),Vector3.UP)
	for i in range(36):
		target.position.x+=speed/120.;await physics_frame;sim._physics_process(1./120.)
	return contacts.duplicate(true)
func _initialize()->void:create_timer(35).timeout.connect(func():quit(2));call_deferred("run")
func run()->void:
	world=Node3D.new();root.add_child(world);sim=Projectiles.new();world.add_child(sim);sim.set_physics_process(false);sim.authoritative_contact.connect(collect)
	target=actor("201",Vector3(0,0,-20),Vector3(.6,1.8,.6));other=actor("202",Vector3(100,0,-20),Vector3(.6,1.8,.6))
	wall=StaticBody3D.new();world.add_child(wall);wall.collision_layer=1;wall.position=Vector3(100,1,-10)
	var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(10,4,.3);shape.shape=box;wall.add_child(shape)
	var directions:Array=[]
	for direction:Vector3 in [Vector3.FORWARD,Vector3(.3,.2,-.9).normalized(),Vector3(0,1,.01).normalized()]:
		for index in range(8):
			var ray:Vector3=Projectiles.pellet_direction(direction,index)
			directions.append({"pellet_index":index,"launch_direction":[direction.x,direction.y,-direction.z],"pellet_direction":[ray.x,ray.y,-ray.z]})
	report["source_space_pellet_directions"]=directions
	check(Projectiles.pellet_direction(Vector3.FORWARD,1).x<0,"Source-space pellet index orientation survives Godot Z reflection")
	var ordinary:=await launch("bolt",.8,3.)
	var scatter:=await launch("scatter",.8,3.)
	check(ordinary.is_empty() and scatter.size()==1,"Moving lateral target is missed by center ray and touched by real off-axis pellet")
	var pellet_count:=int(scatter[0].shot.pellet_contacts.size()) if scatter.size()==1 else 0
	check(pellet_count>0 and pellet_count<8,"Off-axis moving hit has partial pellet evidence, never full discharge damage")
	var source_contacts:Array=[]
	if scatter.size()==1:
		for contact:Dictionary in scatter[0].shot.pellet_contacts:
			var p:Vector3=contact.hit_position;source_contacts.append({"pellet_index":contact.pellet_index,"hit_position":[p.x,p.y,-p.z],"projectile_age_seconds":contact.projectile_age_seconds})
	report["source_space_scatter_fixture"]={"origin":[0,1,0],"direction":[0,0,1],"range":32,"pellet_contacts":source_contacts}
	report["moving_scatter"]={"range_m":20,"target_width_m":.6,"target_start_offset_m":.8,"target_speed_mps":3,"projectile_speed_mps":160,"center_contacts":ordinary.size(),"scatter_recipients":scatter.size(),"pellets":pellet_count,"damage_budget_fraction":pellet_count/8.}
	target.record.kind="lair"
	var lair:=await launch("scatter",0.,0.)
	check(lair.size()==1 and lair[0].identity.id=="201" and lair[0].shot.pellet_contacts.size()>0 and lair[0].shot.pellet_contacts.size()<=8,"Ordinary scatter retains one physical lair/destructible recipient")
	target.record.relation="neutral";lair=await launch("scatter",0.,0.)
	check(lair.is_empty(),"Nonattackable tangible cannot become primary pellet recipient")
	target.record.kind="creature";target.record.relation="hostile"
	var hole:=await launch("scatter",.65,0.)
	check(hole.is_empty(),"Being inside spread cone does not auto-hit between actual pellet rays")
	sim.clear();contacts.clear();target.position=Vector3(0,0,-8);other.position=Vector3(.52,0,-8);await settle();sim.spawn(shot("scatter"),Transform3D(Basis.IDENTITY,Vector3.UP),Vector3.UP)
	for i in range(30):sim._physics_process(1./120.)
	check(contacts.size()==1 and contacts[0].shot.pellet_contacts.size()<8,"Two eligible pellet recipients resolve to one primary and bounded fraction")
	check(sim.scatter_groups.is_empty() and sim.bolts.is_empty(),"Completed pellet group releases all projectiles and evidence")
	sim.clear();contacts.clear();target.position=Vector3(0,0,-8);other.position=Vector3(.52,0,-8);await settle();var bound:=shot("scatter");bound.target_id="202";sim.spawn(bound,Transform3D(Basis.IDENTITY,Vector3.UP),Vector3.UP)
	for i in range(30):sim._physics_process(1./120.)
	check(contacts.size()==1 and contacts[0].identity.id=="202","Target-bound scatter never transfers damage to center bystander")
	wall.position.x=0;await settle();scatter=await launch("scatter",.8,3.);check(scatter.is_empty(),"Wall stops every scatter pellet")
	wall.position.x=100;await settle()
	ordinary=await launch("bolt",.30,1.5)
	var lightning:=await launch("guided_bolt",.30,1.5,true)
	check(ordinary.is_empty() and lightning.size()==1,"Slight lightning guidance improves moving target contact without a cone hit")
	report["moving_lightning"]={"range_m":20,"target_width_m":.6,"target_start_offset_m":.3,"target_speed_mps":1.5,"projectile_speed_mps":160,"straight_contacts":ordinary.size(),"guided_contacts":lightning.size()}
	wall.position.x=0;await settle();lightning=await launch("guided_bolt",.30,1.5,true);check(lightning.is_empty(),"Lightning stops at world wall and does not guide through it")
	wall.position.x=100;await settle();lightning=await launch("guided_bolt",3.,0.,true);check(lightning.is_empty(),"Guidance rejects target outside initial five degrees")
	lightning=await launch("guided_bolt",.3,12.,true);check(lightning.is_empty(),"Fast target can evade bounded guidance")
	sim.clear();contacts.clear();target.position=Vector3(.2,0,-30);await settle();var guided:=shot("guided_bolt");guided.guidance_actor=target;sim.spawn(guided,Transform3D(Basis.IDENTITY,Vector3.UP),Vector3.UP)
	var bolt:Dictionary=sim.bolts[0]
	target.position=Vector3(5,0,-30);await settle()
	for i in range(90):sim.guide(bolt,1./120.)
	check(float(bolt.guidance_turn)<=deg_to_rad(8.)+.00001 and is_equal_approx(float(bolt.guidance_turn),deg_to_rad(8.)),"Accumulated lightning turn is capped at eight degrees")
	sim.clear();contacts.clear();target.position=Vector3(0,0,-8);await settle();sim.spawn(shot("scatter"),Transform3D(Basis.IDENTITY,Vector3.UP),Vector3.UP);sim._physics_process(.06);sim.clear();check(contacts.is_empty(),"Disconnect/clear discards pending pellet aggregation without late damage")
	report.merge({"checks":checks,"errors":errors,"renderer":"dummy","live_xr":false,"collision":"production swept Godot physics","damage_authority":"contact evidence only"})
	print(JSON.stringify(report));var f:=FileAccess.open("res://../runtime/evidence/bounty/combat-projectiles.json",FileAccess.WRITE);f.store_string(JSON.stringify(report,"  "));world.free();quit(0 if errors.is_empty() else 1)
