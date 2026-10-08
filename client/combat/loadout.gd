extends RefCounted
## Authoritative projection and bounded proposals; never grants abilities locally.
static func equipped(ability:Dictionary,loadout:Dictionary)->bool:
	var id:=str(ability.get("id",""))
	if id.is_empty():return false
	if ability.get("ultimate",false) or id=="last_ditch":return id==str(loadout.get("ultimate",""))
	var slots:Array=loadout.get("slots",[])
	return slots.size()==4 and id in slots
static func assign(loadout:Dictionary,id:String,destination:int,source:=-1)->Dictionary:
	var out:=loadout.duplicate(true);var slots:Array=out.get("slots",[])
	if slots.size()!=4 or destination<0 or destination>3:return {}
	var old:=str(slots[destination]);var previous:=slots.find(id)
	if previous>=0:slots[previous]=""
	if source>=0 and source<4:slots[source]=old if source!=destination else id
	slots[destination]=id
	return out
