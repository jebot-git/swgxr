extends Node3D
## Local support markers and shared Volley orders. Core3 supplies membership,
## availability, expiry and receipts; this presentation grants no combat stats.
const Shapes=preload("res://combat/target_abilities.gd")
const Targeting=preload("res://medic/targeting.gd")
const IDS=["steady_aim","rally","form_up","boost_morale","retreat"]
var rig:Node3D
var authority:Callable
var convert:Callable
var authority_ready:Callable
var context:Dictionary={}
var revision:=""
var observed_usec:=0
var target_id:=""
var item_id:=""
var group_id:=""
var points:Array=[]
var widgets:Dictionary={}
var armed:=false
var pressing:=""
var volley_widget:Node3D
var mark:Dictionary={}
var suppressed_marks:Dictionary={}
var ultimate_input=preload("res://combat/ultimate_input.gd").new()
func setup(value:Node3D)->void:rig=value
func observe(value:Dictionary,key:String,callback:Callable,world:Callable,gate:Callable)->void:
	authority=callback;convert=world;authority_ready=gate
	if revision==key:return
	revision=key;context=value.duplicate(true);observed_usec=Time.get_ticks_usec()
	if not active():return
	if str(context.get("group_id",""))!=group_id or person(target_id).is_empty():close()
func age()->float:return maxf(0,float(Time.get_ticks_usec()-observed_usec)/1000000.)
func active()->bool:return not target_id.is_empty()
func close()->void:
	target_id="";item_id="";group_id="";points.clear();armed=false;pressing=""
	for widget:Node3D in widgets.values():widget.hide()
func permitted()->bool:
	return is_instance_valid(rig) and authority_ready.is_valid() and bool(authority_ready.call()) and age()<4. and rig.allowed and rig.combat_actions_allowed() and rig.inventory_allows_combat() and not rig.ability_ui.menu_open and not (is_instance_valid(rig.datapad) and rig.datapad.is_open) and authority.is_valid()
func current_item()->String:return str(rig.active_profile().get("item_id",""))
func aim()->Transform3D:return rig.muzzle_pose(rig.selected) if rig.selected>=0 and not rig.weapons[rig.selected].state.is_melee() else rig.head.global_transform
func abilities()->Array:
	var result:Array=[]
	for row:Dictionary in context.get("abilities",[]):
		if str(row.get("id","")) in IDS and row.get("learned",false):result.append(row)
	return result
func person(id:String)->Dictionary:
	if str(context.get("group_id","")) in ["","0"]:return {}
	for row:Dictionary in context.get("targets",[]):
		if str(row.get("id",""))==id and row.get("eligible",false) and not row.get("dead",false) and not row.get("incapacitated",false):return row
	return {}
func position(row:Dictionary)->Variant:
	var p:Variant=row.get("position")
	if p is Vector3:return p if p.is_finite() else null
	if not p is Array or p.size()!=3 or not convert.is_valid():return null
	for v in p:
		if not (v is float or v is int) or not is_finite(float(v)):return null
	return convert.call(p)
func bounds(row:Dictionary)->AABB:
	var p:Variant=position(row)
	if not p is Vector3:return AABB()
	var height:=clampf(float(row.get("height_m",1.8)),.4,5.)
	return AABB(p+Vector3(-.28,0,-.28),Vector3(.56,height,.56))
func clear_line(from:Vector3,to:Vector3)->bool:
	var query:Dictionary=rig.target_abilities.query(from,to)
	return query.get("complete",false) and not query.get("hit",false)
func candidates()->Array:
	var result:Array=[]
	if not permitted() or abilities().is_empty():return result
	for row:Dictionary in context.get("targets",[]):
		if person(str(row.get("id",""))).is_empty():continue
		var p:Variant=position(row)
		if not p is Vector3 or rig.body.global_position.distance_to(p)>48.:continue
		result.append({"id":str(row.id),"eligible":true,"position":p,"bounds":[bounds(row)],"range_m":48.})
	return result
