extends SceneTree
## Actual streamed Tatooine geometry and native physics contacts; no server RPCs.
const Actor=preload("res://combat/live_actor.gd")
const Assets=preload("res://scripts/inventory_assets.gd")
const Projectiles=preload("res://combat/projectiles.gd")
var contacts:Array=[]
var impacts:Array=[]
var errors:Array=[]
func check(ok:bool,message:String)->void:
	if not ok:errors.append(message);push_error(message)
func _initialize()->void:call_deferred("run")
func run()->void:
	var app:Node3D=load("res://scripts/main.gd").new();root.add_child(app)
	var deadline:=Time.get_ticks_msec()+90000
	while not app.world_ready and Time.get_ticks_msec()<deadline:await process_frame
	var report:Dictionary={"passed":false,"world_ready":app.world_ready,"gpu_tested":false,"real_http_requests":0}
	if app.world_ready:
		app.player.set_physics_process(false)
		var saved:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/evidence/live-nearby-asset-preflight.json"))
		var record:Dictionary=saved.snapshot.actors.filter(func(value):return str(value.template).contains("worrt_hue"))[-1].duplicate(true)
		var assets:=Assets.new();assets.configure();var dead:=Assets.new();dead.configure(ProjectSettings.globalize_path("res://../runtime/assets/corpses/catalog.json"))
		var actor:=Actor.new();app.add_child(actor);actor.set_process(false)
		check(actor.configure(record,"offline-contact-fixture",assets,dead,ProjectSettings.globalize_path("res://../runtime/assets/combat_population/mos_eisley_easy/catalog.json")),"Original worrt configures")
		var origin:Array=app.stage.get_meta("manifest").origin
		var actor_position:=Vector3(float(record.position[0])-float(origin[0]),float(record.position[1])-float(origin[1]),-(float(record.position[2])-float(origin[2])))
		actor.apply_record(record,Transform3D(Basis(Vector3.UP,-float(record.heading_radians)),actor_position),0.2,true)
		await physics_frame;await physics_frame
		var rounds:=Projectiles.new();app.add_child(rounds);rounds.set_physics_process(false);rounds.configure_collision(app.stage,app.player);rounds.excluded.append(app.player.get_rid())
		rounds.authoritative_contact.connect(func(shot,target,position,normal,distance):contacts.append({"shot":shot,"target":target,"position":position,"normal":normal,"distance":distance}))
		rounds.impact.connect(func(value):impacts.append(value))
		var target:=actor.to_global(actor.collider.position)
		var grip:Vector3=app.player.global_position+Vector3.UP*1.3
		var direction:Vector3=(target-grip).normalized()
		var muzzle:=Transform3D(Basis.looking_at(direction),grip+direction*0.2)
		var membership:Variant=rounds.actor_cell_at(grip)
		var query:=PhysicsRayQueryParameters3D.create(grip,target,8);query.exclude=[app.player.get_rid()]
		var dynamic:Dictionary=app.get_world_3d().direct_space_state.intersect_ray(query)
		var world_trace:Dictionary=app.stage.combat_collision.trace_segment(grip,target,str(membership),7)
		var muzzle_trace:Dictionary=rounds.trace_query(grip,muzzle.origin,str(membership))
		var whole_trace:Dictionary=rounds.trace_query(grip,target,str(membership))
		report.merge({"player":app.player.global_position,"target":target,"actor_position":actor.global_position,"bounds":actor.visual_bounds(),"cell":membership,"native_collision":app.stage.combat_collision.statistics(),"direct_dynamic_hit":not dynamic.is_empty(),"world_trace":world_trace,"grip_muzzle_trace":muzzle_trace,"whole_trace":whole_trace,"stage_cell":app.stage.current_cell},true)
		var shot:Dictionary={"weapon_id":"pistol_fwg5","item_id":str(saved.snapshot.weapon.item_id),"shot_id":"offline-source-contact","live_session":"offline-contact-fixture","sequence":1,"range":float(saved.snapshot.weapon.max_range_m),"speed":float(saved.snapshot.weapon.projectile_speed)}
		rounds.spawn(shot,muzzle,grip)
		for tick in range(120):
			if rounds.bolts.is_empty():break
			rounds._physics_process(1.0/120.0)
		report["contacts"]=contacts;report["impacts"]=impacts;report["incomplete_queries"]=rounds.incomplete_queries
		check(not dynamic.is_empty() and dynamic.collider==actor,"Real physics ray hits original worrt collider")
		check(world_trace.get("complete",false),"Authored streamed world/terrain coverage is complete to worrt")
		check(muzzle_trace.get("complete",false) and not muzzle_trace.get("hit",false),"Actual source grip-to-muzzle path is complete and clear")
		check(contacts.size()==1 and contacts[0].target.id==str(record.id),"Swept projectile pipeline emits one actual native-identity contact")
		check(actor.record.health==record.health and actor.record.dead==record.dead,"Client projectile never grants local damage or death")
		report["passed"]=errors.is_empty()
	report["errors"]=errors
	print(JSON.stringify(report));FileAccess.open("res://../runtime/evidence/live-stage-projectile.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	app.queue_free();await process_frame;quit(0 if report.passed else 1)
