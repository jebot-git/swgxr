extends Node3D
## Player-local real-time anatomical ability targets. No networked UI or time pause.
const POINTS := {
	"eye_shot":{"part":"head","label":"Eye Shot","height":.97,"side":1.,"bones":["head"]},
	"confusion_shot":{"part":"chest","label":"Confusion Shot","height":.73,"side":-1.,"bones":["chest","spine3"]},
	"focused_discharge":{"part":"chest","label":"Focused Discharge","height":.73,"side":-1.,"bones":["chest","spine3"]},
	"acid_spray":{"part":"abdomen","label":"Acid Spray","height":.55,"side":1.,"bones":["spine1","spine2"]},
	"piercing_shot":{"part":"chest","label":"Piercing Shot","height":.73,"side":-1.,"bones":["chest","spine3"]},
	"flurry_shot":{"part":"abdomen","label":"Flurry Shot","height":.55,"side":1.,"bones":["spine1","spine2"]},
	"surprise_shot":{"part":"shoulder","label":"Surprise Shot","height":.82,"side":1.,"bones":["rshoulder","rupperarm","chest"]},
	"crippling_shot":{"part":"knees","label":"Crippling Shot","height":.25,"side":1.,"bones":["lknee","lshin","lcalf"]},
	"wild_shot":{"part":"head","label":"Wild Shot","height":.97,"side":1.,"bones":["head"]},
	"charge_shot":{"part":"pelvis","label":"Charge Shot","height":.46,"side":-1.,"bones":["pelvis"]},
	"double_tap":{"part":"heart","label":"Double Tap","height":.72,"side":-1.,"bones":["chest","spine3","spine2"]},
	"disarming_shot":{"part":"arm","label":"Disarming Shot","height":.8,"side":1.,"bones":["rshoulder","rupperarm","chest"]},
	"suppression_fire":{"part":"arm","label":"Suppression Fire","height":.8,"side":1.,"bones":["rshoulder","rupperarm","chest"]},
	"warning_shot":{"part":"knees","label":"Warning Shot","height":.09,"side":-1.,"bones":["lfoot","lankle"]},
	"controlled_burst":{"part":"torso","label":"Controlled Burst","height":.55,"side":1.,"bones":["spine2","spine1"]},
	"bleeding_shot":{"part":"torso","label":"Bleeding Shot","height":.58,"side":-1.,"bones":["spine1"]},
	"pinning_strike":{"part":"knees","label":"Pinning Strike","height":.09,"side":-1.,"bones":["lfoot","lankle"]},
	"disrupting_jab":{"part":"arm","label":"Disrupting Jab","height":.8,"side":1.,"bones":["rshoulder","rupperarm","chest"]},
	"arterial_cut":{"part":"torso","label":"Arterial Cut","height":.55,"side":-1.,"bones":["spine2","spine1"]},
	"nerve_strike":{"part":"arm","label":"Nerve Strike","height":.8,"side":1.,"bones":["rshoulder","rupperarm","chest"]},
	"disorienting_thrust":{"part":"head","label":"Disorienting Thrust","height":.97,"side":1.,"bones":["head"]},
	"exposing_thrust":{"part":"heart","label":"Exposing Thrust","height":.70,"side":-1.,"bones":["chest","spine3","spine2"]},
	"rending_cut":{"part":"torso","label":"Rending Cut","height":.55,"side":-1.,"bones":["spine2","spine1"]},
	"disrupting_blow":{"part":"arm","label":"Disrupting Blow","height":.8,"side":1.,"bones":["rshoulder","rupperarm","chest"]},
	"hamstring":{"part":"knees","label":"Hamstring","height":.25,"side":1.,"bones":["lknee","lshin","lcalf"]},
	"decisive_strike":{"part":"heart","label":"Decisive Strike","height":.70,"side":-1.,"bones":["chest","spine3","spine2"]},
	"challenging_strike":{"part":"heart","label":"Challenging Strike","height":.70,"side":-1.,"bones":["chest","spine3","spine2"]},
	"knockdown_strike":{"part":"knees","label":"Knockdown","height":.25,"side":1.,"bones":["lknee","lshin","lcalf"]},
	"unarmed_stun":{"part":"head","label":"Stunning Attack","height":.88,"side":-1.,"bones":["head","neck"]},
	"unarmed_blind":{"part":"head","label":"Blinding Attack","height":.97,"side":1.,"bones":["head"]},
	"polearm_stun":{"part":"head","label":"Concussive Strike","height":.91,"side":-1.,"bones":["head","neck"]},
	"concussion_shot_improved":{"part":"head","label":"Concussion","height":.91,"side":-1.0,"bones":["head","neck"]},
	"lethal_shot":{"part":"heart","label":"Lethal Shot","height":.70,"side":1.0,"bones":["chest","spine3","spine2"]},
	"low_blow":{"part":"pelvis","label":"Low Blow","height":.46,"side":-1.0,"bones":["pelvis"]},
	"restraining_shot":{"part":"knees","label":"Restraining Shot","height":.25,"side":1.0,"bones":["lknee","lshin","lcalf"]}
}
var pending_melee:Dictionary={}
var punch_history:Dictionary={}
var rig:Node3D
var ultimate_target:Node3D
var target:Node3D
var target_id:=""
var item_id:=""
var points:Array[Dictionary]=[]
var widgets:Dictionary={}
var hovered:=""
var ultimate_input=preload("res://combat/ultimate_input.gd").new()
func setup(owner_rig:Node3D)->void:rig=owner_rig
func close()->void:
	target=null;target_id="";item_id="";points.clear();hovered="";pending_melee.clear();punch_history.clear()
	for widget:Node3D in widgets.values():widget.hide()
