extends SceneTree
class Body extends CharacterBody3D:
	var feedback=preload("res://combat/player_feedback.gd").new()
class Enemy extends StaticBody3D:
	var record:Dictionary={"id":"enemy","relation":"hostile","dead":false}
	func core3_identity()->Dictionary:return {"id":"enemy","targetable":true}
	func is_targetable()->bool:return not record.dead
	func visual_bounds()->AABB:return AABB(Vector3(-.25,-.5,-.2),Vector3(.5,1,.4))
var checks:=0
var errors:Array=[]
var dispatched:Array=[]
func check(value:bool,label:String)->void:
	checks+=1
	if not value:errors.append(label);push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	var body:=Body.new();root.add_child(body)
	var head:=Camera3D.new();body.add_child(head);head.position=Vector3(0,1.7,0)
	var rig:=preload("res://combat/ranged_rig.gd").new();root.add_child(rig)
	check(rig.configure(head,body,[]),"Original weapon rig initializes")
	rig.set_process(false);rig.set_physics_process(false)
	var fixture:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/evidence/professions/fixture.json"))
	var profile:Dictionary=fixture.weapons.pistol_cdef.duplicate(true);profile.source_kind="core3_weapon_instance";profile.item_id="202";profile.certified=true
	rig.set_equipped_inventory_weapons([profile]);rig.draw(0)
	var enemy:=Enemy.new();root.add_child(enemy);enemy.position=Vector3(0,1.4,-4);enemy.collision_layer=8;enemy.collision_mask=0;enemy.add_to_group("swg_radar_contacts")
	var collision:=CollisionShape3D.new();enemy.add_child(collision);collision.shape=BoxShape3D.new();collision.shape.size=Vector3(.5,1,.4)
	await physics_frame;await physics_frame
	var physical:=Transform3D(Basis.IDENTITY,Vector3(0,1.4,-.3));var saved:=physical;var body_saved:=body.global_transform;var head_saved:=head.global_transform
	body.feedback.spice.observe(preload("res://tests/spice_smoke.gd").envelope("booster_blue","active"))
	rig.pose_weapon(physical,Transform3D.IDENTITY)
	check(rig.spice_gunhand.locked_id=="enemy","Actual weapon reticle ray acquires native hostile collider")
	enemy.position.x=1;rig.pose_weapon(physical,Transform3D.IDENTITY)
	var expected:Vector3=(enemy.global_position-physical.origin).normalized();var muzzle:Transform3D=rig.muzzle_pose(0)
	check((-muzzle.basis.z).dot(expected)>.9999 and muzzle.basis.is_equal_approx(rig.weapons[0].visual.global_basis),"Visible original weapon and actual shot muzzle follow the same locked target basis")
	rig.shot_authority=func(_shot,pose,_grip):dispatched.append(pose);return {}
	rig.dispatch_shot({"sequence":1},muzzle,physical.origin,profile,false)
	check(dispatched.size()==1 and dispatched[0]==muzzle,"Native firing boundary receives the actual spice-adjusted muzzle")
	check(physical==saved and body.global_transform==body_saved and head.global_transform==head_saved,"Sticky aim cannot mutate physical controller copies, HMD or player body")
	enemy.record.relation="neutral";rig.spice_gunhand.reset();rig.pose_weapon(physical,Transform3D.IDENTITY)
	check(rig.spice_gunhand.locked_id.is_empty(),"Neutral actor cannot become an aim target from perceived hostility")
	var opaque:=StaticBody3D.new();root.add_child(opaque);opaque.position=Vector3(0,1.4,-1);opaque.collision_layer=1
	var obstruction:=CollisionShape3D.new();opaque.add_child(obstruction);obstruction.shape=BoxShape3D.new();obstruction.shape.size=Vector3(2,2,.2)
	enemy.record.relation="hostile";enemy.position.x=0;await physics_frame;await physics_frame;rig.spice_gunhand.reset();rig.pose_weapon(physical,Transform3D.IDENTITY)
	check(rig.spice_gunhand.locked_id.is_empty(),"Opaque scenery prevents initial reticle acquisition")
	check(preload("res://scripts/crafting_controller.gd").experimentation_label(0)=="Amazing Success" and preload("res://scripts/crafting_controller.gd").experimentation_label(-1).is_empty(),"Muon native experimentation result keeps Amazing Success label and no invented result")
	rig.free();enemy.free();opaque.free();body.free();await process_frame
	print(JSON.stringify({"checks":checks,"errors":errors,"renderer":"dummy","original_weapon":true,"native_transport":"mocked","headset_validated":false}));quit(0 if errors.is_empty() else 1)