func toggle(pose:Transform3D)->bool:
	if active():close();return true
	if not permitted():return false
	var obstruction:=INF
	var ray:Dictionary=rig.target_abilities.query(pose.origin,pose.origin-pose.basis.z*50.)
	if not ray.get("complete",false):return false
	if ray.get("hit",false):obstruction=pose.origin.distance_to(ray.get("position",pose.origin))
	var selected:=Targeting.first(pose,rig.body.global_position,{"range_m":48.},candidates(),obstruction)
	if selected.is_empty():return false
	target_id=str(selected.id);item_id=current_item();group_id=str(context.get("group_id",""));rig.target_abilities.close();refresh();return true
func ability_ready(row:Dictionary)->bool:
	return row.get("learned",false) and row.get("conditions_met",false) and maxf(0,float(row.get("cooldown_remaining_seconds",0))-age())<=0 and float(rig.abilities.cooldowns.get(str(row.get("id","")),0))<=0
func refresh()->void:
	points.clear()
	for widget:Node3D in widgets.values():widget.hide()
	refresh_volley()
	if not active():return
	if not permitted() or current_item()!=item_id or str(context.get("group_id",""))!=group_id:close();return
	var row:=person(target_id);var p:Variant=position(row)
	if row.is_empty() or not p is Vector3 or rig.body.global_position.distance_to(p)>48.:close();return
	var box:=bounds(row);var center:=box.get_center()
	var toward:Vector3=(rig.head.global_position-center).normalized();var right:Vector3=rig.head.global_basis.x.slide(toward).normalized();var up:=toward.cross(right).normalized()
	if right.length_squared()<.9:close();return
	var basis:=Basis(right,up,toward);var entries:=abilities()
	for index in range(entries.size()):
		var entry:Dictionary=entries[index];var id:=str(entry.id)
		var point:Vector3=center+toward*.36+right*(-.58 if index%2==0 else .58)+up*(.55-float(index/2)*.42)
		if not clear_line(aim().origin,center) or not clear_line(rig.head.global_position,center) or not clear_line(aim().origin,point):continue
		points.append({"position":point,"basis":basis,"radius":.15,"ability":entry,"target_id":target_id})
		if not widgets.has(id):widgets[id]=make_widget(false)
		var widget:Node3D=widgets[id];widget.global_transform=Transform3D(basis,point);widget.show()
		var cooling:=maxf(float(rig.abilities.cooldowns.get(id,0)),maxf(0,float(entry.get("cooldown_remaining_seconds",0))-age()))
		widget.get_node("Label").text=str(entry.get("label",id.capitalize()))+"\nNearby group · 48 m"+(" · %.1fs"%cooling if cooling>0 else "" if ability_ready(entry) else " · Unavailable")
		widget.get_node("Label").modulate=Color("a8ffcc") if ability_ready(entry) else Color("a4aaaa")
func hit(pose:Transform3D,choices:Array)->Dictionary:
	var closest:=INF;var result:Dictionary={};var direction:Vector3=-pose.basis.z.normalized()
	for point:Dictionary in choices:
		var normal:Vector3=point.basis.z;var denominator:=direction.dot(normal)
		if absf(denominator)<.001:continue
		var distance:float=(point.position-pose.origin).dot(normal)/denominator
		if distance<=0 or distance>=closest or (pose.origin+direction*distance).distance_to(point.position)>float(point.radius):continue
		closest=distance;result=point
	return result
func sample(trigger:float)->bool:
	var captured:=active();refresh()
	if not captured:return false
	if not active() or not is_finite(trigger):armed=false;pressing="";return true
	var point:=hit(aim(),points)
	if trigger<.25:
		var selected:=pressing;pressing="";armed=true
		if not selected.is_empty() and str(point.get("ability",{}).get("id",""))==selected and ability_ready(point.ability):authority.call(selected,target_id,aim(),rig.dominant)
	elif trigger>.7 and armed:
		armed=false;pressing=str(point.get("ability",{}).get("id",""))
	return true
func make_widget(volley:bool)->Node3D:
	var widget:=Node3D.new();add_child(widget)
	var icon:=MeshInstance3D.new();icon.name="Icon";icon.mesh=ring_mesh(1. if volley else .15);icon.material_override=Shapes.material();icon.material_override.albedo_color=Color("ffcc55") if volley else Color("a8ffcc");icon.material_override.no_depth_test=volley;widget.add_child(icon)
	var label:=Label3D.new();label.name="Label";label.font=preload("res://resources/fonts/Jupiteroid-Regular.ttf");label.font_size=28;label.pixel_size=.002;label.position.y=-1.2 if volley else -.2;label.modulate=Color("ffcc55") if volley else Color("a8ffcc");label.no_depth_test=volley;widget.add_child(label)
	return widget