func reset()->void:
	close();ultimate_input.reset()
func state()->RefCounted:
	if not is_instance_valid(rig):return null
	if rig.selected>=0:return rig.weapons[rig.selected].state
	return rig.unarmed.get(rig.dominant) if rig.get("unarmed") is Dictionary else null
func attack_pose()->Transform3D:
	return rig.muzzle_pose(rig.selected) if rig.selected>=0 else rig.head.global_transform
func permitted()->bool:
	return is_instance_valid(rig) and state()!=null and rig.allowed and rig.combat_actions_allowed() and rig.inventory_allows_combat() and not rig.ability_ui.menu_open and not (is_instance_valid(rig.datapad) and rig.datapad.is_open) and not rig.dna_input_captured and not rig.taunt_input_captured and not rig.warcry_input_captured and not rig.brawler_input_captured and not rig.tka_input_captured and not rig.swordsman_input_captured and not rig.fencer_input_captured and not rig.pikeman_input_captured and not rig.pistoleer_input_captured and not rig.carbineer_input_captured and not rig.rifleman_input_captured and not rig.bountyhunter_input_captured
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
	var distance:=float(state().core.get("maxRange",0))
	if not state().is_melee():distance*=state().range_scale(rig.two_hands)
	var hit:=query(pose.origin,pose.origin-pose.basis.z*distance)
	var actor:Variant=hit.get("collider")
	return actor if hit.get("complete",false) and actor_eligible(actor) else null
func toggle(pose:Transform3D)->void:
	var actor:=acquire(pose)
	if actor==null or actor==target:close();return
	close();target=actor;target_id=str(actor.record.id);item_id=str(state().profile.get("item_id",""));refresh()
