extends SceneTree
const Haptics=preload("res://scripts/action_haptics.gd")
const Main=preload("res://scripts/main.gd")
var checks:=0
func check(value:bool,label:String)->void:
	checks+=1
	if not value:push_error(label);quit(1);assert(value,label)
func _initialize()->void:
	var success:Dictionary={"ok":true,"mutation":{"success":true}}
	for path:String in ["/inventory/equip","/crafting/assemble","/gathering/deploy","/medic/heal","/scout/trap","/services/bazaar_buy","/vehicles/board","/entertainer/perform"]:
		check(Haptics.confirmed(path,{},success),"Confirmed action feedback: "+path)
	for path:String in ["/inventory/status","/services/status","/gathering/inspect","/session/update","/combat/session/melee","/combat/session/impact","/performance","/services/house_harvester_status","/scout/ranger_status","/services/slicing_status","/services/house_preview"]:
		check(not Haptics.confirmed(path,{},success),"No polling or duplicate combat haptics: "+path)
	check(not Haptics.confirmed("/scout/action",{"action":"status"},success),"Nested polling stays silent")
	check(not Haptics.confirmed("/crafting/assemble",{},{"ok":true,"mutation":{"success":false}}),"Rejected mutation stays silent")
	check(not Haptics.confirmed("/crafting/assemble",{},{"ok":true}),"HTTP success alone is not confirmed action")
	check(not Haptics.confirmed("/crafting/assemble",{},{"ok":false,"mutation":{"success":true}}),"Transport failure stays silent")
	print(JSON.stringify({"checks":checks,"test":"action_haptics","hardware_tested":false}));quit()
