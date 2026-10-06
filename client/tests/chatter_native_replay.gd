extends SceneTree
const Fixture=preload("res://tests/chatter_sync_smoke.gd")
const SceneFixture=preload("res://tests/chatter_smoke.gd")
class Host extends Fixture.Host:
	var loader:=preload("res://scripts/stage_loader.gd").new()
var checks:=0
var failures:Array=[]
func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures.append(label);push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	var evidence:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/evidence/chatter-native.json"))
	if not evidence.get("passed",false):push_error("Passing native NPC speech recording required");quit(2);return
	var hosts:Dictionary={};var controllers:Dictionary={};var records:=0;var observed:Dictionary={};var preview:Array=[]
	check(evidence.get("responses",[]).size()<=2048,"Native recording fits bounded replay budget")
	for row:Dictionary in evidence.get("responses",[]).slice(0,2048):
		if row.get("path","")!="/session/sync":continue
		var response:Dictionary=row.get("response",{});var speech:Dictionary=response.get("npc_speech",{})
		var owner:=str(response.character_id);var session:=str(response.session_id);var key:=owner+":"+session
		if not controllers.has(key):
			var host:=Host.new();root.add_child(host);host.stage=SceneFixture.Stage.new();host.add_child(host.stage);host.player=SceneFixture.Player.new();host.add_child(host.player);host.player.eye=Camera3D.new();host.player.add_child(host.player.eye);hosts[key]=host
			var sync:=preload("res://multiplayer/client_sync.gd").new();sync.set_process(false);host.add_child(sync);sync.app=host;host.multiplayer_sync=sync;sync.owner_character=owner;sync.owner_session=session
			sync.players=Fixture.Players.new();host.add_child(sync.players);sync.entities=Fixture.Entities.new();host.add_child(sync.entities);sync.chatter=preload("res://chatter/controller.gd").new();host.add_child(sync.chatter);sync.chatter.setup(host);sync.chatter.set_process(false);controllers[key]=sync
		var host:Node3D=hosts[key];var sync:Node=controllers[key];var manager:Node3D=sync.chatter
		host.active_planet=str(response.zone)
		if not speech.get("events",[]).is_empty():
			var context:Dictionary=speech.events[0];host.stage.current_cell={"building_object_id":str(context.get("building_id","0")),"cell_id":"%s:%d"%[str(context.get("building_id","0")),int(context.get("cell_index",0))]}
		check(sync.apply_response(response,int(response.sequence)),"Actual native owned sync envelope passes production authentication/schema boundary");records+=1
		check(manager.created<=8 and manager.active.size()<=8,"Recorded native speech respects fixed visual allocation cap")
		for id in manager.active:
			var entry:Dictionary=manager.active[id];var record:Dictionary={}
			for candidate:Dictionary in sync.state.actors:
				if str(candidate.id)==str(id):record=candidate;break
			check(not record.is_empty(),"Actual speaker ID exists in native observer world")
			if record.is_empty():continue
			if not sync.entities.actors.has(id):
				var actor:=preload("res://combat/live_actor.gd").new();host.add_child(actor)
				var loaded:bool=actor.configure(record,session,RefCounted.new(),RefCounted.new(),ProjectSettings.globalize_path("res://../runtime/assets/ambient_npcs/catalog.json"));actor.set_process(false)
				check(loaded and is_instance_valid(actor.visual),"Actual native speaker template loads its original source body")
				if not loaded:actor.free();continue
				actor.apply_record(record,Transform3D(Basis(Vector3.UP,-float(record.heading_radians)),sync.world(record.position)),1,true);sync.entities.actors[id]=actor
			var actor:Node3D=sync.entities.actors[id];var crown:Variant=preload("res://chatter/head_anchor.gd").crown(actor)
			check(crown is Vector3 and crown.is_finite(),"Actual native speaker has source-derived animated crown anchor")
			if crown is Vector3:
				host.player.eye.global_position=crown+Vector3(0,.5,4);host.player.eye.look_at(crown+Vector3.UP*.3);host.player.eye.current=true;manager._process(.01)
				check(entry.bubble.visible and (entry.bubble.global_transform*preload("res://chatter/bubble.gd").TAIL_TIP).distance_to(crown+Vector3.UP*.035)<.001,"Actual native speech renders on original actor with precise tail anchor")
			check(entry.bubble.words.text==preload("res://chatter/bubble.gd").fit_text(str(entry.event.text),36,3),"Actual server-resolved language presentation reaches bounded text renderer")
			var mode:="understood" if entry.event.get("understood",false) else "unfamiliar"
			if not observed.has(mode):preview.append({"event":entry.event.duplicate(true),"actor":record.duplicate(true)})
			observed[mode]=true
		var before:int=manager.created
		check(not sync.apply_response(response,int(response.sequence)) and manager.created==before,"Actual replayed transport packet cannot duplicate speech or learning")
		for language:Dictionary in manager.languages:check(int(language.get("progress_basis_points",-1)) in range(10001) and language.get("understood") is bool,"Recipient native comprehension remains bounded authoritative metadata")
	check(records>0 and observed.has("understood") and observed.has("unfamiliar"),"Real native familiar and unfamiliar language presentations were replayed")
	FileAccess.open("res://../runtime/evidence/chatter-native-preview.json",FileAccess.WRITE).store_string(JSON.stringify({"rows":preview,"source":"recorded native NPC speech and actors"},"  "))
	for host in hosts.values():host.free()
	await process_frame
	var report:Dictionary={"passed":failures.is_empty(),"checks":checks,"records":records,"failures":failures,"production_authenticated_sync":true,"original_native_actor_models":true,"native_requests_sent":0,"renderer":"dummy","live_xr":false};FileAccess.open("res://../runtime/evidence/chatter-native-replay.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "));print(JSON.stringify(report));quit(0 if failures.is_empty() else 1)
