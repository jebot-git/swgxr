extends RefCounted
## Selection hints only; Core3 rechecks the item, skill, need, range and consent.
static func eligible(item:Dictionary,person:Dictionary)->bool:
	if not person.get("healable",false):return false
	var command:String=str(item.get("medical_command","healwound" if item.get("wound_medpack",false) else ""))
	if command=="reviveplayer":return not person.get("companion",false) and bool(person.get("dead",false))
	if command in ["healdroiddamage","healdroidwound"]:
		if not person.get("droid",false):return false
	elif person.get("droid",false):return false
	if command=="healpet" and not person.get("companion",false):return false
	if person.get("dead",false):return false
	if command in ["healwound","healdroidwound"]:
		var wounds:Array=person.get("wounds",[]);var attribute:int=0 if command=="healdroidwound" else int(item.get("wound_attribute",-1))
		return attribute>=0 and attribute<wounds.size() and int(wounds[attribute])>0
	if command in ["healstate","curepoison","curedisease","extinguishfire"]:
		return (int(person.get("states",0)) & int(item.get("medical_state",0)))!=0
	return command=="healenhance" or (command in ["healdamage","healpet","healdroiddamage"] and person.get("needs",{}).get("healdamage",false))
