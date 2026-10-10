extends Node3D
## Local equipment-hologram editor. All changes wait for Core3 confirmation.
signal proposed(value:Dictionary)
const Loadout=preload("res://combat/loadout.gd")
const Targets=preload("res://combat/target_abilities.gd")
const FONT=preload("res://resources/fonts/Jupiteroid-Regular.ttf")
const DESCRIPTIONS={"concussion_shot_improved":"Disrupts the target with concussion control effects.","lethal_shot":"A high-damage ranged attack.","low_blow":"A disabling low attack.","restraining_shot":"Slows the target's movement.","last_ditch":"An emergency damage attack. Spends remaining Action and Mind down to 1; damage increases as your pools fall."}
var hologram:Node3D
var context:Dictionary={}
var active:=false
var pending:=false
var page:=0
var tiles:Array[Dictionary]=[]
var lines:Node3D
var grid:Node3D
var slots_root:Node3D
var ghost:Node3D
var drag:Dictionary={}
var grip_armed:=false
var trigger_armed:=false
var hovered:=""
var context_key:=""
func setup(owner_hologram:Node3D)->void:
	hologram=owner_hologram
	grid=Node3D.new();add_child(grid);grid.transform=hologram.panels[0].transform
	slots_root=Node3D.new();add_child(slots_root)
	lines=Node3D.new();add_child(lines);hide()
func observe(value:Dictionary)->void:
	var incoming:=value.duplicate(true)
	for ability:Dictionary in incoming.get("ability_catalog",[]):
		ability.erase("cooldown_remaining_seconds");ability.erase("conditions_met");ability.erase("damage_multiplier")
	var key:=JSON.stringify([incoming.get("item_id",""),incoming.get("ability_loadout",{}),incoming.get("ability_catalog",[])])
	context=incoming
	if key==context_key:return
	context_key=key;cancel_drag();grip_armed=false;trigger_armed=false;page=0
	if active:rebuild()
func resize_grid_panel(height:float)->void:
	for panel:Node3D in hologram.panels:
		var mesh:MeshInstance3D=panel.get_child(0)
		mesh.mesh.size=Vector2(.27,height)
	var detail:Label3D=hologram.labels[1]
	var expanded:=height>.36
	detail.font_size=18 if expanded else 22
	detail.pixel_size=.00065 if expanded else .00075
	detail.width=360 if expanded else 320
	detail.position.y=.215 if expanded else .165
func toggle()->void:
	active=not active;visible=active;cancel_drag();grip_armed=false;trigger_armed=false
	resize_grid_panel(.47 if active else .36)
	for marker:Node3D in hologram.markers.values():marker.visible=not active
	hologram.labels[0].visible=not active
	if active:rebuild()
	else:
		if hologram.browsing:
			hologram.labels[0].text="EQUIPPED ITEMS\n\nGrip an item to move it.\n\nCombat abilities button below"
			hologram.labels[1].text="SELECT EQUIPMENT\n\nItems remain equipped until Core3 confirms their return to inventory."
		else:hologram.update_comparison(hologram.highlighted)
func cancel_drag()->void:
	drag={}
	if is_instance_valid(ghost):ghost.queue_free();ghost=null
func close()->void:
	active=false;hide();cancel_drag();grip_armed=false;trigger_armed=false
	resize_grid_panel(.36)
	hologram.labels[0].show()
	for marker:Node3D in hologram.markers.values():marker.show()
func label(parent:Node3D,text:String,at:Vector3,size:=18)->Label3D:
	var node:=Label3D.new();parent.add_child(node);node.font=FONT;node.text=text;node.font_size=size;node.pixel_size=.00065;node.position=at;node.outline_size=0;node.modulate=Color("c9fbff");node.render_priority=10;return node
func tile(parent:Node3D,at:Vector3,title:String,kind:String,id:String,index:=-1,selected:=false)->Node3D:
	var node:=Node3D.new();parent.add_child(node);node.position=at
	var mesh:=MeshInstance3D.new();var quad:=QuadMesh.new();quad.size=Vector2(.115,.06);mesh.mesh=quad;node.add_child(mesh)
	var material:=StandardMaterial3D.new();material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;material.albedo_color=Color("17665a") if selected else Color("10344a");mesh.material_override=material
	var text:=label(node,title,Vector3(0,-.008,.002),16);text.width=160;text.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	if Targets.POINTS.has(id):
		var icon:=MeshInstance3D.new();node.add_child(icon);icon.mesh=Targets.icon_mesh(str(Targets.POINTS[id].part));icon.scale=Vector3.ONE*.105;icon.position=Vector3(0,.019,.003);icon.material_override=Targets.material()
	tiles.append({"node":node,"kind":kind,"id":id,"index":index,"selected":selected});return node
