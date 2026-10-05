extends "res://scripts/main.gd"
var reply: Dictionary={}
var calls: Array=[]
var reconciliations:=0
var reconciliation_started_pending:=false
var change_epoch:=false
func _ready() -> void: pass
func _process(_delta: float) -> void: pass
func _physics_process(_delta: float) -> void: pass
func api(method: HTTPClient.Method,path: String,payload: Dictionary={}) -> Dictionary:
	calls.append({"method":method,"path":path,"payload":payload.duplicate(true)})
	await get_tree().process_frame
	if change_epoch: datapad_epoch+=1
	return reply.duplicate(true)
func refresh_inventory() -> void:
	reconciliations+=1
	reconciliation_started_pending=inventory.action_pending if is_instance_valid(inventory) else false
	await get_tree().process_frame
func sync_inventory_equipment(_force_statistics := false) -> void: pass
