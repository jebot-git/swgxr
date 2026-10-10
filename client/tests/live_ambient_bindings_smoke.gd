extends SceneTree
const Bindings=preload("res://combat/live_ambient_bindings.gd")
const Ambient=preload("res://scripts/ambient_npcs.gd")
const Radar=preload("res://scripts/radar_contacts.gd")
const Live=preload("res://combat/live_world.gd")
class SourceProjection extends Node3D:
	var collision_layer:=0
	var report:Dictionary={}
class Contact extends Node3D:
	var value:Dictionary={}
	func get_radar_contact()->Dictionary:return value
var checks:=0
var errors:Array[String]=[]
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:errors.append(message);push_error(message)
func _initialize()->void:call_deferred("run")
func run()->void:
	var source:=Ambient.new();root.add_child(source);source.set_process(false)
	check(source.configure(ProjectSettings.globalize_path("res://../runtime/assets/ambient_npcs/placements.json")),"Original placements configure without constructing extra local actors")
	var saved:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/evidence/live-nearby-asset-preflight.json"))
	var binding:=Bindings.new();binding.configure(source.manifest)
	var suppressed:=binding.update(saved.snapshot.actors)
	check(suppressed.size()==4,"Only the three exact source Jawas and one stormtrooper match the actual native snapshot")
	var native_id:=str(suppressed.values()[0]);var placement_id:=str(binding.bindings[native_id])
	var initial:Dictionary=source.manifest.instances.filter(func(entry):return str(entry.id)==placement_id)[0]
	var moved:Array=saved.snapshot.actors.duplicate(true)
	for actor:Dictionary in moved:
		if str(actor.id)==native_id:actor.position[0]+=40;actor.dead=true
	check(binding.update(moved)==suppressed and binding.update([])==suppressed,"Stable native ownership and dead tombstone survive motion and snapshot range eviction")
	var exact:=Bindings.new();exact.configure({"instances":[initial]})
	var duplicate:Dictionary=saved.snapshot.actors.filter(func(actor):return str(actor.id)==native_id)[0].duplicate(true)
	var second:=duplicate.duplicate(true);second.id="same-position-second-native"
	check(exact.update([duplicate,second]).size()==1 and exact.bindings.size()==1,"Coincident native identities cannot claim the same authored placement twice")
	exact.clear();second.template="object/mobile/different_exact_template.iff"
	check(exact.update([second]).is_empty(),"Nearby different template never removes an original local NPC")
	exact.clear();second=duplicate.duplicate(true);second.position[0]+=0.26
	check(exact.update([second]).is_empty(),"More than25cm displacement does not guess a source identity")
	var trainer_audit:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/assets/services/trainers.json"))
	var trainer_row:Dictionary=source.manifest.instances.filter(func(entry):return entry.get("mobile","")=="trainer_medic" and str(entry.source_cell_id)=="0")[0]
	var variants:Array=trainer_audit.trainers.trainer_medic.templates
	var trainer_actor:Dictionary={"id":"native-trainer","kind":"creature","template":variants.filter(func(t):return t!=trainer_row.template)[0],"position":trainer_row.source_world_xyz.duplicate(),"building_id":"0","cell_index":0}
	var trainer_binding:=Bindings.new();trainer_binding.configure({"instances":[trainer_row]},trainer_audit)
	check(trainer_binding.update([trainer_actor]).size()==1,"Original same-profession variant binds exact authored trainer position and native cell")
	trainer_binding.clear();trainer_actor.cell_index=1
	check(trainer_binding.update([trainer_actor]).is_empty(),"Trainer in another cell cannot suppress authored NPC")
	trainer_actor.cell_index=0;trainer_actor.building_id="99"
	check(trainer_binding.update([trainer_actor]).is_empty(),"Trainer in another building cannot suppress authored NPC")
	trainer_actor.building_id="0";trainer_actor.erase("cell_index")
	check(trainer_binding.update([trainer_actor]).is_empty(),"Missing native cell identity cannot claim trainer placement")
	trainer_actor.cell_index=0;trainer_actor.position[0]+=0.26
	check(trainer_binding.update([trainer_actor]).is_empty(),"Trainer variant still requires exact source placement")
	trainer_actor.position=trainer_row.source_world_xyz;trainer_actor.template=trainer_audit.trainers.trainer_scout.templates[0]
	check(trainer_binding.update([trainer_actor]).is_empty(),"Different trainer profession cannot claim colocated source placement")
	var dealer:Dictionary=source.manifest.instances.filter(func(entry):return entry.get("mobile","")=="chassis_dealer" and str(entry.get("source_cell_id",""))=="1106372")[0]
	var dealer_actor:Dictionary={"id":"native-dealer","kind":"creature","template":Bindings.CHASSIS_VARIANTS[0],"position":dealer.source_world_xyz.duplicate(),"building_id":dealer.building_object_id,"cell_index":4}
	var dealers:=Bindings.new();dealers.configure({"instances":[dealer]})
	check(dealers.update([dealer_actor]).size()==1,"Randomized original chassis dealer variant claims exact Mos Eisley placement")
	dealers.clear();dealer_actor.cell_index=3
	check(dealers.update([dealer_actor]).is_empty(),"Other cell cannot claim chassis dealer")
	dealer_actor.cell_index=4;dealer_actor.template="object/mobile/unrelated.iff"
	check(dealers.update([dealer_actor]).is_empty(),"Unrelated NPC cannot claim chassis dealer")
	dealer_actor.template=Bindings.CHASSIS_VARIANTS[0]
	var radar:=Radar.new();radar.configure(source)
	var center:=Vector3(float(initial.position[0]),float(initial.position[1]),float(initial.position[2]))
	check(radar.query(center,64).any(func(contact):return contact.id==placement_id),"Authored placement remains a radar contact before native ownership")
	var live:=Live.new();root.add_child(live);live.set_process(false);live.configure_ambient(source);live.source_visual_records(saved.snapshot.actors);live.synchronize_ambient(saved.snapshot.actors)
	check(source.live_suppressed.is_empty(),"Unconstructed live variants cannot remove existing authored presentation")
	for id:String in binding.bindings:
		var projection:=SourceProjection.new();live.add_child(projection);projection.report={"source_variant_ready":true,"source_placement_id":binding.bindings[id]};live.actors[id]=projection
	live.synchronize_ambient(saved.snapshot.actors)
	check(source.live_suppressed.size()==4 and not radar.query(center,64).any(func(contact):return contact.id==placement_id),"Exact native ownership suppresses only matched local radar entries")
	var dealer_projection:Array=live.source_visual_records([dealer_actor])
	check(not dealer_projection[0].has("source_placement_visual"),"Dealer retains native randomized art instead of static variant")
	var dealer_view:=SourceProjection.new();live.add_child(dealer_view);dealer_view.report={"appearance_status":"complete"};live.actors[dealer_actor.id]=dealer_view
	live.synchronize_ambient([dealer_actor])
	check(source.live_suppressed.get(str(dealer.id))==dealer_actor.id,"Ready native dealer suppresses the overlapping authored dealer")
	dealer_view.report.appearance_status="partial";live.synchronize_ambient([dealer_actor])
	check(source.live_suppressed.get(str(dealer.id))==dealer_actor.id,"Partial native dealer body still has exclusive visual ownership")
	dealer_view.report.appearance_status="unavailable";live.synchronize_ambient([dealer_actor])
	check(not source.live_suppressed.has(str(dealer.id)),"Unavailable native body retains authored fallback")
	var contact:=Contact.new();root.add_child(contact);contact.value={"id":native_id,"position":center,"kind":"mob","alive":true};contact.add_to_group("swg_radar_contacts")
	check(radar.query(center,64).any(func(item):return item.id==native_id),"Authoritative live radar identity remains visible")
	contact.value.alive=false
	check(not radar.query(center,64).any(func(item):return item.id in [native_id,placement_id]),"Confirmed corpse cannot resurrect an ambient radar ghost")
	live.reset("Test stop")
	check(source.live_suppressed.is_empty() and radar.query(center,64).any(func(item):return item.id==placement_id),"Session reset restores original authored presentation and radar")
	var report:Dictionary={"passed":errors.is_empty(),"checks":checks,"errors":errors,"exact_matches":suppressed,"real_http_requests":0,"gpu_tested":false}
	print(JSON.stringify(report));FileAccess.open("res://../runtime/evidence/live-ambient-bindings-smoke.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	live.queue_free();source.queue_free();contact.queue_free();await process_frame;quit(0 if errors.is_empty() else 1)
