extends SceneTree
const Trigger=preload("res://medic/focus_trigger.gd")
class App extends Node:
	var datapad_epoch:=1
	var world_ready:=true
class Bag extends Node3D:
	var is_open:=false
	var action_pending:=false
class Wheel extends Node3D:
	var menu_open:=false
class Medic extends "res://medic/controller.gd":
	var permitted:=true
	var calls:Array=[]
	var recipient:="patient"
	var mutation:=""
	func allowed()->bool:return permitted
	func aim()->Transform3D:return Transform3D.IDENTITY
	func candidates(_entry:Dictionary)->Array:
		return [{"id":recipient,"eligible":true,"position":Vector3(0,0,-2),"bounds":[AABB(Vector3(-.3,-.3,-2.2),Vector3(.6,.6,.4))]}] if not recipient.is_empty() else []
	func request(action:String,detail:Dictionary={})->Dictionary:
		calls.append({"action":action,"detail":detail.duplicate(true)})
		await get_tree().process_frame
		if action=="select":
			selected=str(detail.ability)
			match mutation:
				"aim":recipient="other"
				"stow":held={}
				"focus":permitted=false
				"epoch":app.datapad_epoch+=1
				"world":app.world_ready=false
		return {"ok":mutation!="rejected"}
var checks:=0
var errors:Array[String]=[]
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:errors.append(label);push_error(label)
func _initialize()->void:
	create_timer(30).timeout.connect(func():quit(2));call_deferred("run")
func run()->void:
	for hz in [45.0,72.0,90.0,120.0]:
		for long_press in [false,true]:
			var trigger:=Trigger.new();var actions:Array=[]
			trigger.sample(1/hz,0,true)
			for i in range(int(hz*(2 if long_press else .15))):
				var result:=trigger.sample(1/hz,1,true)
				if not result.is_empty():actions.append(result)
			var released:=trigger.sample(1/hz,0,true)
			if not released.is_empty():actions.append(released)
			check(actions==["quickheal" if long_press else "tenddamage"],"Exactly one action for tap/hold at %s Hz: %s"%[hz,long_press])
	for mode in ["focus","tracking_gap","menu","draw_pressed"]:
		var trigger:=Trigger.new();var actions:Array=[]
		if mode!="draw_pressed":
			trigger.sample(.01,0,true);trigger.sample(.1,1,true)
			trigger.sample(.2 if mode=="tracking_gap" else .01,1,mode=="tracking_gap")
		for i in range(100):
			var result:=trigger.sample(.01,1,true)
			if not result.is_empty():actions.append(result)
		check(actions.is_empty() and trigger.sample(.01,0,true).is_empty(),"Interrupted or already-held trigger requires fresh release: "+mode)
	var medic:=Medic.new();root.add_child(medic);medic.set_process(false)
	medic.app=App.new();medic.add_child(medic.app);medic.bag=Bag.new();medic.add_child(medic.bag);medic.wheel=Wheel.new();medic.add_child(medic.wheel);medic.body=CharacterBody3D.new();medic.add_child(medic.body)
	for mode in ["tap","hold","unlearned","cooldown","menu","stale","unfocused","aim","stow","focus","epoch","world","rejected"]:
		medic.calls.clear();medic.focus_trigger.reset();medic.held={"id":"tool"};medic.selected="";medic.age=0;medic.permitted=mode!="unfocused";medic.recipient="patient";medic.mutation=mode
		medic.app.world_ready=true
		medic.wheel.menu_open=mode=="menu"
		medic.state={"abilities":[{"id":"tenddamage","range_m":6,"cooldown_seconds":0},{"id":"quickheal","range_m":6,"cooldown_seconds":0}]}
		if mode=="unlearned":medic.state.abilities=[]
		if mode=="cooldown":medic.state.abilities[0].cooldown_seconds=4
		if mode=="stale":medic.age=5
		medic.sample_focus_trigger(.01,0)
		for i in range(100 if mode=="hold" else 10):medic.sample_focus_trigger(.01,1)
		medic.sample_focus_trigger(.01,0)
		await process_frame;await process_frame;await process_frame
		var heals:Array=medic.calls.filter(func(row):return row.action=="heal")
		check(heals.size()==(1 if mode in ["tap","hold"] else 0),"Production dispatch and cancellation: "+mode)
		if not heals.is_empty():check(heals[0].detail=={"item_id":"tool","ability":"quickheal" if mode=="hold" else "tenddamage","target_id":"patient"},"Select and heal use exact tool, ability and aimed recipient: "+mode)
	medic.free();await process_frame
	var report:Dictionary={"passed":errors.is_empty(),"checks":checks,"errors":errors,"renderer":"dummy","mocked_tracking":true,"native_transport":"mocked","live_xr":false}
	print(JSON.stringify(report));FileAccess.open("res://../runtime/evidence/medical-focus-trigger.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "));quit(0 if errors.is_empty() else 1)
