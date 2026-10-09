extends Node3D
## Held medical focus owns both friendly treatment and hostile delivery markers.
const Shapes=preload("res://combat/target_abilities.gd")
const Targeting=preload("res://medic/targeting.gd")
const DEFINITIONS={
	"stunned":{"height":.92,"side":-1.,"part":"head","label":"Treat Stun"},
	"dizzy":{"height":.72,"side":-1.,"part":"head","label":"Treat Dizzy"},
	"blinded":{"height":.92,"side":1.,"part":"head","label":"Treat Blind"},
	"intimidated":{"height":.64,"side":1.,"part":"heart","label":"Treat Intimidation"},
	"applypoison":{"height":.76,"side":-1.,"part":"heart","label":"Poison"},
	"applydisease":{"height":.76,"side":1.,"part":"torso","label":"Disease"},
	"applypoison_area":{"height":.46,"side":-1.,"part":"heart","label":"Area Poison"},
	"applydisease_area":{"height":.46,"side":1.,"part":"torso","label":"Area Disease"}
}
var medic:Node3D
var target_id:=""
var focus_id:=""
var mode:="friendly"
var points:Array=[]
var widgets:Dictionary={}
var armed:=false
var pressing:Dictionary={}
func setup(controller:Node3D)->void:medic=controller
func active()->bool:return not target_id.is_empty()
func close()->void:
	target_id="";focus_id="";mode="friendly";points.clear();armed=false;pressing.clear()
	for widget:Node3D in widgets.values():widget.hide()
func permitted()->bool:
	return is_instance_valid(medic) and medic.focus_permitted() and medic.doctor_allowed() and medic.held.get("tool_kind","")=="medical"
func learned(which:String)->bool:
	if which=="friendly":return medic.state.get("doctor",{}).get("healstate",{}).get("learned",false)
	return medic.state.get("combat_medic",{}).get("abilities",[]).any(func(entry):return entry.get("learned",false) and str(entry.get("id","")) in ["applypoison","applydisease"])
func supplies(person:Dictionary,which:="")->Array:
	if which.is_empty():which=mode
	var result:Array=[];var seen:Array=[]
	if not learned(which) or person.get("dead",false):return result
	if which=="friendly":
		if not person.get("healable",false) or not person.get("doctor_needs",{}).get("healstate",false):return result
		for item:Dictionary in medic.state.get("doctor",{}).get("healstate",{}).get("supplies",[]):
			var condition:=str(item.get("state",""))
			if not DEFINITIONS.has(condition) or condition in seen or int(item.get("charges",0))<=0 or (int(person.get("states",0))&int(item.get("state_mask",0)))==0:continue
			var supply:=item.duplicate();supply["ability"]="healstate";supply["range_m"]=float(medic.doctor_entry("healstate").get("range_m",6));supply["area_radius_m"]=0.;result.append(supply);seen.append(condition)
		return result
	if not medic.combat_medic_target_valid(person):return result
	var distance:float=medic.body.global_position.distance_to(medic.app.scout.world(person.position))
	var owned:Array=medic.state.get("combat_medic",{}).get("supplies",[]).duplicate(true)
	# Prefer potency within a delivery variant; never silently replace a single
	# delivery with an area pack. The exact selected pack is shown on its marker.
	owned.sort_custom(func(a,b):return float(a.get("potency",0))>float(b.get("potency",0)) if float(a.get("potency",0))!=float(b.get("potency",0)) else str(a.get("item_id",""))<str(b.get("item_id","")))
	for supply:Dictionary in owned:
		var ability:=str(supply.get("ability",""));var entry:Dictionary=medic.combat_medic_entry(ability)
		if ability not in ["applypoison","applydisease"] or not entry.get("learned",false) or not person.get("ability_available",{}).get(ability,true) or int(supply.get("charges",0))<=0 or float(supply.get("range_m",0))<=0 or distance>float(supply.get("range_m",0)):continue
		var id:=ability+("_area" if float(supply.get("area_radius_m",0))>0 else "")
		if id in seen:continue
		supply["state"]=id;result.append(supply);seen.append(id)
	return result
