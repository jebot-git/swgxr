extends SceneTree
## Production LOS callback against native coverage and Godot actor collision.
const Wave=preload("res://scripts/npc_wave_gesture.gd")
class Stage extends Node3D:
	var combat_collision:=SwgCombatCollision.new()
	var current_cell:Dictionary={}
	func advance_world(_start:Vector3,_end:Vector3,_cell:Dictionary)->Dictionary:return {}
class Host extends Node3D:
	var stage:Node3D
	var player:Node3D
class Actor extends StaticBody3D:
	var record:Dictionary={"id":"42"}
var errors:Array=[]
var checks:=0
func check(value:bool,label:String)->void:
	checks+=1
	if not value:errors.append(label);push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	var host:=Host.new();root.add_child(host);host.player=Node3D.new();host.add_child(host.player)
	host.stage=Stage.new();host.add_child(host.stage);host.stage.combat_collision.configure([])
	host.stage.combat_collision.set_require_terrain(false)
	host.stage.combat_collision.set_geometry("visible",[],AABB(Vector3(-10,-10,-10),Vector3(20,20,20)),1)
	var coordinator:=preload("res://scripts/services_controller.gd").new();host.add_child(coordinator);coordinator.set_process(false);coordinator.app=host
	var actor:=Actor.new();host.add_child(actor);actor.collision_layer=8;actor.collision_mask=0
	var collider:=CollisionShape3D.new();actor.add_child(collider);var box:=BoxShape3D.new();box.size=Vector3(.55,1.8,.4);collider.shape=box;collider.position.y=.9
	await physics_frame;await physics_frame
	var record:Dictionary={"id":"42","kind":"herald","position":Vector3.ZERO}
	for degrees in range(0,360,45):
		actor.rotation.y=deg_to_rad(37+degrees)
		host.player.position=Vector3(sin(deg_to_rad(degrees))*2,0,cos(deg_to_rad(degrees))*2)
		var eye:Vector3=host.player.position+Vector3.UP*1.7
		var head:=Transform3D(Basis.looking_at(Vector3(0,1.4,0)-eye),eye)
		await physics_frame;await physics_frame
		check(Wave.target([record],host.player.position,head,coordinator.wave_line_clear).get("id")=="42","Native LOS accepts target's own collider from azimuth "+str(degrees))
	# Another identity genuinely blocks the sightline instead of being ignored as self.
	var blocker:=Actor.new();host.add_child(blocker);blocker.record={"id":"99"};blocker.collision_layer=8;blocker.position=Vector3(0,0,1)
	var shape:=CollisionShape3D.new();blocker.add_child(shape);var tall:=BoxShape3D.new();tall.size=Vector3(1,3,1);shape.shape=tall;shape.position.y=1.5
	await physics_frame;await physics_frame
	check(not coordinator.wave_line_clear(Vector3(0,1.7,2),Vector3(0,1.4,0),record),"Different actor obstructs NPC interaction")
	host.free();await process_frame
	var report:Dictionary={"passed":errors.is_empty(),"checks":checks,"errors":errors,"renderer":"dummy","geometry":"native trace and Godot physics","headset_tested":false}
	print(JSON.stringify(report));FileAccess.open("res://../runtime/evidence/npc-visibility-smoke.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "));quit(0 if errors.is_empty() else 1)
