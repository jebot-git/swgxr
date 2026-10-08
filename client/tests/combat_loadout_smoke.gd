extends SceneTree
const Hologram=preload("res://scripts/equipment_hologram.gd")
const Loadout=preload("res://combat/loadout.gd")
const Inventory=preload("res://scripts/xr_inventory.gd")
class Player extends CharacterBody3D:
	func set_interface_capture(_move:bool,_turn:bool)->void:pass
var checks:=0
var errors:Array[String]=[]
var proposals:Array=[]
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:errors.append(message);push_error(message)
func _initialize()->void:call_deferred("run")
func fixture()->Dictionary:
	var value:Dictionary={"item_id":"99","ability_loadout":{"family":"pistols","slots":["lethal_shot","","",""],"ultimate":"","revision":1},"ability_catalog":[]}
	for id:String in ["lethal_shot","low_blow","restraining_shot","concussion_shot_improved","last_ditch"]:
		value.ability_catalog.append({"id":id,"label":id.replace("_"," ").capitalize(),"ultimate":id=="last_ditch","activation":"native_ranged","cooldown_seconds":30,"max_range_m":40})
	return value
func find(ui:Node3D,kind:String,id:="",index:=-1)->Dictionary:
	for row:Dictionary in ui.tiles:
		if row.kind==kind and (id.is_empty() or row.id==id) and (index<0 or row.index==index):return row
	return {}
func aim(row:Dictionary)->Transform3D:
	var node:Node3D=row.node
	return Transform3D(node.global_basis,node.global_position+node.global_basis.z*.3)
func confirm(ui:Node3D,value:Dictionary)->void:
	var snapshot:Dictionary=ui.context.duplicate(true);snapshot.ability_loadout=value.duplicate(true);snapshot.ability_loadout.revision+=1
	ui.observe(snapshot);ui.finish(true,"")
func drag_to(ui:Node3D,source:Dictionary,target:Dictionary)->void:
	ui.sample(aim(source),0,0,true);ui.sample(aim(source),1,0,true);ui.sample(aim(target),1,0,true);ui.sample(aim(target),0,0,true)
