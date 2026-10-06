extends RefCounted
## One consumable offhand selection, independent of weapon and medical state.
var selection: Dictionary={}
var device_id:=""
var pet_id:=""
var aiming:=false
var trigger_down:=true
var captured:=false
func clear()->void:
	selection={};device_id="";pet_id="";aiming=false
func reset()->void:
	clear();trigger_down=true;captured=false
func select(entry:Dictionary,device:String,pet:String)->void:
	selection=entry.duplicate(true);device_id=device;pet_id=pet;aiming=false
	trigger_down=true # Selecting while the opening trigger is held cannot fire.
func click(value:float,permitted:bool)->bool:
	if not permitted or not is_finite(value):trigger_down=true;return false
	var next:=trigger_down
	if value<.25:next=false;captured=false
	elif value>.65:next=true
	var edge:=next and not trigger_down;trigger_down=next
	return edge
func activate(target:String="")->Dictionary:
	if selection.is_empty():return {}
	captured=true
	if selection.get("requires_target",false):
		if not aiming:aiming=true;return {}
		if target.is_empty():return {}
	var proposal:Dictionary={"device_id":device_id,"command_id":int(selection.command_id)}
	if selection.get("requires_target",false):proposal.target_id=target
	clear()
	return proposal