func ability_ready(ability:Dictionary,actor:Node3D)->bool:
	if not permitted() or not actor_eligible(actor):return false
	if not preload("res://combat/loadout.gd").equipped(ability,rig.active_profile().get("ability_loadout",{})):return false
	var state:RefCounted=state()
	if ability.get("requires_control_available",state.is_melee()) and not actor.record.get("melee_control_available",true):return false
	if not actor.record.get("ability_target_available",{}).get(str(ability.id),true):return false
	if ability.get("requires_knockdown_available",false) and not actor.record.get("knockdown_available",false):return false
	if ability.get("excludes_bosses",false) and (actor.record.get("boss",true) or int(actor.record.get("level",151))>150):return false
	if ability.has("target_health_below"):
		var maximum:=float(actor.record.get("effective_max_health",actor.record.get("max_health",0)))
		if maximum<=0 or float(actor.record.get("health",maximum))>=maximum*float(ability.target_health_below):return false
	if ability.get("id","")=="armour_break" and actor.record.get("fractured_armour",false):return false
	if ability.get("id","")=="sniper_shot" and not rig.two_hands:return false
	if state.profile.get("native_family","")=="commando" and state.profile.get("commando_family","")!="pistol_launcher" and not rig.two_hands:return false
	if not state.certified():return false
	if not state.profile.get("unarmed",false) and (state.condition_max<2 or state.condition_damage>=state.condition_max):return false
	if not state.is_melee() and (state.rounds<int(ability.get("ammo_cost",1)) or (ability.get("id","") in ["showdown","flurry_shot"] and state.rounds<3) or state.reload_until>=0):return false
	if not ability.get("conditions_met",true) or ability.get("activation","")!=("native_melee" if state.is_melee() else "native_ranged"):return false
	if float(rig.abilities.cooldowns.get(str(ability.id),0))>0:return false
	var cost:Array=rig.abilities.costs(ability)
	if cost.size()!=3:return false
	for i in range(3):
		if float(rig.abilities.ham[i*3])<=float(cost[i]):return false
	if str(ability.id)=="last_ditch" and (rig.abilities.ham[3]<=1 or rig.abilities.ham[6]<=1):return false
	var distance:float=rig.body.global_position.distance_to(actor.global_position)
	var base_range:=float(state.core.get("maxRange",0))
	var ability_range:=float(ability.get("max_range_m",base_range))
	var grip_scale:float=1.0 if state.is_melee() else state.range_scale(rig.two_hands)
	if is_equal_approx(ability_range,base_range):ability_range*=grip_scale
	var maximum:=minf(base_range*grip_scale,ability_range)
	return distance>=float(ability.get("min_range_m",0)) and distance<=maximum
func definition(ability:Dictionary)->Dictionary:
	if str(ability.get("id",""))=="bleeding_shot" and ability.get("bountyhunter_upgrade",false) and str(ability.get("anatomical_part",""))=="abdomen":return {"part":"abdomen","label":str(ability.get("label","Bleeding Shot")),"height":.55,"side":-1.,"bones":["spine1","spine2"]}
	if str(ability.get("id",""))=="lethal_shot" and ability.get("rifleman_upgrade",false) and str(ability.get("anatomical_part",""))=="head":return {"part":"head","label":"Head Shot","height":.97,"side":1.,"bones":["head"]}
	return POINTS.get(str(ability.get("id","")),{})
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
	if not permitted() or not actor_eligible(target) or str(state().profile.get("item_id",""))!=item_id:close();return
	var anchors:Dictionary={};var entries:Dictionary={}
	for ability:Dictionary in rig.active_profile().get("abilities",[]):
		var id:=str(ability.get("id",""))
		if not POINTS.has(id) or not ability_ready(ability,target):continue
		anchors[id]=anchor(target,definition(ability));entries[id]=ability
	var bounds:AABB=target.global_transform*target.visual_bounds()
	var arranged:=layout(bounds,rig.head.global_transform,anchors)
	var muzzle:Transform3D=attack_pose()
	for id:String in arranged:
		var point:Dictionary=arranged[id]
		if not clear_line(rig.head.global_position,point.position,target) or not clear_line(rig.head.global_position,point.anchor,target) or not clear_line(muzzle.origin,point.position,target) or not clear_line(muzzle.origin,point.anchor,target):continue
		point["ability"]=entries[id];point["target_id"]=target_id;points.append(point)
		if not widgets.has(id):widgets[id]=make_widget(id)
		var widget:Node3D=widgets[id];widget.global_transform=Transform3D(point.basis,point.position);widget.show()
		var part:=str(definition(entries[id]).part)
		if str(widget.get_meta("part",""))!=part:
			widget.get_node("Icon").mesh=icon_mesh(part);widget.set_meta("part",part)
		widget.get_node("Label").text=str(entries[id].get("label",POINTS[id].label))
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
		ultimate_target=null
		actor=acquire(pose)
		# Both-trigger use can also aim at any currently visible body marker.
		if actor==null and not point.is_empty():actor=target
		if not actor_eligible(actor):return {}
		point={}
		for ability:Dictionary in rig.active_profile().get("abilities",[]):
			if (str(ability.get("id",""))=="last_ditch" or ability.get("ultimate",false)) and ability_ready(ability,actor):
				point={"ability":ability,"anchor":anchor(actor,POINTS.lethal_shot),"target_id":str(actor.record.id)};break
	if point.is_empty() or not ability_ready(point.ability,actor) or not clear_line(pose.origin,point.anchor,actor):return {}
	if ultimate:ultimate_target=actor
	if str(point.ability.id) in ["showdown","flurry_shot"]:return {"ability_id":str(point.ability.id),"target_id":str(point.target_id)}
	return {"ability_id":str(point.ability.id),"target_id":str(point.target_id),"aim_point":point.anchor}
