extends Node3D
## Player-local real-time anatomical ability targets. No networked UI or time pause.
const POINTS := {
	"concussion_shot_improved":{"part":"head","label":"Concussion","height":.91,"side":-1.0,"bones":["head","neck"]},
	"lethal_shot":{"part":"heart","label":"Lethal Shot","height":.70,"side":1.0,"bones":["chest","spine3","spine2"]},
	"low_blow":{"part":"pelvis","label":"Low Blow","height":.46,"side":-1.0,"bones":["pelvis"]},
	"restraining_shot":{"part":"knees","label":"Restraining Shot","height":.25,"side":1.0,"bones":["lknee","lshin","lcalf"]}
}
var rig:Node3D
var target:Node3D
var target_id:=""
var item_id:=""
var points:Array[Dictionary]=[]
var widgets:Dictionary={}
var hovered:=""
var ultimate_input=preload("res://combat/ultimate_input.gd").new()
func setup(owner_rig:Node3D)->void:rig=owner_rig
func close()->void:
	target=null;target_id="";item_id="";points.clear();hovered=""
	for widget:Node3D in widgets.values():widget.hide()
func reset()->void:
	close();ultimate_input.reset()
func permitted()->bool:
	return is_instance_valid(rig) and rig.selected>=0 and not rig.weapons[rig.selected].state.is_melee() and rig.allowed and rig.combat_actions_allowed() and rig.inventory_allows_combat() and not rig.ability_ui.menu_open and not (is_instance_valid(rig.datapad) and rig.datapad.is_open) and not rig.dna_input_captured and not rig.taunt_input_captured
func actor_eligible(actor:Node)->bool:
	if not is_instance_valid(actor) or not actor.has_method("core3_identity") or not actor.has_method("is_targetable") or not actor.is_targetable():return false
	var record:Dictionary=actor.get("record")
	return record.get("relation","") in ["hostile","attackable"] and record.get("kind","")=="creature" and not record.get("incapacitated",false) and not record.get("dead",false)
func query(from:Vector3,to:Vector3)->Dictionary:
	var cell:Variant=rig.rounds_sim.actor_cell_at(from)
	if cell==null:return {"complete":false}
	return rig.rounds_sim.trace_query(from,to,str(cell))
func clear_line(from:Vector3,to:Vector3,actor:Node)->bool:
	var hit:=query(from,to)
	return hit.get("complete",false) and (not hit.get("hit",false) or hit.get("collider")==actor)
func acquire(pose:Transform3D)->Node3D:
	if not permitted():return null
	var distance:=float(rig.weapons[rig.selected].state.core.get("maxRange",0))
	var hit:=query(pose.origin,pose.origin-pose.basis.z*distance)
	var actor:Variant=hit.get("collider")
	return actor if hit.get("complete",false) and actor_eligible(actor) else null
func toggle(pose:Transform3D)->void:
	var actor:=acquire(pose)
	if actor==null or actor==target:close();return
	close();target=actor;target_id=str(actor.record.id);item_id=str(rig.weapons[rig.selected].state.profile.get("item_id",""));refresh()
func ability_ready(ability:Dictionary,actor:Node3D)->bool:
	if not permitted() or not actor_eligible(actor):return false
	if not preload("res://combat/loadout.gd").equipped(ability,rig.active_profile().get("ability_loadout",{})):return false
	var state:RefCounted=rig.weapons[rig.selected].state
	if not state.certified() or state.condition_max<2 or state.condition_damage>=state.condition_max:return false
	if state.rounds<=0 or state.reload_until>=0:return false
	if not ability.get("conditions_met",true) or ability.get("activation","")!="native_ranged":return false
	if float(rig.abilities.cooldowns.get(str(ability.id),0))>0:return false
	var cost:Array=rig.abilities.costs(ability)
	if cost.size()!=3:return false
	for i in range(3):
		if float(rig.abilities.ham[i*3])<=float(cost[i]):return false
	if str(ability.id)=="last_ditch" and (rig.abilities.ham[3]<=1 or rig.abilities.ham[6]<=1):return false
	var distance:float=rig.body.global_position.distance_to(actor.global_position)
	var maximum:=minf(float(state.core.get("maxRange",0)),float(ability.get("max_range_m",state.core.get("maxRange",0))))
	return distance>=float(ability.get("min_range_m",0)) and distance<=maximum
