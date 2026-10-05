extends "res://scripts/main.gd"
## Main's real session/guard methods with only startup, transport and stage creation stubbed.
var events: Array=[]
var calls: Array=[]
var reply: Dictionary={}
var start_result: Variant=null
func begin_start_test()->void:
	start_result=await start_live_combat()
func _ready()->void: pass
func _process(_delta:float)->void: pass
func _physics_process(_delta:float)->void: pass
func update_buttons()->void: pass
func api(method: HTTPClient.Method,path: String,payload: Dictionary={}) -> Dictionary:
	events.append("api:"+path)
	calls.append({"method":method,"path":path,"payload":payload.duplicate(true),"reserved":live_combat_reserved})
	await get_tree().process_frame
	return reply.duplicate(true)
func guarded_api(method: HTTPClient.Method,path: String,payload: Dictionary={}) -> Dictionary:
	return await super.api(method,path,payload)
func enter_stage(offline: bool,entry: Dictionary={}) -> void:
	events.append("enter_stage")