func person(id:String,which:="")->Dictionary:
	if which.is_empty():which=mode
	var rows:Array=medic.state.get("combat_medic",{}).get("targets",[]) if which=="hostile" else medic.state.get("players",[])+medic.state.get("companions",[])+[medic.state.get("self",{})]
	for row:Dictionary in rows:
		if str(row.get("id",""))==id:return row
	return {}
func candidates(which:="")->Array:
	if which.is_empty():which=mode
	var result:Array=[]
	var rows:Array=medic.state.get("combat_medic",{}).get("targets",[]) if which=="hostile" else medic.state.get("players",[])+medic.state.get("companions",[])+[medic.state.get("self",{})]
	for row:Dictionary in rows:
		var choices:=supplies(row,which)
		if choices.is_empty():continue
		var own:bool=str(row.id)==medic.app.datapad_character_id
		var boxes:Array=medic.combat_medic_bounds(row) if which=="hostile" else medic.patient_bounds(row)
		if boxes.is_empty():continue
		var position:Vector3=medic.body.global_position if own else medic.app.scout.world(row.position)
		var distance:float=medic.body.global_position.distance_to(position);var maximum:=0.
		for supply:Dictionary in choices:maximum=maxf(maximum,float(supply.get("range_m",0)))
		if distance>maximum:continue
		result.append({"id":str(row.id),"eligible":true,"bounds":boxes,"position":position,"range_m":maximum,"mode":which})
	return result
func toggle()->bool:
	if active():close();return true
	if not permitted():return false
	var pose:Transform3D=medic.aim();var options:=candidates("friendly")+candidates("hostile");var maximum:=0.
	for option:Dictionary in options:maximum=maxf(maximum,float(option.range_m))
	var hit:=medic.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(pose.origin,pose.origin-pose.basis.z*(maximum+2),7,[medic.body.get_rid()]))
	var obstruction:float=pose.origin.distance_to(hit.position) if not hit.is_empty() else INF
	if not hit.is_empty():
		for option:Dictionary in options:
			if option.mode=="hostile" and hit.get("collider")==medic.combat_medic_actor(str(option.id)):obstruction=INF;break
	var chosen:=Targeting.first(pose,medic.body.global_position,{"range_m":maximum},options,obstruction)
	if chosen.is_empty():return false
	mode=str(chosen.mode);target_id=str(chosen.id);focus_id=str(medic.held.id);medic.doctor_release_pending=true;medic.focus_trigger.reset();refresh();return true
func line_clear(from:Vector3,to:Vector3)->bool:
	var hit:=medic.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from,to,7,[medic.body.get_rid()]))
	return hit.is_empty() or (mode=="hostile" and hit.get("collider")==medic.combat_medic_actor(target_id))
