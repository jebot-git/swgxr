extends RefCounted
## Confirmed action feedback only: polling and uncertain mutations stay silent.
const HandInput=preload("res://scripts/tracked_hand_input.gd")
const FAMILIES=["/inventory/","/crafting/","/gathering/","/medic/","/scout/","/services/","/vehicles/","/entertainer/"]
const READS=["status","inspect","list","catalog","options","presence","snapshot","preview","search","nearby","poll"]
var last_pulse_ms:=-1000
static func confirmed(path:String,body:Dictionary,response:Dictionary)->bool:
	if not response.get("ok",false) or not FAMILIES.any(func(prefix):return path.begins_with(prefix)):return false
	var verb:=path.get_slice("?",0).get_file()
	var action:=str(body.get("action",verb))
	for value:String in [verb,action]:
		if value in READS or value.get_slice("_",value.get_slice_count("_")-1) in READS:return false
	var mutation:Variant=response.get("mutation")
	return mutation is Dictionary and mutation.get("success",false)==true
static func choose_hand(origin:Node,fallback:String)->String:
	if not is_instance_valid(origin):return fallback
	var strongest:=.5;var side:=fallback
	for hand:String in ["left","right"]:
		var controller:=origin.get_node_or_null(hand.capitalize()+"Hand") as XRController3D
		if not is_instance_valid(controller) or not HandInput.controller_tracked(controller):continue
		var amount:=maxf(controller.get_float("trigger"),controller.get_float("grip"))
		if amount>strongest:strongest=amount;side=hand
	return side
func receipt(origin:Node,focused:bool,path:String,body:Dictionary,response:Dictionary,side:String)->void:
	if not focused or not confirmed(path,body,response) or not is_instance_valid(origin) or Time.get_ticks_msec()-last_pulse_ms<80:return
	var controller:=origin.get_node_or_null(side.capitalize()+"Hand") as XRController3D
	if not is_instance_valid(controller) or not HandInput.controller_tracked(controller):return
	controller.trigger_haptic_pulse("haptic",0,.22,.035,0)
	last_pulse_ms=Time.get_ticks_msec()
