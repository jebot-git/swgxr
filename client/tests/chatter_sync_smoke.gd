extends SceneTree
const Fixture=preload("res://tests/chatter_smoke.gd")
class Host extends Fixture.Host:
	var asset_status:Label
	var live_combat_reserved:=false
class Entities extends Fixture.Entities:
	func accept(_rows:Array,_owner:String,_revision:int)->void:pass
	func clear()->void:actors.clear()
class Players extends Node3D:
	var report:Dictionary={}
	func apply_snapshot(_rows:Array,_owner:String,_observer:Vector3,_cell:String,_full:bool)->void:pass
	func consume_events(_events:Array)->void:pass
	func apply_deployments(_rows:Array,_owner:String,_observer:Vector3)->void:pass
	func clear()->void:pass
var checks:=0
var failures:Array=[]
func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures.append(label);push_error(label)
func packet(sequence:int)->Dictionary:
	return {"ok":true,"backend":"core3","source_kind":"core3_multiplayer_sync","character_id":"101","session_id":"owned","zone":"tatooine","sequence":sequence,"world_revision":1,"world":{"source_kind":"core3_world","full":true,"zone":"tatooine","players":[],"actors":[]},"poses":[],"npc_speech":{"sequence":sequence,"events":[{"id":str(sequence),"actor_id":"42","zone":"tatooine","building_id":"0","cell_index":0,"language_key":"rodese","text":"Native presentation","age_ms":0,"lifetime_ms":6000}],"languages":[{"id":3,"progress_basis_points":250}]}}
func _initialize()->void:call_deferred("run")
func run()->void:
	var host:=Host.new();root.add_child(host);host.stage=Fixture.Stage.new();host.add_child(host.stage);host.player=Fixture.Player.new();host.add_child(host.player)
	var sync:=preload("res://multiplayer/client_sync.gd").new();sync.set_process(false);host.add_child(sync);sync.app=host;host.multiplayer_sync=sync;sync.owner_character="101";sync.owner_session="owned"
	sync.players=Players.new();host.add_child(sync.players);sync.entities=Entities.new();host.add_child(sync.entities);sync.chatter=preload("res://chatter/controller.gd").new();host.add_child(sync.chatter);sync.chatter.setup(host);sync.chatter.set_process(false)
	check(sync.apply_response(packet(1),1) and sync.chatter.active.size()==1,"Production authenticated sync forwards recipient-only native speech")
	var forged:=packet(2);forged.character_id="999"
	check(not sync.apply_response(forged,2) and sync.chatter.sequence==1 and sync.chatter.languages[0].progress_basis_points==250,"Foreign character cannot replace speech or native language progress")
	forged=packet(2);forged.session_id="previous"
	check(not sync.apply_response(forged,2) and sync.chatter.sequence==1,"Old session cannot emit a bubble after ownership changes")
	forged=packet(2);forged.zone="naboo"
	check(not sync.apply_response(forged,2) and sync.chatter.sequence==1,"Old planet response is rejected before speech presentation")
	check(not sync.apply_response(packet(1),1) and sync.chatter.created==1,"Replayed transport packet cannot duplicate recipient speech")
	var legacy:=packet(2);legacy.erase("npc_speech")
	check(sync.apply_response(legacy,2) and sync.chatter.created==1,"Backend without additive speech fields preserves normal multiplayer sync")
	sync.reset();check(sync.chatter.active.is_empty() and sync.chatter.languages.is_empty() and sync.chatter.sequence==-1,"Actual session reset drops speech and private knowledge state")
	host.free();await process_frame
	var report:Dictionary={"passed":failures.is_empty(),"checks":checks,"failures":failures,"native_requests_sent":0,"renderer":"dummy","live_xr":false};FileAccess.open("res://../runtime/evidence/chatter-sync.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "));print(JSON.stringify(report));quit(0 if failures.is_empty() else 1)