func run()->void:
	var world:=Node3D.new();root.add_child(world)
	var source:=preload("res://scripts/avatar.gd").new();world.add_child(source);var report:Dictionary=source.configure("human_male");source.set_process(false);source.hide()
	check(str(report.get("error","")).is_empty(),"Original avatar loaded")
	var hologram:=Hologram.new();world.add_child(hologram);hologram.configure(source,[]);hologram.set_ability_context(fixture());hologram.show_equipment(Transform3D.IDENTITY)
	var ui:Node3D=hologram.ability_editor;ui.proposed.connect(func(value):proposals.append(value.duplicate(true)))
	ui.toggle()
	check(ui.active and ui.tiles.filter(func(row):return row.kind=="slot").size()==4,"Exactly four combat slots above avatar")
	check(ui.tiles.filter(func(row):return row.kind=="ability").size()==4 and ui.tiles.filter(func(row):return row.kind=="ultimate").size()==1,"Separate regular grid and ultimate row")
	check(ui.lines.get_child_count()==1,"Only confirmed equipped slot draws anatomical connector")
	check(not hologram.labels[0].visible and hologram.equipped_at(Vector3.ZERO).is_empty(),"Ability editor reserves equipment pane and grip targets")
	var learned:=find(ui,"ability","low_blow");var destination:=find(ui,"slot","",1)
	ui.sample(aim(learned),1,0,true)
	check(ui.drag.is_empty(),"Held grip on open cannot start a drag")
	drag_to(ui,learned,destination)
	check(proposals.size()==1 and proposals[0].loadout.slots==["lethal_shot","low_blow","",""],"Drag/drop proposes ability into requested slot")
	check(ui.context.ability_loadout.slots[1]=="" and ui.pending and ui.lines.get_child_count()==1,"No optimistic equip or connector before Core3 confirms")
	ui.sample(aim(learned),0,0,true);ui.sample(aim(learned),1,0,true)
	check(proposals.size()==1 and ui.drag.is_empty(),"Pending save blocks repeated input")
	confirm(ui,proposals[0].loadout)
	check(ui.lines.get_child_count()==2 and ui.context.ability_loadout.slots[1]=="low_blow","Confirmed snapshot updates body connectors")
	var old:Dictionary=ui.context.ability_loadout.duplicate(true)
	drag_to(ui,find(ui,"slot","",1),find(ui,"slot","",0))
	check(proposals.back().loadout.slots==["low_blow","lethal_shot","",""],"Dragging equipped slots swaps without duplicates")
	ui.finish(false,"Rejected by Core3")
	check(ui.context.ability_loadout==old and hologram.labels[1].text=="Rejected by Core3","Rejected save retains confirmed layout and reports rejection")
	var ultimate:=find(ui,"ultimate","last_ditch")
	ui.sample(aim(ultimate),0,0,true);ui.sample(aim(ultimate),0,1,true)
	check(proposals.back().loadout.ultimate=="last_ditch" and proposals.back().loadout.slots==old.slots,"Ultimate click selects independently of four slots")
	confirm(ui,proposals.back().loadout)
	check(Loadout.equipped({"id":"last_ditch"},ui.context.ability_loadout),"Only selected ultimate is equipped")
	check(not Loadout.equipped({"id":"restraining_shot"},ui.context.ability_loadout),"Learned but unequipped regular ability is unavailable")
	check(not Loadout.equipped({"id":"other_ultimate","ultimate":true},ui.context.ability_loadout),"Other ultimate is unavailable")
	var count:=proposals.size();ui.sample(aim(find(ui,"ability","low_blow")),0,0,true);ui.sample(aim(find(ui,"ability","low_blow")),1,0,true)
	var heartbeat:Dictionary=ui.context.duplicate(true)
	heartbeat.ability_catalog[0].cooldown_remaining_seconds=3;heartbeat.ability_catalog[0].conditions_met=false;heartbeat.ability_catalog[0].damage_multiplier=4.2
	ui.observe(heartbeat)
	check(not ui.drag.is_empty(),"Cooldown/state/HAM heartbeat cannot cancel an in-progress drag")
	ui.sample(Transform3D.IDENTITY,0,0,false)
	check(ui.drag.is_empty() and proposals.size()==count,"Tracking loss cancels drag without saving")
	ui.sample(aim(find(ui,"ability","low_blow")),1,0,true)
	check(ui.drag.is_empty(),"Grip must release after tracking returns")
	drag_to(ui,find(ui,"slot","",1),find(ui,"ability","restraining_shot"))
	check(proposals.back().loadout.slots[1]=="","Dragging slot back to inventory clears it")
	confirm(ui,proposals.back().loadout)
	var other:=fixture();other.item_id="101";other.ability_loadout.family="carbines";other.ability_loadout.slots=["","","",""]
	ui.observe(other)
	check(ui.context.ability_loadout.family=="carbines" and ui.lines.get_child_count()==0,"Weapon-family switch uses its own confirmed slots")
	other.ability_loadout.family="2h_melee";other.ability_catalog=[];ui.observe(other)
	check(ui.tiles.size()==4 and "No learned abilities" in hologram.labels[1].text,"Melee family has four slots without fabricated native abilities")
	var many:=fixture()
	for i in range(12):many.ability_catalog.append({"id":"extra_%d"%i,"label":"Extra %d"%i,"ultimate":false})
	for i in range(4):many.ability_catalog.append({"id":"ultimate_%d"%i,"label":"Ultimate %d"%i,"ultimate":true})
	ui.observe(many);ui.scroll(99)
	check(ui.page==2 and not find(ui,"ability","extra_11").is_empty() and not find(ui,"ultimate","ultimate_3").is_empty(),"Pagination reaches all combat abilities and ultimates")
	var xr:=XROrigin3D.new();world.add_child(xr);var camera:=XRCamera3D.new();camera.name="XRCamera3D";xr.add_child(camera)
	for side in ["LeftHand","RightHand"]:var hand:=XRController3D.new();hand.name=side;xr.add_child(hand)
	var body:=Player.new();world.add_child(body)
	var inventory:=Inventory.new();world.add_child(inventory);inventory.configure(xr,body,"right");inventory.set_process(false);inventory.allowed=true
	inventory.set_equipment_context(source,[]);inventory.browse_equipment(Transform3D.IDENTITY);inventory.set_combat_loadout_context(fixture(),Callable())
	inventory.sample_ability_editor(true,Transform3D.IDENTITY,0,0,true)
	check(not inventory.hologram.ability_editor.active,"Held right stick cannot open editor")
	inventory.sample_ability_editor(false,Transform3D.IDENTITY,0,0,true);inventory.sample_ability_editor(true,Transform3D.IDENTITY,0,0,true)
	check(inventory.hologram.ability_editor.active and inventory.blocks_combat(),"Fresh physical right stick opens editor for left-handed setup and blocks combat")
	inventory.update_gestures(true,Transform3D.IDENTITY,Transform3D.IDENTITY,1,1,{},Transform3D.IDENTITY)
	check(inventory.equipment_drag.is_empty(),"Ability editor prevents equipment pickup gestures")
	inventory.sample_ability_editor(false,Transform3D.IDENTITY,0,0,true);inventory.sample_ability_editor(true,Transform3D.IDENTITY,0,0,true)
	check(not inventory.hologram.ability_editor.active and inventory.hologram.active,"Second click returns to equipment hologram")
	print(JSON.stringify({"checks":checks,"passed":errors.is_empty(),"errors":errors,"renderer":"dummy","native_transport":"mocked","live_xr":false}))
	world.free();quit(0 if errors.is_empty() else 1)
