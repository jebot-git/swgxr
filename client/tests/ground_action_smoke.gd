extends SceneTree
const Controller=preload("res://combat/action_combat.gd")
const Timeline=preload("res://combat/action_timeline.gd")
class Height extends RefCounted:
	func sample_height(x:float,z:float)->float:return x*x*.025+sin(z)*.2
class Terrain extends Node3D:
	var evaluator:=Height.new()
class Host extends Node3D:
	var terrain:=Terrain.new()
class Mapping extends Node:
	func world(p:Array)->Vector3:return Vector3(p[0],p[1],p[2])
var errors:Array=[]
var checks:=0
func check(value:bool,label:String)->void:
	checks+=1
	if not value:errors.append(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	var clock=preload("res://combat/action_clock.gd").new()
	check(clock.observe(1,101.05,101.25,1.3),"Clock accepts four timestamps")
	check(is_equal_approx(clock.offset,100.) and is_equal_approx(clock.best_delay,.1),"Server work is excluded from clock delay")
	check(not clock.observe(2,102.2,102.2,2.5),"Queued sample cannot displace better clock")
	var host:=Host.new();root.add_child(host);host.add_child(host.terrain)
	var sync:=Mapping.new();root.add_child(sync)
	var c:=Controller.new();root.add_child(c);c.app=host;c.sync=sync;c.set_process(false)
	var event:Dictionary={"protocol":2,"state_revision":1,"sequence":50,"id":"7","encounter_id":"7","attack_id":"1","target_id":"9","eligible_victim_ids":["9"],"role":"ranged","hit_policy":"first_contact","cell_id":"0","origin":[0,0,0],"direction":[1,0,0],"range":12.,"radius":.45,"cosine":.5,"server_now":10.,"age_ms":0.,"start":10.,"delivery_at":11.4,"active_at":11.733,"end_at":11.9,"recover_at":13.8,"animation_end_at":12.4,"aim_revision":1,"aim_locked":true,"lock_at":10.9,"phase":"windup"}
	var special:=event.duplicate(true);special.shape="circle";special.geometry_origin=[20,0,0];special.range=8.;special.special=true;special.target_required=false;special.hit_policy="cleave"
	check(Timeline.contact(special,Vector3(20,0,-7)),"Splash contact uses its warned impact centre")
	check(not Timeline.contact(special,Vector3.ZERO),"Splash excludes attacker origin outside the impact radius")
	var area:=c.draw_warning(special);c.update_fill(area,special,11.,Color.PURPLE)
	var area_vertices:PackedVector3Array=area.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	check(area_vertices.size()>48,"Special area warning is a subdivided circle")
	for vertex in area_vertices:check(Vector2(vertex.x-20,vertex.z).length()<=8.01,"Area drawing matches contact radius and centre")
	special.shape="cone";special.geometry_origin=[0,0,0];special.cosine=.5
	check(Timeline.contact(special,Vector3(4,0,5)) and not Timeline.contact(special,Vector3(0,0,-4)),"Ranged special cone uses its cone rather than a thin lane")
	special.shape="targeted";special.target_required=true;special.eligible_victim_ids=["9"]
	check(Timeline.contact(special,Vector3(-7,0,0)),"Target-bound effect checks native reach rather than dodgable lane")
	check(c.timeline.eligible(special,"9") and not c.timeline.eligible(special,"10"),"Explicit target cannot transfer to another player")
	var camera:=Camera3D.new();root.add_child(camera);camera.current=true
	c.cue_textures["ui/target_aim.png"]=area.get_node("TargetCue/Target").texture
	c.update_targeted_cue(true,.8)
	check(c.targeted_cue.visible and c.targeted_cue.texture!=null,"Existing reticle identifies targeted special near the player's view")
	c.update_targeted_cue(false,0);check(not c.targeted_cue.visible,"Targeted indicator clears when the threat ends")
	area.queue_free();camera.queue_free()
	var mesh:=c.draw_warning(event);c.update_fill(mesh,event,11.,Color.ORANGE)
	var target:Sprite3D=mesh.get_node("TargetCue/Target");var danger:Sprite3D=mesh.get_node("TargetCue/Danger")
	check(target.texture!=null and danger.texture!=null,"Original SWG targeting and attack icons load")
	c.update_cues(mesh,true,false,false)
	check(target.visible and not danger.visible and target.modulate!=Color.WHITE,"Targeted player sees amber tracking icon")
	c.update_cues(mesh,false,true,false)
	check(not target.visible and danger.visible,"Bystander stepping into lane sees danger icon")
	c.update_cues(mesh,true,true,true)
	check(target.visible and danger.visible and target.modulate==Color.WHITE,"Locked aim and contact risk remain distinct icons")
	c.update_cues(mesh,false,false,false)
	check(not target.visible and not danger.visible,"Uninvolved player has no warning icon clutter")
	var fill:Mesh=mesh.get_node("ProgressFill").mesh
	var vertices:PackedVector3Array=fill.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	check(vertices.size()>6,"Lane is subdivided for heightmap projection")
	for p:Vector3 in vertices:
		check(absf(p.y-host.terrain.evaluator.sample_height(p.x,p.z)-.065)<.00001,"Every mesh vertex follows heightmap")
		check(p.x>=0 and p.x<=12.*(1./1.4)+.0001 and absf(p.z)<=.451,"Projection keeps progressive horizontal footprint")
	check(Timeline.contact(event,Vector3(4,6,0)),"V2 footprint is horizontal; cell and native LOS fence elevation")
	var timeline:=Timeline.new();timeline.ingest(event,0)
	var update:=event.duplicate(true);update.sequence=1;update.state_revision=2;update.phase="active";timeline.ingest(update,1.5)
	check(timeline.attacks["7:1"].event.phase=="active","Critical replay uses native state revision, independent of cache sequence")
	var actor=preload("res://combat/live_actor.gd").new()
	actor.apply_action_event(event,3);actor.apply_action_event(update,3)
	check(actor.ground_state_revision==2,"Actor pose accepts recovered state with lower transport sequence")
	actor.apply_action_event(event,2)
	check(actor.action_event_epoch==3,"Old scene epoch cannot replace action pose")
	c.timeline.clock_ready=true;c.timeline.server_offset=100
	check(not c.presentation_receipt("lock",event,3).has("presented_at"),"Older server receives its existing receipt schema")
	c.integration_timestamps=true
	check(c.presentation_receipt("lock",event,3).presented_at==103,"Negotiated receipts carry actual client presentation time")
	actor.free()
	print(JSON.stringify({"passed":errors.is_empty(),"checks":checks,"errors":errors,"renderer":"dummy","live_test":false}));quit(0 if errors.is_empty() else 1)