func melee_attack(from:Vector3,to:Vector3)->Dictionary:
	if not permitted() or not state().is_melee():return {}
	refresh()
	var segment:=to-from
	if not from.is_finite() or not to.is_finite() or segment.length()>.8:return {}
	for point:Dictionary in points:
		var along:=clampf((point.position-from).dot(segment)/maxf(segment.length_squared(),.000001),0,1)
		if (from+segment*along).distance_to(point.position)<=float(point.radius) and clear_line(to,point.anchor,target):
			return {"ability_id":str(point.ability.id),"target_id":str(point.target_id)}
	return {}
func sample_punch(key:String,hand:Vector3,delta:float,enabled:bool)->void:
	# Use tracked translation relative to the head/origin, not the blade tip or
	# controller aim. Walking and snap turning cannot supply punch travel.
	if not enabled or not permitted() or not actor_eligible(target) or not hand.is_finite() or not is_finite(delta) or delta<=0 or delta>.1:
		punch_history.erase(key);pending_melee.erase(key);return
	var position:Vector3=rig.swing_position(hand)
	var samples:Array=punch_history.get(key,[])
	if not samples.is_empty() and position.distance_to(samples.back().position)>.5:
		punch_history.erase(key);pending_melee.erase(key);return
	for sample:Dictionary in samples:sample.age+=delta
	while not samples.is_empty() and float(samples[0].age)>.14:samples.pop_front()
	samples.append({"position":position,"hand":hand,"age":0.0})
	punch_history[key]=samples
func punch_attack(key:String,hand:Vector3)->Dictionary:
	if not permitted() or not state().is_melee():return {}
	var samples:Array=punch_history.get(key,[])
	if samples.size()<3:return {}
	var travel:Vector3=samples.back().position-samples[0].position
	var path:=0.0
	for i in range(1,samples.size()):path+=samples[i].position.distance_to(samples[i-1].position)
	if travel.length()<.10 or travel.length()<path*.85:return {}
	var direction:=travel.normalized()
	if is_instance_valid(rig.origin):direction=rig.origin.global_basis*direction
	# Retraction, sideways sweeps and stationary pointing do not select a marker.
	if direction.dot(-rig.head.global_basis.z)<.15:return {}
	refresh()
	var best:Dictionary={};var nearest:=INF
	for point:Dictionary in points:
		var offset:Vector3=point.position-hand
		var along:=offset.dot(direction)
		if along<0:continue
		var tolerance:=maxf(float(point.radius),minf(.18,along*.06))
		var miss:float=(offset-direction*along).length()/tolerance
		if miss>1 or miss>=nearest:continue
		if not clear_line(hand,point.position,target) or not clear_line(hand,point.anchor,target):continue
		nearest=miss;best={"ability_id":str(point.ability.id),"target_id":str(point.target_id)}
	return best
