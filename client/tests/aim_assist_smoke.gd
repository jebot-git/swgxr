extends SceneTree
const Assist=preload("res://combat/aim_assist.gd")
class CandidateWorld extends "res://combat/live_world.gd":
	var ready_for_test:=true
	func is_ready()->bool:return ready_for_test
class Actor extends StaticBody3D:
	var session_id:="owned-session"
	var snapshot_usec:=0
	var visual:Node3D
	var collider:CollisionShape3D
	var record:Dictionary={"id":"101","kind":"creature","relation":"hostile","dead":false}
	func is_targetable()->bool:return true
	func core3_identity()->Dictionary:return record
var checks:=0
var failures:Array=[]
var assist:=Assist.new()
var pose:=Transform3D.IDENTITY
var profile:Dictionary={"class":"pistol","delivery":"bolt","core3":{"maxRange":50}}
var shot:Dictionary={"range":50}
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);push_error(label)
func _initialize()->void:call_deferred("run")
func trace(from:Vector3,to:Vector3)->Dictionary:
	var query:=PhysicsRayQueryParameters3D.create(from,to,15);query.hit_from_inside=true
	var result:=root.world_3d.direct_space_state.intersect_ray(query)
	result["complete"]=true;result["hit"]=result.has("collider")
	return result
func actor_at(at:Vector3)->Actor:
	var actor:=Actor.new();actor.collision_layer=8
	actor.visual=Node3D.new();actor.add_child(actor.visual)
	actor.collider=CollisionShape3D.new();actor.collider.shape=BoxShape3D.new();actor.collider.shape.size=Vector3(.6,1.5,.6);actor.add_child(actor.collider)
	root.add_child(actor);actor.position=at;return actor
func wall_at(at:Vector3,size:Vector3)->StaticBody3D:
	var wall:=StaticBody3D.new();wall.collision_layer=1
	var shape:=CollisionShape3D.new();shape.shape=BoxShape3D.new();shape.shape.size=size;wall.add_child(shape);root.add_child(wall);wall.position=at;return wall
