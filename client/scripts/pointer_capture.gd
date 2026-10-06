extends RefCounted
## Nested diegetic panels share suspension of the stock XR Tools pointers.
static func suspend(owner:Node,rig:Node,value:bool)->void:
	if not is_instance_valid(rig):return
	for side:String in ["LeftHand","RightHand"]:
		var pointer:Node=rig.get_node_or_null(side+"/FunctionPointer")
		if pointer==null:continue
		var claims:Dictionary=pointer.get_meta("swg_pointer_claims",{})
		for id in claims.keys():
			if claims[id].get_ref()==null:claims.erase(id)
		if value:
			if claims.is_empty():pointer.set_meta("swg_pointer_enabled",pointer.enabled)
			claims[owner.get_instance_id()]=weakref(owner)
		else:claims.erase(owner.get_instance_id())
		pointer.set_meta("swg_pointer_claims",claims)
		if not claims.is_empty():pointer.enabled=false
		elif pointer.has_meta("swg_pointer_enabled"):
			pointer.enabled=pointer.get_meta("swg_pointer_enabled");pointer.remove_meta("swg_pointer_enabled")
