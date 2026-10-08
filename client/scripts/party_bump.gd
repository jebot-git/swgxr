extends RefCounted
## Local eligibility and duplicate suppression only. The authenticated presence hub owns contact proof;
## Core3 owns party membership; losing tracking never manufactures a fresh gesture.
var submitted:Dictionary={}
func reset()->void:submitted.clear()
static func hand_sample(position:Array,tracked:bool,grip:float,trigger:float,free:bool)->Dictionary:
	return {"position":position,"tracked":tracked,"fist":tracked and free and grip>=.65 and trigger>=.65,"free":tracked and free}
static func free_hand(side:String,context:Dictionary)->bool:
	if context.get("blocked",true) or side in context.get("occupied",[]):return false
	return side in ["left","right"]
func take_ready(owner:String,records:Array)->Dictionary:
	if not owner.is_valid_int():return {}
	for peer:Dictionary in records:
		var target:=str(peer.get("id",""));var gesture:=str(peer.get("group_bump_id",""))
		if not peer.get("group_bump_ready",false) or not target.is_valid_int() or int(owner)>=int(target) or gesture.is_empty() or submitted.has(gesture):continue
		# A server gesture ID is a bounded opaque receipt, never a target supplied
		# by UI text or an arbitrary nearby avatar.
		if gesture.length()!=24 or not gesture.is_valid_hex_number():continue
		submitted[gesture]=true
		if submitted.size()>64:submitted.erase(submitted.keys()[0])
		return {"target_id":target,"group_bump_id":gesture,"request_id":"bump_"+gesture}
	return {}
