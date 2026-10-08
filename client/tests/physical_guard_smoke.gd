extends SceneTree
const Guard=preload("res://combat/physical_guard.gd")
const Rig=preload("res://combat/ranged_rig.gd")
class Host extends Node:
	func source_position_at(p:Vector3)->Vector3:return Vector3(100+p.x,p.y,200-p.z)
var checks:=0
func check(value:bool,label:String)->void:
	checks+=1
	if not value:push_error(label);quit(1);assert(value,label)
func _initialize()->void:
	var guard:=Guard.new()
	var left:=Vector3(-.2,-.15,-.3);var right:=Vector3(.2,-.15,-.3)
	check(Guard.qualifies("boxing",left,right,Vector3.UP,"right"),"Two fists protect the face")
	check(not Guard.qualifies("boxing",left,Vector3(.2,-.8,-.3),Vector3.UP,"right"),"Dropped fist opens guard")
	check(not Guard.qualifies("boxing",right,left,Vector3.UP,"left"),"Crossed wrists do not become boxing guard")
	check(Guard.qualifies("parry",left,right,Vector3.RIGHT,"left"),"Left-handed cross-body parry")
	check(Guard.qualifies("parry",left,right,Vector3.UP,"right"),"Upright parry")
	check(not Guard.qualifies("parry",left,right,Vector3.FORWARD,"right"),"Forward stab is not a parry")
	guard.sample(.02,"boxing",left,right,Vector3.UP,"right","123")
	check(guard.current.mode=="none","Guard must settle")
	for i in range(8):guard.sample(.02,"boxing",left,right,Vector3.UP,"right","123")
	check(guard.current.mode=="boxing","Held pose arms guard")
	guard.sample(.02,"boxing",left,right+Vector3(.15,0,0),Vector3.UP,"right","123")
	check(guard.current.mode=="none","Fast punch immediately cancels guard")
	for i in range(9):guard.sample(.02,"parry",left,right,Vector3.UP,"right","123")
	check(guard.current.mode=="parry","Weapon guard settles")
	guard.sample(.02,"parry",left,right,Vector3.UP,"right","456")
	check(guard.current.mode=="none","Weapon switch re-arms guard")
	guard.clear();check(guard.current=={"mode":"none"},"Tracking loss releases guard")
	guard.sample(.5,"boxing",left,right,Vector3.UP,"right","123")
	check(guard.current.mode=="none","Frame stall cannot arm guard")
	var rig:=Rig.new();var host:=Host.new()
	rig.allowed=true;rig.guard_head=Vector3(0,1.7,0);rig.guard_forward=Vector3.FORWARD
	rig.physical_guard.current={"mode":"boxing","main":"right","item_id":"","left":[-.2,-.15,-.3],"right":[.2,-.15,-.3],"axis":[0,1,0]}
	rig.guard_sample_ms=Time.get_ticks_msec()
	var payload:Dictionary=rig.guard_payload(host,{"item_id":"123"})
	check(payload.mode=="boxing" and payload.item_id=="123" and payload.forward==[0.0,0.0,1.0],"Guard direction uses source coordinates and native unarmed item")
	rig.guard_sample_ms=Time.get_ticks_msec()-200
	check(rig.guard_payload(host,{"item_id":"123"})=={"mode":"none"},"Stopped tracking sampling cannot refresh a stale guard")
	rig.guard_sample_ms=Time.get_ticks_msec();rig.allowed=false
	check(rig.guard_payload(host,{"item_id":"123"})=={"mode":"none"},"UI/focus lock immediately releases guard")
	rig.free();host.free()
	print(JSON.stringify({"test":"physical_guard","checks":checks,"mocked_poses":true,"hardware_tested":false,"native_executed":false}))
	quit()