func melee_swing(shot:Dictionary,from:Vector3,to:Vector3,key:String,delta:float,enabled:=true)->Dictionary:
	if not enabled:pending_melee.erase(key);punch_history.erase(key);return {}
	if not permitted() or not actor_eligible(target):pending_melee.erase(key);return shot
	# Swing qualification may occur before the hand reaches the body marker.
	if not shot.is_empty():pending_melee[key]={"shot":shot.duplicate(true),"remaining":.3,"target_id":target_id,"item_id":item_id}
	if not pending_melee.has(key):return {}
	var pending:Dictionary=pending_melee[key]
	if pending.target_id!=target_id or pending.item_id!=item_id:pending_melee.erase(key);return {}
	var special:=melee_attack(from,to)
	if special.is_empty():
		var samples:Array=punch_history.get(key,[])
		if not samples.is_empty():
			special=punch_attack(key,samples.back().hand)
	pending.remaining-=delta
	if not special.is_empty() or pending.remaining<=0:
		var result:Dictionary=pending.shot;pending_melee.erase(key);result.merge(special,true);return result
	return {}

func make_widget(id:String)->Node3D:
	var node:=Node3D.new();add_child(node)
	var mesh:=MeshInstance3D.new();mesh.name="Icon";mesh.mesh=icon_mesh(str(POINTS[id].part));mesh.material_override=material();mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;node.add_child(mesh)
	var connector:=MeshInstance3D.new();connector.name="Connector";connector.material_override=material();connector.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;node.add_child(connector)
	var label:=Label3D.new();label.name="Label";label.font=preload("res://resources/fonts/Jupiteroid-Regular.ttf");label.text=POINTS[id].label;label.font_size=26;label.pixel_size=.0018;label.position=Vector3(0,-.14,0);label.modulate=Color("99f9ff");label.no_depth_test=false;node.add_child(label)
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
		"torso","chest","abdomen":path=[Vector2(-.05,.06),Vector2(.05,.06),Vector2(.04,-.055),Vector2(-.04,-.055),Vector2(-.05,.06),Vector2(.05,-.055)]
		"arm","shoulder":path=[Vector2(-.055,.06),Vector2(-.015,.045),Vector2(.045,-.005),Vector2(.025,-.065),Vector2(-.005,-.045),Vector2(.005,-.01),Vector2(-.05,.025)]
		"heart":path=[Vector2(-.065,.025),Vector2(-.035,.06),Vector2(0,.03),Vector2(.035,.06),Vector2(.065,.025),Vector2(0,-.065),Vector2(-.065,.025)]
		"head":path=[Vector2(-.03,-.055),Vector2(-.03,-.025),Vector2(-.06,.01),Vector2(-.045,.06),Vector2(.025,.065),Vector2(.045,.025),Vector2(.065,0),Vector2(.035,-.005),Vector2(.03,-.055)]
		"pelvis":path=[Vector2(-.06,.055),Vector2(-.045,-.02),Vector2(-.015,-.06),Vector2(0,-.015),Vector2(.015,-.06),Vector2(.045,-.02),Vector2(.06,.055)]
		"knees":path=[Vector2(-.025,.065),Vector2(.04,.015),Vector2(-.025,-.065)]
	for i in range(path.size()-1):
		vertices.append(Vector3(path[i].x,path[i].y,0));vertices.append(Vector3(path[i+1].x,path[i+1].y,0))
	return line_mesh(vertices)
