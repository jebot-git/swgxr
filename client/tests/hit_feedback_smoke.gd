extends SceneTree
const Feedback=preload("res://combat/hit_feedback.gd")
class Actor extends Node3D:
	var collider:CollisionShape3D
var failures:Array=[]
func check(ok:bool,message:String)->void:
	if not ok:failures.append(message)
func _initialize()->void:call_deferred("run")
func run()->void:
	check(Feedback.outcome({"success":false,"damage":900}).is_empty(),"Rejected hit cannot invent damage")
	check(Feedback.outcome({"success":true,"damage":0,"resolution":"blocked"}).text=="Blocked","Native block retained")
	check(Feedback.outcome({"success":true,"damage":40,"resolution":"blocked"}).text=="40 · Blocked","Partial block shows remaining damage")
	check(Feedback.outcome({"success":true,"damage":0,"resolution":"resisted"}).text=="Resisted","Explicit native resistance retained")
	check(Feedback.outcome({"success":true,"damage":0,"resolution":"hit","before":{"ham":[100,100,100]},"after":{"ham":[100,63,100]}}).text=="37","Action-pool damage is not reported as a miss")
	check(Feedback.outcome({"success":true,"damage":0}).text=="No damage","Unknown mitigation is not mislabeled as a block")
	var layer:=Feedback.new();root.add_child(layer);layer.set_process(false)
	var point:=Vector3(2,1,-4);layer.present({"success":true,"damage":17},point)
	check(layer.entries.size()==1 and layer.entries[0].label.global_position==point,"Number begins at contact point")
	layer._process(.5);check(layer.entries[0].label.global_position.y>point.y,"Number rises from contact")
	layer._process(1);check(layer.entries.is_empty(),"Feedback expires")
	var live:=preload("res://combat/live_world.gd").new();root.add_child(live);live.set_process(false)
	var actor:=Actor.new();live.add_child(actor);actor.collider=CollisionShape3D.new();actor.add_child(actor.collider)
	actor.collider.shape=BoxShape3D.new();actor.collider.shape.size=Vector3(1,2,1);actor.collider.position=Vector3(3,1,0);live.actors["target"]=actor
	var request:Dictionary={"kind":"impact","payload":{"target_id":"target","origin":[0,1,0]},"feedback_position":Vector3(2.5,1,.1)}
	live.present_hit_result(request,{"success":true,"combat_results":[{"success":true,"target_id":"target","damage":23,"resolution":"hit","position":[3,0,0]}]})
	check(live.hit_feedback.entries.size()==1 and live.hit_feedback.entries[0].label.text=="23" and live.hit_feedback.entries[0].origin==request.feedback_position,"Native receipt uses exact local projectile contact")
	live.present_hit_result({"kind":"warcry","payload":{"origin":[0,1,0]}},{"success":true,"combat_results":[{"success":true,"target_id":"target","damage":0,"resolution":"resisted","position":[3,0,0]},{"success":true,"target_id":"removed","damage":31,"resolution":"hit","position":[5,0,2]}]})
	check(live.hit_feedback.entries.size()==3 and live.hit_feedback.entries[1].label.text=="Resisted" and live.hit_feedback.entries[1].origin==Vector3(2.5,1,0),"Special target feedback appears on the nearest body contact surface")
	check(live.hit_feedback.entries[2].origin==Vector3(5,1,-2),"Removed victim retains feedback using native world position")
	live.present_hit_result(request,{"success":false,"combat_results":[{"success":true,"target_id":"target","damage":999}]})
	check(live.hit_feedback.entries.size()==3,"Rejected mutation cannot display nested hit results")
	live.queue_free()
	layer.queue_free();await process_frame
	print(JSON.stringify({"passed":failures.is_empty(),"failures":failures,"renderer":"dummy","xr":false}));quit(0 if failures.is_empty() else 1)