func run()->void:
	var actor:=actor_at(Vector3(.44,0,-20))
	await physics_frame;await physics_frame
	var authority:=CandidateWorld.new();authority.session_id="owned-session";authority.actors={"101":actor}
	actor.snapshot_usec=Time.get_ticks_usec()-100000
	var bound:Array=authority.aim_assist_candidates()
	check(bound.size()==1 and bound[0].age_seconds>=.1,"Authority callback preserves observation age rather than refreshing at trigger")
	authority.ready_for_test=false
	check(authority.aim_assist_candidates().is_empty(),"Unready authority yields no assist candidates")
	authority.ready_for_test=true;actor.session_id="old-session"
	check(authority.aim_assist_candidates().is_empty(),"Previous session identities cannot attract assistance")
	actor.session_id="owned-session";actor.snapshot_usec=0
	check(authority.aim_assist_candidates()[0].age_seconds==INF,"Missing observation timestamp fails stale")
	authority.free()
	var rows:Array=[{"actor":actor,"age_seconds":.1}]
	var result:=assist.correct(pose,profile,shot,rows,trace)
	check(not result.is_empty() and result.degrees>0 and result.degrees<=.5,"Near silhouette miss receives at most half a degree of correction")
	if not result.is_empty():check(trace(pose.origin,result.pose.origin-result.pose.basis.z*50).get("collider")==actor,"Corrected ray strikes unchanged actual body collider")
	check(pose==Transform3D.IDENTITY and actor.position==Vector3(.44,0,-20),"Aim assistance leaves caller pose and target untouched")
	check(Assist.angular_limit(.15)==.5 and Assist.angular_limit(.3)<.5 and Assist.angular_limit(.5)==0 and Assist.angular_limit(INF)==0,"Stale data fades conservatively; invalid age disables assist")
	rows[0].age_seconds=.4
	check(assist.correct(pose,profile,shot,rows,trace).is_empty(),"Old target observation cannot use the full cone")
	rows[0].age_seconds=.1
	actor.visual.hide()
	check(assist.correct(pose,profile,shot,rows,trace).is_empty(),"Separately hidden mount visual cannot attract aim assistance")
	actor.visual.show();actor.collision_layer=0
	check(assist.correct(pose,profile,shot,rows,trace).is_empty(),"Out-of-cell collision suppression immediately prevents assistance")
	actor.collision_layer=8;actor.hide()
	check(assist.correct(pose,profile,shot,rows,trace).is_empty(),"Hidden parent prevents assistance")
	actor.show();actor.collider.disabled=true
	check(assist.correct(pose,profile,shot,rows,trace).is_empty(),"Disabled body collider prevents assistance")
	actor.collider.disabled=false
	for relation:String in ["friendly","neutral","party"]:
		actor.record.relation=relation;check(assist.correct(pose,profile,shot,rows,trace).is_empty(),"No assistance towards "+relation)
	actor.record.relation="hostile"
	for flag:String in ["dead","incapacitated","pet"]:
		actor.record[flag]=true;check(assist.correct(pose,profile,shot,rows,trace).is_empty(),"No assistance towards "+flag);actor.record[flag]=false
	for delivery:String in ["guided","cone","beam","melee","scatter"]:
		var special:=profile.duplicate(true);special.delivery=delivery
		check(assist.correct(pose,special,shot,rows,trace).is_empty(),"Special delivery remains unmodified: "+delivery)
	check(assist.correct(pose,profile,{"range":50,"ability_id":"eye_shot"},rows,trace).is_empty(),"Anatomical abilities retain their own physical targeting")
	check(assist.correct(pose,profile,{"range":50,"aim_point":Vector3.ZERO},rows,trace).is_empty(),"Explicit aim points retain their own intent")
	check(assist.correct(pose,profile,shot,rows,func(_from:Vector3,_to:Vector3):return {"complete":false}).is_empty(),"Missing collision data fails closed")
	actor.position.x=.8;await physics_frame;await physics_frame
	check(assist.correct(pose,profile,shot,rows,trace).is_empty(),"Far miss does not snap to target")
	actor.position.x=0;await physics_frame;await physics_frame
	check(assist.correct(pose,profile,shot,rows,trace).is_empty(),"Direct hits are never recentered")
	actor.position.x=.44;await physics_frame;await physics_frame
	check(assist.correct(pose,profile,{"range":10},rows,trace).is_empty(),"Target beyond weapon range receives no help")
	actor.rotation.y=PI*.25;await physics_frame;await physics_frame
	var rotated:=assist.correct(pose,profile,shot,rows,trace)
	check(not rotated.is_empty() and trace(pose.origin,rotated.pose.origin-rotated.pose.basis.z*50).get("collider")==actor,"Rotated body uses oriented collider and actual first hit")
	actor.rotation.y=0;await physics_frame;await physics_frame
	var wall:=wall_at(Vector3(.09,0,-10),Vector3(.10,2,.3));await physics_frame;await physics_frame
	check(assist.correct(pose,profile,shot,rows,trace).is_empty(),"Corrected path cannot pass through cover")
	wall.position.x=0;wall.get_child(0).shape.size.x=.04;await physics_frame;await physics_frame
	check(assist.correct(pose,profile,shot,rows,trace).is_empty(),"Assistance cannot bend an obstructed original shot around cover")
	wall.free();await physics_frame;await physics_frame
	var nearer:=actor_at(Vector3(0,0,-5));nearer.record.relation="friendly";await physics_frame;await physics_frame
	check(assist.correct(pose,profile,shot,rows,trace).is_empty(),"An intervening friendly retains the actual shot path")
	nearer.free();await physics_frame;await physics_frame
	var catalog:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/assets/combat/catalog.json"))
	var cdef:Dictionary=catalog.weapons.pistol_cdef.duplicate(true);cdef.item_id="55"
	var body:=CharacterBody3D.new();root.add_child(body)
	var head:=Camera3D.new();body.add_child(head)
	var rig=preload("res://combat/ranged_rig.gd").new();root.add_child(rig)
	check(rig.configure(head,body,[cdef]),"Production CDEF rig configures")
	rig.set_process(false);rig.set_physics_process(false);rig.aim_assist_candidates=func():return rows
	var captured:Array=[]
	rig.shot_authority=func(value:Dictionary,launch:Transform3D,_grip:Vector3):captured.append({"shot":value.duplicate(true),"pose":launch});return value
	var launch:Dictionary={"weapon_id":cdef.id,"core3":cdef.core3,"range":50.,"range_scale":1.,"speed":100.,"condition_fraction":1.}
	check(rig.dispatch_shot(launch,pose,pose.origin,cdef,false),"Assisted CDEF shot dispatches")
	check(captured.size()==1 and captured[0].shot.has("aim_assist_degrees"),"Actual dispatch invokes assist before registering native launch")
	if captured.size()==1:
		check(rig.rounds_sim.bolts.size()==1 and rig.rounds_sim.bolts[0].direction.is_equal_approx(-captured[0].pose.basis.z),"Visual bolt and native request use the identical corrected direction")
	if not rig.rounds_sim.bolts.is_empty():
		var launched_direction:Vector3=rig.rounds_sim.bolts[0].direction
		actor.position.x=8
		rig.rounds_sim._physics_process(.01)
		check(not rig.rounds_sim.bolts.is_empty() and rig.rounds_sim.bolts[0].direction==launched_direction,"Moving target cannot steer a bolt after launch")
		actor.position.x=.44
	check(head.transform==Transform3D.IDENTITY and pose==Transform3D.IDENTITY,"Tracked head and caller muzzle pose never move")
	rig.aim_assist_mode="off";rig.dispatch_shot(launch,pose,pose.origin,cdef,false)
	check(captured.size()==2 and captured[1].pose==pose and not captured[1].shot.has("aim_assist_degrees"),"Off setting leaves emitted direction untouched")
	# Settings persist separately from tracking preferences, using an isolated file.
	var prefs=preload("res://scripts/vr_settings.gd").new();prefs.path="user://aim-assist-smoke.cfg";prefs.aim_assist="off";prefs.save_preferences()
	var saved=preload("res://scripts/vr_settings.gd").new();saved.path=prefs.path;saved.load_preferences()
	check(saved.aim_assist=="off","Aim-assist setting survives reload")
	DirAccess.remove_absolute(prefs.path)
	rig.free();body.free();actor.free();await process_frame
	print(JSON.stringify({"passed":failures.is_empty(),"checks":checks,"failures":failures,"xr":false,"renderer":"dummy","native_transport":"mocked"}))
	quit(0 if failures.is_empty() else 1)