static func ring_mesh(radius:float)->ImmediateMesh:
	var mesh:=ImmediateMesh.new();mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for index in range(64):
		for angle in [TAU*index/64.,TAU*(index+1)/64.]:mesh.surface_add_vertex(Vector3(cos(angle),sin(angle),0)*radius)
	for axis:Vector3 in [Vector3.UP,Vector3.DOWN,Vector3.LEFT,Vector3.RIGHT]:
		mesh.surface_add_vertex(axis*radius*.78);mesh.surface_add_vertex(axis*radius*1.2)
	mesh.surface_end();return mesh
func refresh_volley()->void:
	mark={}
	if is_instance_valid(volley_widget):volley_widget.hide()
	if not permitted():return
	var raw:Variant=context.get("volley_fire",{}).get("mark",{})
	if not raw is Dictionary:return
	var value:Dictionary=raw
	var id:=str(value.get("id",""));var target:=str(value.get("target_id",""));var p:Variant=position(value)
	if id.is_empty() or target.is_empty() or suppressed_marks.has(id) or not p is Vector3 or float(value.get("remaining_seconds",0))-age()<=0 or not value.get("eligible",true):return
	var center:Vector3=p+Vector3.UP*clampf(float(value.get("height",1.8))*.6,.3,3.)
	var toward:Vector3=(rig.head.global_position-center).normalized();var right:Vector3=rig.head.global_basis.x.slide(toward).normalized();var up:=toward.cross(right).normalized()
	if right.length_squared()<.9:return
	mark={"position":center,"basis":Basis(right,up,toward),"radius":1.,"target_id":target,"mark_id":id,"range_position":p}
	if not is_instance_valid(volley_widget):volley_widget=make_widget(true)
	volley_widget.global_transform=Transform3D(mark.basis,center);volley_widget.show();volley_widget.get_node("Label").text="VOLLEY FIRE · %.1fs"%maxf(0,float(value.remaining_seconds)-age())
func volley_intent(pose:Transform3D,maximum:float,target:="")->Dictionary:
	refresh_volley()
	if mark.is_empty() or maximum<=0 or rig.body.global_position.distance_to(mark.range_position)>maximum or (not target.is_empty() and target!=str(mark.target_id)):return {}
	if target.is_empty():
		if hit(pose,[mark]).is_empty():return {}
		var traced:Dictionary=rig.target_abilities.query(pose.origin,pose.origin-pose.basis.z*maximum)
		var actor:Variant=traced.get("collider")
		# A nearer enemy under the actual aim wins over a marker behind it.
		if is_instance_valid(actor) and actor.has_method("core3_identity") and str(actor.core3_identity().get("id",""))!=str(mark.target_id):return {}
	return {"volley_mark_id":str(mark.mark_id),"volley_target_id":str(mark.target_id)}
func consumed(id:String)->void:
	if id.is_empty():return
	suppressed_marks[id]=true
	while suppressed_marks.size()>32:suppressed_marks.erase(suppressed_marks.keys()[0])
	refresh_volley()
func enemy(actor:Variant)->bool:
	if not is_instance_valid(actor) or not actor.has_method("core3_identity") or not actor.has_method("is_targetable") or not actor.is_targetable():return false
	var row:Dictionary=actor.get("record")
	return row.get("kind","") in ["creature","lair"] and row.get("relation","") in ["hostile","attackable"] and not row.get("dead",false) and not row.get("incapacitated",false)
func ultimate(pose:Transform3D)->bool:
	if not permitted() or str(rig.active_profile().get("ability_loadout",{}).get("ultimate",""))!="volley_fire":return false
	var query:Dictionary=rig.target_abilities.query(pose.origin,pose.origin-pose.basis.z*64.)
	var actor:Variant=query.get("collider")
	if not query.get("complete",false) or not enemy(actor):return false
	return bool(authority.call("volley_fire",str(actor.record.id),pose,rig.dominant))
