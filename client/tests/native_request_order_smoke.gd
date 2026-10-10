extends SceneTree
class Services extends Node3D:
	var point:=[1,0,0]
	var cell:=1
	func identity_payload()->Dictionary:return {"zone":"tatooine","position":point,"building_id":"10","cell_index":cell}
class Host extends "res://scripts/main.gd":
	var received:Array=[]
	var replies:Array=[]
	var active:=0
	var maximum:=0
	func _ready()->void:pass
	func _process(_delta:float)->void:pass
	func _physics_process(_delta:float)->void:pass
	func _api_dispatch(_method:HTTPClient.Method,path:String,body:Dictionary={})->Dictionary:
		active+=1;maximum=maxi(maximum,active);received.append({"path":path,"body":body.duplicate(true)})
		for i in range(3):await get_tree().process_frame
		active-=1
		return {"ok":true}
	func send(path:String,body:Dictionary)->void:replies.append(await api(HTTPClient.METHOD_POST,path,body))
var errors:Array=[]
func check(value:bool,label:String)->void:
	if not value:errors.append(label);push_error(label)
func _initialize()->void:run.call_deferred()
func run()->void:
	var host:=Host.new();root.add_child(host);host.services=Services.new();host.add_child(host.services);host.world_ready=true
	var pose:Dictionary={"position":[0,0,0],"zone":"tatooine","building_id":"10","cell_index":1,"item_id":"200","left_hand":[0,.5,0]}
	host.send("/session/update",pose)
	host.send("/services/house_recover",pose)
	for i in range(10):await process_frame
	check(host.maximum==1 and host.replies.size()==2,"Native requests serialize through receipt completion")
	check(host.received[1].body.position==[1,0,0] and host.received[1].body.item_id=="200" and host.received[1].body.left_hand==[0,.5,0],"Queued locomotion refresh keeps explicit recovery intent")
	host.send("/session/update",pose);host.send("/services/house_recover",pose);host.services.cell=2
	for i in range(10):await process_frame
	check(host.received.size()==3 and host.replies[-1].get("cancelled",false),"Queued economic action cannot follow a room transition")
	check(host.native_api_queue.is_empty(),"Request queue drains after rejection")
	host.free();print(JSON.stringify({"errors":errors,"native":"mocked","renderer":"dummy"}));quit(0 if errors.is_empty() else 1)