func refresh()->void:
	points.clear()
	for widget:Node3D in widgets.values():widget.hide()
	if not active():return
	if not permitted() or not learned(mode) or focus_id!=str(medic.held.get("id","")):close();return
	var row:=person(target_id);var choices:=supplies(row)
	var candidate:Dictionary={}
	for value:Dictionary in candidates():
		if str(value.id)==target_id:candidate=value;break
	if candidate.is_empty():close();return
	var boxes:Array=candidate.bounds;var bounds:AABB=boxes[0]
	for box:AABB in boxes:bounds=bounds.merge(box)
	var center:=bounds.get_center();var toward:Vector3=(medic.head.global_position-center).normalized();var right:Vector3=medic.head.global_basis.x.slide(toward).normalized();var up:=toward.cross(right).normalized()
	if right.length_squared()<.9:close();return
	var basis:=Basis(right,up,toward);var front:=0.;var width:=0.
	for index in range(8):
		var offset:=bounds.get_endpoint(index)-center;front=maxf(front,offset.dot(toward));width=maxf(width,absf(offset.dot(right)))
	for supply:Dictionary in choices:
		if medic.body.global_position.distance_to(candidate.position)>float(supply.get("range_m",0)):continue
		var id:=str(supply.state);var definition:Dictionary=DEFINITIONS[id]
		var anchor:Vector3=bounds.position+bounds.size*Vector3(.5,float(definition.height),.5)
		var position:Vector3=center+toward*(front+.025)+up*((float(definition.height)-.5)*bounds.size.y)+right*(float(definition.side)*(width+.18))
		if not line_clear(medic.aim().origin,anchor) or not line_clear(medic.head.global_position,anchor) or not line_clear(medic.aim().origin,position):continue
		points.append({"position":position,"basis":basis,"radius":.105,"item_id":str(supply.item_id),"target_id":target_id,"state":id,"ability":str(supply.ability),"mode":mode,"focus_id":focus_id,"area_radius_m":float(supply.area_radius_m)})
		if not widgets.has(id):widgets[id]=make_widget(id)
		var widget:Node3D=widgets[id];widget.global_transform=Transform3D(basis,position);widget.show()
		var entry:Dictionary=medic.doctor_entry("healstate") if mode=="friendly" else medic.combat_medic_entry(str(supply.ability))
		var cooling:=float(entry.get("cooldown_seconds",0))
		var detail:="" if mode=="friendly" else "\n"+str(supply.get("label","Delivery pack"))+"\n%d charges"%int(supply.charges)+( " · %.1f m radius"%float(supply.area_radius_m) if float(supply.area_radius_m)>0 else " · Single target")
		widget.get_node("Label").text=str(definition.label)+( " · %.1fs"%cooling if cooling>0 else "")+detail
	if not pressing.is_empty() and not points.any(func(point):return same_choice(point,pressing)):pressing.clear();armed=false
func make_widget(id:String)->Node3D:
	var widget:=Node3D.new();add_child(widget)
	var icon:=MeshInstance3D.new();icon.mesh=Shapes.icon_mesh(str(DEFINITIONS[id].part));icon.material_override=Shapes.material();widget.add_child(icon)
	var label:=Label3D.new();label.name="Label";label.font=preload("res://resources/fonts/Jupiteroid-Regular.ttf");label.font_size=24;label.pixel_size=.0016;label.position=Vector3(0,-.14,0);label.modulate=Color("ffb58c") if id.begins_with("apply") else Color("99ffbc");label.no_depth_test=false;widget.add_child(label)
	if id.begins_with("apply"):label.font_size=20;label.pixel_size=.0013;label.width=360;label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	return widget
static func same_choice(a:Dictionary,b:Dictionary)->bool:
	for key:String in ["item_id","target_id","ability","mode","focus_id","state"]:
		if str(a.get(key,""))!=str(b.get(key,"")):return false
	return true
func hit(pose:Transform3D)->Dictionary:
	var direction:Vector3=-pose.basis.z.normalized();var nearest:=INF;var result:Dictionary={}
	for point:Dictionary in points:
		var denominator:float=direction.dot(point.basis.z)
		if absf(denominator)<.001:continue
		var distance:float=(point.position-pose.origin).dot(point.basis.z)/denominator
		if distance<=0 or distance>=nearest or (pose.origin+direction*distance).distance_to(point.position)>float(point.radius):continue
		nearest=distance;result=point
	return result
func sample(delta:float,trigger:float)->void:
	refresh()
	if not active() or not is_finite(delta) or delta<=0 or delta>.15 or not is_finite(trigger):armed=false;pressing.clear();return
	var point:=hit(medic.aim())
	if trigger<.25:
		var ready:=pressing.duplicate();pressing.clear();armed=true
		if not ready.is_empty() and same_choice(point,ready):
			if mode=="friendly":medic.cast_doctor("healstate",str(ready.item_id),str(ready.target_id),focus_id)
			else:medic.cast_combat_medic(str(ready.ability),str(ready.item_id),str(ready.target_id),focus_id)
	elif trigger>.7 and armed:
		armed=false;pressing=point.duplicate()