func anchor(actor:Node3D,definition:Dictionary)->Vector3:
	var visual:Variant=actor.get("visual")
	if is_instance_valid(visual) and is_instance_valid(visual.get("skeleton")):
		var skeleton:Skeleton3D=visual.skeleton
		for name:String in definition.bones:
			var bone:=skeleton.find_bone(name)
			if bone>=0:return skeleton.global_transform*skeleton.get_bone_global_pose(bone).origin
	var bounds:AABB=actor.visual_bounds()
	return actor.global_transform*(bounds.position+bounds.size*Vector3(.5,float(definition.height),.5))
static func layout(bounds:AABB,head:Transform3D,anchors:Dictionary)->Dictionary:
	var center:=bounds.get_center()
	var toward:Vector3=(head.origin-center).normalized()
	var right:Vector3=head.basis.x.slide(toward).normalized()
	var up:Vector3=toward.cross(right).normalized()
	if right.length_squared()<.9:return {}
	# One world-space plane just in front of the target's visible extent. It
	# follows target distance, never the HMD, and is still depth tested.
	var front:=0.0;var width:=0.0
	for i in range(8):
		var relative:=bounds.get_endpoint(i)-center
		front=maxf(front,relative.dot(toward));width=maxf(width,absf(relative.dot(right)))
	var plane:=center+toward*(front+.025)
	var result:Dictionary={}
	for id:String in anchors:
		var point:Vector3=anchors[id]
		var projected:Vector3=point+toward*(plane-point).dot(toward)
		var side:float=POINTS[id].side
		var marker:=projected+right*(side*(width+.18)-(projected-center).dot(right))
		result[id]={"position":marker,"anchor":point,"projected":projected,"basis":Basis(right,up,toward),"radius":.105}
	return result
func refresh()->void:
	points.clear();hovered=""
	for widget:Node3D in widgets.values():widget.hide()
	if not permitted() or not actor_eligible(target) or str(rig.weapons[rig.selected].state.profile.get("item_id",""))!=item_id:close();return
	var anchors:Dictionary={};var entries:Dictionary={}
	for ability:Dictionary in rig.active_profile().get("abilities",[]):
		var id:=str(ability.get("id",""))
		if not POINTS.has(id) or not ability_ready(ability,target):continue
		anchors[id]=anchor(target,POINTS[id]);entries[id]=ability
	var bounds:AABB=target.global_transform*target.visual_bounds()
	var arranged:=layout(bounds,rig.head.global_transform,anchors)
	var muzzle:Transform3D=rig.muzzle_pose(rig.selected)
	for id:String in arranged:
		var point:Dictionary=arranged[id]
		if not clear_line(rig.head.global_position,point.position,target) or not clear_line(rig.head.global_position,point.anchor,target) or not clear_line(muzzle.origin,point.position,target) or not clear_line(muzzle.origin,point.anchor,target):continue
		point["ability"]=entries[id];point["target_id"]=target_id;points.append(point)
		if not widgets.has(id):widgets[id]=make_widget(id)
		var widget:Node3D=widgets[id];widget.global_transform=Transform3D(point.basis,point.position);widget.show()
		var connector:MeshInstance3D=widget.get_node("Connector")
		connector.mesh=line_mesh([Vector3.ZERO,point.basis.inverse()*(point.projected-point.position)])
	var hit:=hit_point(muzzle)
	if not hit.is_empty():hovered=str(hit.ability.id)
	for id:String in widgets:widgets[id].scale=Vector3.ONE*(1.14 if id==hovered else 1.0)
