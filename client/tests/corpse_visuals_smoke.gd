extends SceneTree
const Corpses=preload("res://scripts/corpse_visuals.gd")
class ReplicatedCorpse extends Node3D:
	var record:={"dead":true}
	func visual_bounds()->AABB:return AABB(Vector3(-.5,0,-.3),Vector3(1,.4,.6))
var errors: Array[String]=[]
func _initialize() -> void: call_deferred("run")
func check(ok: bool,message: String) -> void:
	if not ok: errors.append(message); push_error(message)
func run() -> void:
	var stage:=Node3D.new(); stage.set_meta("manifest",{"origin":[3618.98388671875,5,-4801.0859375]}); root.add_child(stage)
	var observer:=Node3D.new(); root.add_child(observer)
	var corpses:=Corpses.new(); root.add_child(corpses); corpses.configure(); corpses.set_context(stage,observer); corpses.set_physics_process(false)
	var source:={"id":"actual_model_fixture","template":"object/mobile/worrt_hue.iff","shared_template":"object/mobile/shared_worrt_hue.iff","world_position":Vector3.ZERO,"dead":true,"scale":1.25,"heading_radians":0.65,"customization":{"/private/index_color_1":3},"loot_available":true,"loot":{"credits":10,"item_count":1},"resources":[{"resource_id":"confirmed_id","quantity":5}]}
	check(corpses.set_states([source]),"Authoritative corpse fixture rejected")
	corpses.sync_visuals()
	check(corpses.visuals.size()==1,"Original worrt source model/pose unavailable")
	var descriptor:=corpses.assets.descriptor(source.template)
	check(descriptor.get("bones",0)==30 and descriptor.get("source_clip","")=="appearance/animation/frog_std_incapacitated.ans","Wrong original skeleton/pose lineage")
	var vertex_count:=0
	if corpses.visuals.size()==1:
		var visual: Dictionary=corpses.visuals[source.id]
		var bounds: AABB=visual.bounds
		check(absf(bounds.position.y)<0.001,"Posed corpse is not grounded by original vertex bounds")
		check(bounds.size.x>0.5 and bounds.size.x<1,"Corpse source meter scale was normalized for UI")
		check(visual.model.mesh.get_surface_count()>0,"Original corpse mesh empty")
		for surface in range(visual.model.mesh.get_surface_count()):
			vertex_count+=visual.model.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX].size()
		check(vertex_count>100,"Original animal source geometry missing")
		var hand: Vector3=visual.node.to_global(Vector3(bounds.get_center().x,bounds.end.y+0.15,bounds.get_center().z))
		var candidate:=corpses.nearest(hand)
		check(candidate.get("id","")==source.id and candidate.get("bounds") is AABB,"Hand above actual posed body cannot select corpse")
		candidate.resources[0].quantity=999
		check(corpses.states[source.id].resources[0].quantity==5,"Hover query mutated authoritative yield metadata")
		check(corpses.nearest(hand+Vector3.UP*2).is_empty() and corpses.nearest(hand+Vector3.RIGHT*3).is_empty(),"Distant hand can harvest corpse")
		check(visual.node.collision_layer==32 and visual.node.collision_mask==0,"Corpse collider changes movement geometry")
	check(corpses.coins.has(source.id) and corpses.coins[source.id].visible,"Server-eligible corpse displays original coin")
	var marker:Node3D=corpses.coins[source.id]
	var coin_point:Vector3=marker.global_position
	check(corpses.nearest_loot(Transform3D(Basis.IDENTITY,coin_point+Vector3.RIGHT*.45)).get("id","")==source.id,"Coin has forgiving half-metre direct boundary")
	check(corpses.nearest_loot(Transform3D(Basis.IDENTITY,coin_point+Vector3(0,0,2))).get("id","")==source.id,"Short forward aim reaches coin above large corpse")
	check(corpses.nearest_loot(Transform3D(Basis.IDENTITY,coin_point+Vector3(0,0,3))).is_empty(),"Coin cannot be selected beyond bounded aim range")
	var wall:=StaticBody3D.new();wall.collision_layer=1
	var wall_shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(2,2,.1);wall_shape.shape=box;wall.add_child(wall_shape);root.add_child(wall);wall.position=coin_point+Vector3(0,0,1)
	await physics_frame;await physics_frame
	check(corpses.nearest_loot(Transform3D(Basis.IDENTITY,coin_point+Vector3(0,0,2))).is_empty(),"Coin aim cannot reach through world collision")
	wall.queue_free();await physics_frame
	var angle:float=marker.get_child(0).rotation.y;corpses._process(.25)
	check(not is_equal_approx(angle,marker.get_child(0).rotation.y),"Original gold coin spins")
	var denied:Dictionary=source.duplicate(true);denied.loot_available=false
	corpses.set_states([denied]);corpses.sync_visuals()
	check(not marker.visible,"Ineligible owner/capacity state immediately hides coin")
	var empty:Dictionary=source.duplicate(true);empty.loot={"credits":0,"item_count":0}
	corpses.set_states([empty]);corpses.sync_visuals()
	check(not marker.visible,"Empty corpse never displays Loot All even if availability metadata contradicts contents")
	corpses.set_states([source]);corpses.sync_visuals()
	var living:=source.duplicate(true); living.dead=false
	check(not corpses.set_states([living]) and corpses.states.size()==1,"Living creature accepted or malformed refresh destroyed corpse")
	var records: Array=[]
	for i in range(40):
		var record:=source.duplicate(true); record.id="corpse_%d"%i; record.world_position=Vector3(i,0,0); records.append(record)
	check(corpses.set_states(records),"Corpse authority incorrectly capped at render limit")
	for i in range(18): corpses.sync_visuals()
	check(corpses.states.size()==40 and corpses.visuals.size()==32,"Corpse rendering budget is not32 while authority retains40")
	observer.position=Vector3(1000,0,0); corpses.sync_visuals()
	check(corpses.visuals.is_empty() and corpses.states.size()==40,"Distance culling lost authority or left distant renderers")
	observer.position=Vector3.ZERO
	var unavailable:=source.duplicate(true); unavailable.template="object/mobile/unknown_original_creature.iff"
	corpses.set_states([unavailable]); corpses.sync_visuals()
	check(corpses.visuals.is_empty() and corpses.failures.has(source.id),"Missing original species received placeholder animal")
	var species_count:=0
	for template: String in corpses.assets.catalog.get("planets",{}).get("tatooine",{}).get("templates",[]):
		var animal:=source.duplicate(true); animal.id=template; animal.template=template
		corpses.set_states([animal]); corpses.sync_visuals()
		check(corpses.visuals.size()==1,"Original Tatooine animal failed to instantiate: "+template)
		if corpses.visuals.size()==1: species_count+=1
		await process_frame
	var replicated:=ReplicatedCorpse.new();root.add_child(replicated);replicated.position=Vector3(1,.2,0)
	corpses.actor_provider=func(_id):return replicated
	corpses.set_states([source]);corpses.sync_visuals()
	check(corpses.visuals[source.id].node==replicated and corpses.visuals[source.id].external,"Existing replicated NPC corpse owns its pose; no duplicate body")
	check(replicated.position==Vector3(1,.2,0),"Loot presentation never relocates the replicated body")
	corpses.clear();await process_frame
	check(is_instance_valid(replicated) and replicated.visible,"Removing loot marker never frees or hides replicated body")
	replicated.queue_free();corpses.actor_provider=Callable()
	var report:={"ok":errors.is_empty(),"renderer":"dummy; no GPU validation","source_template":source.template,"source_clip":descriptor.get("source_clip"),"vertices":vertex_count,"tatooine_templates_instantiated":species_count,"posed_bounds":descriptor.get("bounds"),"state":corpses.statistics(),"errors":errors}
	FileAccess.open("res://../runtime/evidence/corpse-visuals-smoke.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  ")+"\n")
	print(JSON.stringify(report)); corpses.clear(); corpses.queue_free(); stage.queue_free(); observer.queue_free()
	await process_frame; quit(0 if errors.is_empty() else 1)