func definition(id:String)->Dictionary:
	for ability:Dictionary in context.get("ability_catalog",[]):
		if str(ability.get("id",""))==id:return ability
	return {}
func is_gesture(row:Dictionary)->bool:return row.get("category","")=="gesture"
func is_ultimate(row:Dictionary)->bool:return row.get("ultimate",false) or row.get("id","")=="last_ditch"
func rebuild()->void:
	for parent:Node3D in [grid,slots_root,lines]:
		for child in parent.get_children():parent.remove_child(child);child.queue_free()
	tiles.clear();hovered=""
	var loadout:Dictionary=context.get("ability_loadout",{})
	var family:=str(loadout.get("family",""))
	label(slots_root,(family.replace("_"," ").to_upper() if not family.is_empty() else "NO WEAPON LOADOUT")+"  /  4 TARGETED + 1 ULTIMATE",Vector3(0,.725,0),19)
	var slots:Array=loadout.get("slots",["","","",""])
	for i in range(4):
		var id:=str(slots[i]) if slots.size()==4 else ""
		var entry:=definition(id)
		var node:=tile(slots_root,Vector3((i-1.5)*.124,.66,.01),str(entry.get("label","Empty")),"slot",id,i,not id.is_empty())
		if not id.is_empty() and Targets.POINTS.has(id):
			var point:Dictionary=Targets.POINTS[id];var anchor:Variant=hologram.bone_anchor(point.bones)
			if not anchor is Vector3:anchor=Vector3(0,float(point.height)*hologram.HEIGHT,0)
			var connector:=MeshInstance3D.new();lines.add_child(connector);connector.mesh=Targets.line_mesh([node.position-Vector3(0,.03,0),Vector3(anchor)+Vector3(0,0,.025)]);connector.material_override=Targets.material()
	label(grid,"COMBAT ABILITIES",Vector3(0,.212,.005),20)
	var regular:Array=[];var ultimates:Array=[];var gestures:Array=[]
	for entry:Dictionary in context.get("ability_catalog",[]):
		if is_gesture(entry):gestures.append(entry)
		elif is_ultimate(entry):ultimates.append(entry)
		else:regular.append(entry)
	for i in range(page*6,mini(regular.size(),(page+1)*6)):
		var row:Dictionary=regular[i];var index:=i-page*6
		tile(grid,Vector3(-.061+(index%2)*.122,.160-(index/2)*.068,.006),str(row.get("label",row.id)),"ability",str(row.id),-1,str(row.id) in slots)
	label(grid,"ULTIMATES — ADVANCED",Vector3(0,-.027,.005),18)
	for i in range(page*2,mini(ultimates.size(),(page+1)*2)):
		var row:Dictionary=ultimates[i]
		tile(grid,Vector3(-.061+(i-page*2)*.122,-.071,.006),str(row.get("label",row.id)),"ultimate",str(row.id),-1,str(row.id)==str(loadout.get("ultimate","")))
	label(grid,"GESTURES — NO SLOT",Vector3(0,-.117,.005),18)
	for i in range(page*2,mini(gestures.size(),(page+1)*2)):
		var row:Dictionary=gestures[i]
		tile(grid,Vector3(-.061+(i-page*2)*.122,-.161,.006),str(row.get("label",row.id)),"gesture",str(row.id))
	label(grid,"%d/%d  •  STICK TO PAGE"%[page+1,page_count()],Vector3(0,-.208,.006),14)
	hologram.labels[1].text="ABILITY LOADOUT\n\n"+("No learned abilities for this weapon family." if regular.is_empty() and ultimates.is_empty() and gestures.is_empty() else "Point at an ability for details.\n\nGrip and drag a combat ability to a slot above your head.\n\nClick an ultimate to select it.\n\nPoint at a gesture for its trigger. No slot needed.")+"\n\nEquipment button below"
func page_count()->int:
	var regular:=0;var ultimate:=0;var gesture:=0
	for row:Dictionary in context.get("ability_catalog",[]):
		if is_gesture(row):gesture+=1
		elif is_ultimate(row):ultimate+=1
		else:regular+=1
	return maxi(1,maxi(ceili(gesture/2.0),maxi(ceili(regular/6.0),ceili(ultimate/2.0))))
func scroll(direction:int)->void:
	if not drag.is_empty() or pending:return
	page=clampi(page+direction,0,page_count()-1);rebuild()
