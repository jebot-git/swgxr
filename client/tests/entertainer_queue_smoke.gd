extends SceneTree
class Host extends Node:
	var live_combat: Node
	var gameplay_session: Node
	var calls: Array = []
	func api(_method:int,path:String,payload:Dictionary)->Dictionary:
		calls.append({"path":path,"payload":payload.duplicate(true)})
		await get_tree().create_timer(.02).timeout
		return {"ok":true}
class Performer extends Node:
	var item: Dictionary={"id":"123"}
	var message:=""
class Native extends "res://entertainment/native_controller.gd":
	var permitted:=true
	func bound()->bool:return true
	func allowed()->bool:return permitted
	func identity()->Dictionary:return {}
	func accept(_reply:Dictionary)->bool:return true
var failures:Array=[]
func check(ok:bool,label:String)->void:
	if not ok:failures.append(label);push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	var host:=Host.new();root.add_child(host)
	var performer:=Performer.new();host.add_child(performer)
	var native:=Native.new();host.add_child(native);native.set_process(false);native.set_physics_process(false);native.host=host;native.performer=performer
	native.request("status")
	check(native.busy,"Native status occupies transport")
	var result:Dictionary=await native.request("perform",{"performance_id":"music:starwars1:slitherhorn"})
	check(result.get("queued",false) and native.pending_actions.size()==1,"Gesture is queued behind native status")
	await native.request("perform",{"performance_id":"music:starwars1:slitherhorn"})
	check(native.pending_actions.size()==1,"Same pending gesture deduplicated")
	await create_timer(.04).timeout
	native.flush_pending_actions()
	await create_timer(.04).timeout
	check(host.calls.size()==2 and host.calls[1].path=="/entertainer/perform","Queued gesture dispatches once after status")
	check(host.calls[1].payload.item_id=="123" and not str(host.calls[1].payload.request_id).is_empty(),"Native command retains owned instrument and receipt")
	native.busy=true
	await native.request("perform",{"performance_id":"music:starwars1:slitherhorn"})
	performer.item={"id":"999"};native.busy=false;native.flush_pending_actions()
	check(host.calls.size()==2 and performer.message.contains("changed"),"Switching instrument cancels stale queued performance")
	native.busy=true
	await native.request("stop")
	native.reset()
	check(native.pending_actions.is_empty(),"Session reset removes pending native actions")
	var report:Dictionary={"test":"entertainer_native_action_queue","passed":failures.is_empty(),"failures":failures,"native_transport":"mocked","renderer":"dummy"}
	FileAccess.open("res://../runtime/evidence/entertainer-queue-smoke.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "));print(JSON.stringify(report))
	host.free();quit(0 if failures.is_empty() else 1)
