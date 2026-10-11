extends SceneTree
class Actor extends StaticBody3D:
	var session_id:="owned"
	var record:Dictionary={"attackable":true,"observation_at":10.0}
	var collider:CollisionShape3D
	func is_targetable()->bool:return true
var errors:Array=[]
func check(ok:bool,label:String)->void:
	if not ok:errors.append(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	var stage:=Node3D.new();root.add_child(stage)
	var actor:=Actor.new();stage.add_child(actor);actor.collision_layer=8;actor.position=Vector3(0,1,-1.5)
	actor.collider=CollisionShape3D.new();actor.collider.shape=BoxShape3D.new();actor.collider.shape.size=Vector3(1,2,1);actor.add_child(actor.collider)
	await physics_frame;await physics_frame
	var policy=preload("res://combat/melee_contact.gd");var pose:=Transform3D(Basis.IDENTITY,Vector3(0,1.6,0))
	var hit:Dictionary=policy.pick(stage,{"42":actor},"owned",pose,2)
	check(not hit.is_empty() and hit.target_id=="42" and absf(hit.point.z+1)<.03,"Swing selects the presented collider surface")
	check(policy.pick(stage,{"42":actor},"other",pose,2).is_empty(),"Foreign session cannot be hit")
	actor.position.x=4;await physics_frame;await physics_frame
	check(policy.pick(stage,{"42":actor},"owned",pose,2).is_empty(),"Target outside presented reach remains a whiff")
	actor.position.x=0
	var wall:=StaticBody3D.new();stage.add_child(wall);wall.collision_layer=1;wall.position=Vector3(0,1,-.5)
	var shape:=CollisionShape3D.new();shape.shape=BoxShape3D.new();shape.shape.size=Vector3(3,3,.1);wall.add_child(shape)
	await physics_frame;await physics_frame
	check(policy.pick(stage,{"42":actor},"owned",pose,2).is_empty(),"World wall blocks presented melee selection")
	stage.free();print(JSON.stringify({"passed":errors.is_empty(),"errors":errors,"renderer":"dummy","tracking":"mocked"}));quit(0 if errors.is_empty() else 1)