func hit_point(pose:Transform3D)->Dictionary:
	var direction:Vector3=-pose.basis.z.normalized();var closest:=INF;var result:Dictionary={}
	for point:Dictionary in points:
		var normal:Vector3=point.basis.z;var denominator:=direction.dot(normal)
		if absf(denominator)<.001:continue
		var distance:float=(point.position-pose.origin).dot(normal)/denominator
		if distance<=0 or distance>=closest:continue
		if (pose.origin+direction*distance).distance_to(point.position)>float(point.radius):continue
		closest=distance;result=point
	return result
func attack(pose:Transform3D,ultimate:=false)->Dictionary:
	if not permitted():return {}
	refresh()
	var point:=hit_point(pose)
	var actor:Node3D=target
	if ultimate:
		actor=acquire(pose)
		# Both-trigger use can also aim at any currently visible body marker.
		if actor==null and not point.is_empty():actor=target
		if not actor_eligible(actor):return {}
		point={}
		for ability:Dictionary in rig.active_profile().get("abilities",[]):
			if (str(ability.get("id",""))=="last_ditch" or ability.get("ultimate",false)) and ability_ready(ability,actor):
				point={"ability":ability,"anchor":anchor(actor,POINTS.lethal_shot),"target_id":str(actor.record.id)};break
	if point.is_empty() or not ability_ready(point.ability,actor) or not clear_line(pose.origin,point.anchor,actor):return {}
	return {"ability_id":str(point.ability.id),"target_id":str(point.target_id),"aim_point":point.anchor}
func make_widget(id:String)->Node3D:
	var node:=Node3D.new();add_child(node)
	var mesh:=MeshInstance3D.new();mesh.mesh=icon_mesh(str(POINTS[id].part));mesh.material_override=material();mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;node.add_child(mesh)
	var connector:=MeshInstance3D.new();connector.name="Connector";connector.material_override=material();connector.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;node.add_child(connector)
	var label:=Label3D.new();label.font=preload("res://resources/fonts/Jupiteroid-Regular.ttf");label.text=POINTS[id].label;label.font_size=26;label.pixel_size=.0018;label.position=Vector3(0,-.14,0);label.modulate=Color("99f9ff");label.no_depth_test=false;node.add_child(label)
	return node
static func material()->StandardMaterial3D:
	var value:=StandardMaterial3D.new();value.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;value.albedo_color=Color("65edff");value.no_depth_test=false
	return value
static func line_mesh(vertices:Array)->ImmediateMesh:
	var mesh:=ImmediateMesh.new();mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for vertex:Vector3 in vertices:mesh.surface_add_vertex(vertex)
	mesh.surface_end();return mesh
static func icon_mesh(part:String)->ImmediateMesh:
	var vertices:Array=[]
	for i in range(32):
		for angle:float in [i*TAU/32,(i+1)*TAU/32]:vertices.append(Vector3(cos(angle),sin(angle),0)*.1)
	var path:Array=[]
	match part:
		"heart":path=[Vector2(-.065,.025),Vector2(-.035,.06),Vector2(0,.03),Vector2(.035,.06),Vector2(.065,.025),Vector2(0,-.065),Vector2(-.065,.025)]
		"head":path=[Vector2(-.03,-.055),Vector2(-.03,-.025),Vector2(-.06,.01),Vector2(-.045,.06),Vector2(.025,.065),Vector2(.045,.025),Vector2(.065,0),Vector2(.035,-.005),Vector2(.03,-.055)]
		"pelvis":path=[Vector2(-.06,.055),Vector2(-.045,-.02),Vector2(-.015,-.06),Vector2(0,-.015),Vector2(.015,-.06),Vector2(.045,-.02),Vector2(.06,.055)]
		"knees":path=[Vector2(-.025,.065),Vector2(.04,.015),Vector2(-.025,-.065)]
	for i in range(path.size()-1):
		vertices.append(Vector3(path[i].x,path[i].y,0));vertices.append(Vector3(path[i+1].x,path[i+1].y,0))
	return line_mesh(vertices)