func hit(pose:Transform3D,pointer:Dictionary={})->Dictionary:
	var nearest:=INF;var found:Dictionary={}
	for entry:Dictionary in tiles:
		var node:Node3D=entry.node;var local:Vector3=node.to_local(pointer.get("ray_origin",pose.origin))
		var direction:Vector3=node.global_basis.inverse()*Vector3(pointer.get("direction",-pose.basis.z))
		var distance:=0.0
		if absf(local.z)>.04:
			if absf(direction.z)<.001:continue
			distance=-local.z/direction.z
			if distance<0:continue
			local+=direction*distance
		if absf(local.x)<=.0575 and absf(local.y)<=.03 and distance<nearest:nearest=distance;found=entry
	return found
func describe(id:String)->void:
	if id==hovered:return
	hovered=id;var row:=definition(id)
	if row.is_empty():return
	if is_gesture(row):
		hologram.labels[1].text=str(row.get("label",id))+"\n\n"+str(row.get("description",""))+"\n\nTRIGGER\n"+str(row.get("trigger_description",""))+"\n\n"+str(row.get("weapon_requirement",""))+"\n\nNo targeting slot required."
		return
	var ultimate:=is_ultimate(row)
	var part:=str(Targets.POINTS.get(id,{}).get("part",""))
	var requirement:="Requires "+str(row.get("profession_requirement","an advanced profession"))+".\n" if ultimate else ""
	hologram.labels[1].text=str(row.get("label",id))+"\n\n"+str(row.get("description",DESCRIPTIONS.get(id,"")))+"\n\n"+requirement+(str(row.get("trigger_description","Ultimate: both hands on weapon, press both triggers.")) if ultimate else "Target: "+part.capitalize())+"\n\nCooldown: %.1f s"%float(row.get("cooldown_seconds",0))+("\nSelf" if row.get("self_only",false) else "\nRange: %.1f m"%float(row.get("max_range_m",0)))+"\n\n"+("Click to select" if ultimate else "Grip, drag, release over a slot")
func submit(value:Dictionary)->void:
	if pending or value.is_empty() or value==context.get("ability_loadout",{}):return
	value["revision"]=int(value.get("revision",-1))
	pending=true;hologram.labels[1].text="Saving loadout in Core3…";proposed.emit({"item_id":str(context.get("item_id","")),"loadout":value})
func finish(success:bool,message:String)->void:
	pending=false
	if active:rebuild();hologram.labels[1].text="Loadout equipped." if success else message
func sample(pose:Transform3D,grip:float,trigger:float,tracked:bool,pointer:Dictionary={})->void:
	if not active:return
	if not tracked or pending:cancel_drag();grip_armed=false;trigger_armed=false;return
	var pointed:=hit(pose,pointer)
	for entry:Dictionary in tiles:
		entry.node.get_child(0).material_override.albedo_color=Color("247b94") if entry==pointed else Color("17665a") if entry.selected else Color("10344a")
	if not pointed.is_empty():describe(str(pointed.id))
	if trigger<.2:trigger_armed=true
	elif trigger>=.75 and trigger_armed:
		trigger_armed=false
		if drag.is_empty() and pointed.get("kind","")=="ultimate":
			var value:Dictionary=context.get("ability_loadout",{}).duplicate(true)
			value["ultimate"]="" if str(value.get("ultimate",""))==str(pointed.id) else str(pointed.id);submit(value);return
	if grip<.35:
		grip_armed=true
		if not drag.is_empty():
			var value:Dictionary={};var source:=int(drag.get("index",-1)) if drag.kind=="slot" else -1
			if pointed.get("kind","")=="slot":value=Loadout.assign(context.get("ability_loadout",{}),str(drag.id),int(pointed.index),source)
			elif source>=0 and absf(grid.to_local(pose.origin).x)<.15 and absf(grid.to_local(pose.origin).y)<.19 and absf(grid.to_local(pose.origin).z)<.1:
				value=context.get("ability_loadout",{}).duplicate(true);value.slots[source]=""
			elif source>=0 and pointed.get("kind","") in ["ability","ultimate","gesture"]:
				value=context.get("ability_loadout",{}).duplicate(true);value.slots[source]=""
			cancel_drag();submit(value)
	elif grip>=.65 and grip_armed and drag.is_empty():
		grip_armed=false
		if pointed.get("kind","") in ["ability","slot"] and not str(pointed.get("id","")).is_empty():
			drag=pointed.duplicate();ghost=Node3D.new();add_child(ghost);label(ghost,str(definition(str(drag.id)).get("label",drag.id)),Vector3.ZERO,20)
	if is_instance_valid(ghost):ghost.global_transform=pose;ghost.global_position-=pose.basis.z*.09
