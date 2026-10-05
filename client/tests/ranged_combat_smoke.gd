extends SceneTree
const State = preload("res://combat/weapon_state.gd")
const Rig = preload("res://combat/ranged_rig.gd")
const Bolts = preload("res://combat/projectiles.gd")
const Target = preload("res://combat/training_target.gd")
const Loader = preload("res://scripts/stage_loader.gd")
var failures: Array[String] = []
var checks := 0
var catalog: Dictionary
var events: Array = []

func check(test: bool, message: String) -> void:
	checks += 1
	if not test: failures.append(message); push_error(message)

func weapon(key: String, certs = null):
	var state := State.new()
	var profile: Dictionary = catalog.weapons[key]
	check(state.configure(profile,profile.core3.certificationsRequired if certs==null else certs),"Valid profile " + key)
	return state

func _initialize() -> void: call_deferred("run")

func run() -> void:
	create_timer(45).timeout.connect(func(): push_error("Combat smoke timeout"); quit(2))
	catalog = JSON.parse_string(FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://../runtime/combat/catalog.json")))
	var balance: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://combat/balance.json"))
	var expected: Array=[]; var exported: Array=[]
	for key: String in balance.weapons:
		if balance.classes[balance.weapons[key].class].get("kind","")!="melee": expected.append(key)
	for key: String in catalog.weapons:
		if catalog.weapons[key].get("kind","")!="melee": exported.append(key)
	expected.sort(); exported.sort()
	check(exported==expected and catalog.failures.is_empty(),"Every configured source ranged weapon exported without failure")
	var fwg5: Dictionary=catalog.weapons.get("pistol_fwg5",{})
	check(fwg5.get("template","")=="object/weapon/ranged/pistol/pistol_fwg5.iff" and fwg5.get("class","")=="heavy_pistol","FWG5 original template uses heavy-pistol presentation")
	var source: Dictionary=fwg5.get("core3",{})
	check(source.get("damageType","")=="heat" and source.get("minDamage",0)==40 and source.get("maxDamage",0)==150 and source.get("maxRange",0)==64 and source.get("certificationsRequired",[])==["cert_pistol_fwg5"],"FWG5 source template damage/range/certification fields preserved")
	for rate in [60,90,120]:
		var automatic = weapon("rifle_e11")
		automatic.tick(0,0,true,true)
		for i in range(rate*5): automatic.tick(1.0/rate,1,true,true)
		check(automatic.fired==30,"360 RPM is frame-rate independent at %d Hz (%d)" % [rate,automatic.fired])
	var pistol = weapon("pistol_dl44")
	pistol.tick(0,0,true,false)
	var shot: Dictionary = pistol.tick(0.01,1,true,false)
	check(not shot.is_empty(),"Fresh trigger fires semi-auto")
	for i in range(100): pistol.tick(0.01,1,true,false)
	check(pistol.fired==1,"Held semi-auto trigger produces exactly one shot")
	pistol.tick(0,0,true,false)
	pistol.tick(0.01,1,true,false)
	check(pistol.fired==2,"Fresh press fires after cadence")
	pistol.tick(0,0,true,false)
	pistol.tick(0.01,1,true,false)
	check(pistol.fired==2,"Trigger spam cannot bypass RPM")
	var burst = weapon("carbine_ee3")
	burst.tick(0,0,true,true)
	for i in range(200): burst.tick(0.01,1,true,true)
	check(burst.fired==3,"EE-3 emits exactly three rounds per held trigger")
	burst.tick(0,0,true,true)
	burst.tick(0.01,1,true,true)
	burst.tick(0.01,1,false,true)
	for i in range(100): burst.tick(0.01,1,true,true)
	check(burst.fired==4,"Interrupted burst cancels and needs trigger release")
	var peace_burst = weapon("carbine_ee3")
	peace_burst.tick(0,0,true,true)
	peace_burst.tick(0.01,1,true,true)
	for i in range(30): peace_burst.tick(0.01,0,true,true)
	check(peace_burst.fired==1 and peace_burst.burst_left==0,"Trigger release cancels remaining burst rounds")
	var uncertified = weapon("rifle_e11",[])
	uncertified.tick(0,0,true,true)
	check(uncertified.tick(1,1,true,true).is_empty(),"Missing required certificate blocks shots")
	var reload_state = weapon("rifle_e11")
	reload_state.rounds = 2
	reload_state.tick(0,0,true,true)
	for i in range(50): reload_state.tick(0.01,1,true,true)
	check(reload_state.fired==2 and reload_state.rounds==0 and reload_state.reload_until>0,"Capacity starts automatic timed reload")
	for i in range(300): reload_state.tick(0.01,1,true,true)
	check(reload_state.rounds==40 and reload_state.fired==2,"Reload completes without resuming held trigger")
	reload_state.tick(0.01,0,true,true)
	check(not reload_state.tick(0.01,1,true,true).is_empty(),"Release then press re-arms after reload")
	var worn = weapon("pistol_dl44")
	worn.condition_damage = worn.condition_max-0.01
	worn.tick(0,0,true,false)
	worn.tick(0.01,1,true,false)
	worn.tick(1,0,true,false)
	check(worn.tick(1,1,true,false).is_empty(),"Broken weapon cannot fire; reload never repairs condition")
	check(is_equal_approx(pistol.range_scale(true),1.1),"Two-handed pistol gets ten percent range bonus")
	check(is_equal_approx(uncertified.range_scale(false),0.3),"One-handed longarm loses seventy percent range")
	var low: Dictionary = State.damage_at(shot,8,{},0,0,1)
	var high: Dictionary = State.damage_at(shot,8,{},0,1,0)
	check(is_equal_approx(low.damage,25) and is_equal_approx(high.damage,112.5),"Core3 DL-44 damage spread and ideal-range curve retained")
	check(not low.wound and high.wound,"Core3 wound percentage interpreted as percent")
	var resisted: Dictionary = State.damage_at(shot,8,{"energy":50,"kinetic":100},0,1,0)
	check(is_equal_approx(resisted.damage,high.damage*0.5),"Only resistance matching weapon damage type applies")
	check(is_equal_approx(State.damage_at(shot,8,{},1,1,0).damage,high.damage*0.5),"Higher armour tier applies Core3 AP multiplier")
	check(State.damage_at(shot,65,{},0,1,0).damage==0,"Beyond projectile range cannot damage")
	check(State.damage_at(shot,64,{},0,1,0).damage<high.damage,"Far-range damage modifier applies")
	var world := Node3D.new()
	root.add_child(world)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(0,1.7,0)
	var body := CharacterBody3D.new()
	world.add_child(body)
	var rig := Rig.new()
	world.add_child(rig)
	check(rig.configure(camera,body,[catalog.weapons.pistol_dl44,catalog.weapons.rifle_e11]),"Original weapon rig configured")
	rig.set_physics_process(false)
	rig.set_allowed(true)
	var original_head := camera.transform
	var original_body := body.transform
	var hip: Transform3D = rig.holster_transform(1)
	var shoulder: Transform3D = rig.holster_transform(2)
	check(hip.origin.x>camera.position.x and shoulder.origin.z>camera.position.z,"Right dominant hip and rear shoulder placement")
	rig.sample(0.01,hip,Transform3D.IDENTITY,0,0,0,true,true)
	rig.sample(0.01,hip,Transform3D.IDENTITY,0.9,0,1,true,true)
	check(rig.selected==0 and rig.weapons[0].state.fired==0,"Dominant grip draws hip pistol without firing a held trigger")
	var pose := Transform3D(Basis.from_euler(Vector3(0.02,0.041,0)),Vector3(0.25,1.3,-0.35))
	rig.sample(0.01,pose,pose,0.9,0,0,true,true)
	rig.sample(0.01,pose,pose,0.9,0.9,1,true,true)
	check(rig.two_hands and rig.weapons[0].state.fired==1,"Support grip braces pistol and fresh trigger fires")
	check(rig.reticle.visible and is_equal_approx(rig.reticle.global_position.distance_to(rig.muzzle_pose(0).origin),3),"Reticle remains exactly three metres from muzzle")
	check((-rig.reticle.global_basis.z).distance_to(-pose.basis.z)<0.0001,"Broad reticle stays aligned with barrel")
	rig.sample(0.01,pose,pose,0,0,0,true,true)
	check(rig.selected==-1 and not rig.reticle.visible,"Releasing primary grip returns pistol to hip and hides reticle")
	rig.sample(0.01,shoulder,pose,0.9,0,0,true,true)
	check(rig.selected==1,"Over-shoulder grip draws two-handed weapon")
	rig.sample(0.01,pose,pose,0.9,0,0,true,true)
	var support := Transform3D(Basis.IDENTITY,rig.support_point(1))
	rig.sample(0.01,pose,support,0.9,0.9,0,true,true)
	check(rig.two_hands,"Secondary grip near fore-end attaches")
	support.origin += Vector3(0.15,0.08,0)
	rig.sample(0.01,pose,support,0.9,0.9,0,true,true)
	check((-rig.weapons[1].visual.global_basis.z).dot((support.origin-pose.origin).normalized())>0.999,"Two hands steer longarm along tracked grip-to-support axis")
	rig.sample(0.01,pose,support,0.9,0.9,0,true,false)
	check(not rig.two_hands,"Lost support tracking immediately removes range bonus")
	rig.sample(0.01,pose,support,0.9,0.9,1,false,false)
	check(rig.selected==-1,"Lost main tracking stows and blocks firing")
	check(camera.transform==original_head and body.transform==original_body,"Combat never moves head or physics body")
	rig.dominant = "left"
	check(rig.holster_transform(1).origin.x<camera.position.x,"Left dominant holster mirrors")
	camera.position.y -= 0.5
	check(is_equal_approx(rig.holster_transform(1).origin.y,hip.origin.y-0.5),"Holster follows physical crouching")
	camera.transform = original_head
	var target := Target.new()
	world.add_child(target)
	target.position = Vector3(0,1.3,-5)
	await physics_frame
	await physics_frame
	var bolts := Bolts.new()
	world.add_child(bolts)
	bolts.set_physics_process(false)
	bolts.impact.connect(func(event):events.append(event))
	bolts.spawn(shot,Transform3D(Basis.IDENTITY,Vector3(0,1.3,0)),Vector3(0,1.3,0.1))
	bolts._physics_process(0.2)
	check(target.hit_count==1 and bolts.bolts.is_empty(),"Swept projectile hits a thin target across a large time step")
	var short_shot := shot.duplicate(true)
	short_shot.range = 2
	bolts.spawn(short_shot,Transform3D(Basis.IDENTITY,Vector3(0,1.3,0)),Vector3(0,1.3,0.1))
	bolts._physics_process(1)
	check(target.hit_count==1 and bolts.bolts.is_empty(),"Projectile range clamps sweep and despawns before farther target")
	# The grip is behind the target but the muzzle is beyond it: must hit obstruction.
	bolts.spawn(shot,Transform3D(Basis.IDENTITY,Vector3(0,1.3,-5.5)),Vector3(0,1.3,-4))
	check(target.hit_count==2 and bolts.bolts.is_empty(),"Muzzle-through-wall exploit blocked by grip-to-muzzle sweep")
	var loader := Loader.new()
	var stage := loader.load_stage(ProjectSettings.globalize_path("res://../runtime/assets/mos_eisley/scene.json"))
	check(stage!=null,"Actual Mos Eisley stage loads alongside combat")
	if stage != null:
		world.add_child(stage)
		await physics_frame
		await physics_frame
		bolts.configure_collision(stage)
		var point: Vector3 = loader.vec(loader.report.spawn)+Vector3.UP
		var cell_id := "1106368:4"
		body.global_position = Vector3(-60,0.6394,10)
		stage.set_observer(body)
		stage.seed_membership_at(body.global_position,cell_id)
		bolts.configure_collision(stage,body)
		check(str(bolts.actor_cell_at(point))==cell_id,"Elevated weapon inherits persistent actor cell, not floor classification")
		var hit: Dictionary = {}
		var direction := Vector3.ZERO
		for angle in range(0,360,15):
			direction = Vector3.FORWARD.rotated(Vector3.UP,deg_to_rad(angle))
			hit = bolts.trace(point,point+direction*30,cell_id)
			if not hit.is_empty(): break
		check(not hit.is_empty(),"Actual-stage wall/floor collision available")
		if not hit.is_empty():
			var before := events.size()
			bolts.spawn(shot,Transform3D(Basis.looking_at(direction),point),point-direction*0.01)
			bolts._physics_process(1)
			check(events.size()==before+1 and bolts.bolts.is_empty(),"Projectile stops against actual imported stage geometry")
	# Presentation pool exhaustion never discards authoritative shot simulation.
	bolts.configure_collision(null)
	bolts.max_visuals = bolts.visual_allocated
	var previous_allocations: int = bolts.visual_allocated
	for count in range(8):
		bolts.spawn(short_shot,Transform3D(Basis.IDENTITY,Vector3(100,100,100)),Vector3(100,100,100))
	check(bolts.bolts.size()==8 and bolts.visual_drops>0,"Visual capacity does not drop simulated shots")
	bolts._physics_process(1)
	check(bolts.bolts.is_empty() and bolts.visual_allocated==previous_allocations,"Native projectile handle budget remains bounded")
	var assets: Dictionary = rig.assets.catalog
	check(assets.weapons.size()==catalog.weapons.size() and assets.failures.is_empty(),"All original model/effect/audio exports complete")
	check(rig.weapons[0].visual.get_child(0) is MeshInstance3D,"Held model built from original geometry")
	check(assets.weapons.pistol_dl44.muzzle[2]<0,"Original muzzle hardpoint drives projectile origin")
	await process_frame
	await process_frame
	world.queue_free()
	var particle_manager := root.get_node_or_null("SwgOptimizedParticles")
	if particle_manager != null: particle_manager.queue_free()
	await create_timer(0.12).timeout
	await process_frame
	var report := {"test":"ranged_combat_foundation","checks":checks,"errors":failures,"passed":failures.is_empty(),"hardware_tested":false,"backend_combat_tested":false}
	FileAccess.open(ProjectSettings.globalize_path("res://../runtime/evidence/ranged-combat-smoke.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
