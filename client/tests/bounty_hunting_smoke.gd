extends SceneTree
## Production inventory trigger, services menus and native-state presentation.
## HTTP responses are controlled fixtures; dummy rendering is not headset evidence.
const Presentation=preload("res://bounty/presentation.gd")
const Coordinator=preload("res://scripts/services_controller.gd")
class EffectObserver extends "res://bounty/controller.gd":
	var arrivals:Array=[]
	func delivery_effect(probe:Dictionary)->void:arrivals.append(str(probe.id))
class Player extends CharacterBody3D:
	func set_interface_capture(_move:bool,_turn:bool)->void:pass
class Stage extends Node3D:
	var current_cell:Dictionary={"building_object_id":"0","cell_id":"exterior"}
class Datapad extends Node3D:
	var ui:Control
	var is_open:=false
	func set_open(value:bool)->void:is_open=value
class Live extends Node:
	var live:=false
class Host extends Node3D:
	signal release_api
	var datapad_account:="fixture"
	var datapad_character_id:="101"
	var datapad_epoch:=1
	var xr_requested:=true
	var world_ready:=true
	var loading_stage:=false
	var session_leaving:=false
	var xr_origin:XROrigin3D
	var vr_settings:Dictionary={"offhand":"left"}
	var player:CharacterBody3D
	var stage:Stage
	var tracked_avatar:Node3D
	var datapad:Datapad
	var inventory:Node3D
	var combat_rig:Node3D
	var live_combat:Live
	var services:Node3D
	var loader:Dictionary={"report":{"origin":[0,0,0]}}
	var inventory_snapshot:Dictionary={}
	var bounty:Dictionary={}
	var calls:Array=[]
	var hold_next:=false
	var fail_next:=false
	func source_position_at(point:Vector3)->Vector3:return Vector3(point.x,point.y,-point.z)
	func reconcile_inventory_presentations()->void:pass
	func update_inventory_presentation()->void:pass
	func owned_inventory_item(id:String)->Dictionary:
		for item:Dictionary in inventory_snapshot.get("items",[]):
			if str(item.id)==id:return item
		return {}
	func response()->Dictionary:return {"ok":true,"source_kind":"core3_services","character_id":datapad_character_id,"state":{"character_id":datapad_character_id,"zone":"tatooine","wallet":{"cash":100,"bank":200},"terminals":[],"missions":[{"id":"401"}],"parcels":[],"bounty":bounty.duplicate(true)},"mutation":{}}
	func api(_method:HTTPClient.Method,path:String,payload:Dictionary={})->Dictionary:
		calls.append({"path":path,"payload":payload.duplicate(true)})
		var answer:=response()
		var wait:=hold_next;hold_next=false
		var fail:=fail_next;fail_next=false
		if wait:await release_api
		await get_tree().process_frame
		if fail:return {"ok":false,"error":"native fixture rejection"}
		if path!="/services/status":answer.mutation={"success":true,"operation":path.get_file()}
		return answer
var checks:=0
var failures:Array=[]
func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures.append(label);push_error(label)
func frames(count:int=4)->void:
	for _index in range(count):await process_frame
func state()->Dictionary:return {"pve_only":true,"mission_id":"401","level":2,"stage":"signature","signature":true,"planet_known":false,"planets":["tatooine","naboo","corellia"],"waypoint":{"active":false,"planet":"hidden","position":[999,0,777]},"droids":[{"id":"501","kind":"probe","uses":3,"call_enabled":true},{"id":"502","kind":"seeker","uses":4,"find_enabled":true,"track_enabled":false}],"informants":[{"id":"601","kind":"bounty_informant","name":"Bounty informant","position":[0,0,-1],"building_id":"0","cell_index":0,"eligible":true,"can_contact":true}]}
func _initialize()->void:create_timer(30).timeout.connect(func():quit(2));call_deferred("run")
func run()->void:
	var app:=Host.new();root.add_child(app)
	app.xr_origin=XROrigin3D.new();app.add_child(app.xr_origin)
	var camera:=XRCamera3D.new();camera.name="XRCamera3D";app.xr_origin.add_child(camera);camera.position=Vector3(0,1.7,0)
	for side:String in ["LeftHand","RightHand"]:
		var hand:=XRController3D.new();hand.name=side;app.xr_origin.add_child(hand)
	app.player=Player.new();app.add_child(app.player)
	app.stage=Stage.new();app.add_child(app.stage);app.stage.set_meta("manifest",{"origin":[0,0,0]})
	app.live_combat=Live.new();app.add_child(app.live_combat)
	app.datapad=Datapad.new();app.add_child(app.datapad);app.datapad.ui=preload("res://scripts/datapad_ui.gd").new();app.datapad.add_child(app.datapad.ui);app.datapad.ui.build_ui()
	app.inventory=preload("res://scripts/xr_inventory.gd").new();app.add_child(app.inventory);app.inventory.configure(app.xr_origin,app.player);app.inventory.set_process(false);app.inventory.set_allowed(true)
	app.services=Coordinator.new();app.add_child(app.services);app.services.setup(app);app.services.set_process(false);app.services.gcw.set_physics_process(false);app.services.ui.set_process(false);app.services.set_allowed(true)
	app.bounty=state()
	app.inventory_snapshot={"items":[{"id":"501","template":Presentation.PROBE,"name":"Arakyd probe"},{"id":"502","template":Presentation.SEEKER,"name":"Seeker"}]}
	check(app.services.accept_response(app.response()),"Owned native bounty state accepted through production services coordinator")
	check(Presentation.droid_item({"template":Presentation.PROBE}) and Presentation.droid_item({"template":Presentation.SEEKER.replace("/mission_bounty","/shared_mission_bounty")}),"Both original tangible droid types accepted, including shared template names")
	check(not Presentation.droid_item({"template":"object/intangible/pet/shared_nhelper_droid.iff"}) and not Presentation.droid_item({"template":"object/weapon/ranged/pistol/pistol_cdef.iff"}),"Pet devices and weapons do not become expendable bounty droids")
	check(Presentation.choices(app.bounty,"501").map(func(row):return row.id)==app.bounty.planets,"Probe popup lists only native supported planets")
	check(Presentation.choices(app.bounty,"502").is_empty() and Presentation.choices(app.bounty,"stale").is_empty(),"Seeker and invented inventory IDs never open a planetary search popup")
	check(Presentation.launch_action(app.bounty,"502")=="bounty_seek","Basic seeker uses native one-shot find")
	app.bounty.droids[1].track_enabled=true
	check(Presentation.launch_action(app.bounty,"502")=="bounty_track","Advanced learned tracking becomes direct seeker trigger action")
	var pvp:=app.bounty.duplicate(true);pvp.pve_only=false
	check(Presentation.launch_action(pvp,"502").is_empty() and Presentation.choices(pvp,"501").is_empty() and Presentation.contacts(pvp).is_empty() and Presentation.entry(pvp).is_empty(),"PvP or unconfirmed bounty projections fail closed")
	var hidden:=Presentation.progress_text(app.bounty)
	check(not hidden.contains("999") and not hidden.contains("777") and not hidden.contains("Hidden"),"Undisclosed native waypoint is never shown in investigation text")
	var planet_only:=app.bounty.duplicate(true);planet_only.planet_known=true;planet_only.planet="naboo"
	check(Presentation.progress_text(planet_only).contains("Target planet: Naboo") and not Presentation.progress_text(planet_only).contains("999"),"Planet-only native discovery names destination without revealing coordinates")
	var novice:=app.bounty.duplicate(true);novice.level=1;novice.stage="target"
	check(not Presentation.progress_text(novice).to_lower().contains("seeker"),"Novice informant waypoint does not suggest an untrained seeker action")
	var empty:=app.bounty.duplicate(true);empty.mission_id="0"
	check(Presentation.entry(empty).is_empty() and Presentation.choices(empty,"501").is_empty() and Presentation.progress_text(empty).begins_with("Accept a PvE bounty"),"Native zero mission sentinel does not create fake investigation or droid actions")
	app.bounty.waypoint.active=true;app.bounty.waypoint.planet="naboo"
	check(Presentation.progress_text(app.bounty).contains("Naboo · X 999, Z 777"),"Revealed native waypoint uses actual report planet and coordinates")
	app.bounty.waypoint.active=false
	var rows:Array=app.services.terminal_records()
	check(rows.size()==1 and rows[0].kind=="bounty_informant" and rows[0].position==Vector3(0,0,1),"Bounty contacts reuse cell-filtered native discovery and coordinate conversion")
	app.services.ui.open_terminal(rows[0]);await frames()
	check(app.calls.is_empty() and not app.services.ui.pending,"Opening informant dialogue does not grant a signature or use generic terminal open")
	app.services.ui.panel.confirm();await frames()
	check(app.calls.size()==1 and app.calls[0].path=="/services/bounty_informant" and app.calls[0].payload.target_id=="601" and app.calls[0].payload.has("request_id"),"Explicit informant confirmation carries only selected identity and native mutation receipt token")
	check(app.services.ui.terminal.is_empty(),"Confirmed contact closes the service panel")
	app.calls.clear();app.inventory.held_item=app.inventory_snapshot.items[0].duplicate(true)
	app.inventory.update_held_trigger(.0,Transform3D.IDENTITY);app.inventory.update_held_trigger(.8,Transform3D.IDENTITY);await frames(6)
	check(app.calls.size()==1 and app.calls[0].path=="/services/status","Probe trigger refreshes native eligibility before presenting choices")
	check(app.inventory.held_item.is_empty() and app.services.ui.terminal.kind=="bounty_droid","Probe popup releases only local hand presentation and opens shared service UI")
	check(app.services.ui.panel.rows.size()==3 and not app.services.ui.pending,"Planet popup remains interactive and carries native choices")
	app.services.ui.panel.click_at(Vector2(100,128+44+22));await frames()
	check(app.calls.size()==2 and app.calls[1].path=="/services/bounty_probe" and app.calls[1].payload.search_planet=="naboo" and app.calls[1].payload.item_id=="501" and app.calls[1].payload.zone=="tatooine","Planet selection launches probe with separate search planet; source location remains current planet")
	check(app.calls[1].payload.has("request_id") and not app.calls[1].payload.has("target_id") and not app.calls[1].payload.has("mission_id"),"Client does not claim target, mission authority or search outcome")
	app.calls.clear();app.inventory.held_item=app.inventory_snapshot.items[1].duplicate(true)
	app.inventory.update_held_trigger(.8,Transform3D.IDENTITY);await frames()
	check(app.calls.is_empty(),"Held trigger cannot relaunch a droid without release")
	app.inventory.update_held_trigger(.0,Transform3D.IDENTITY);app.inventory.update_held_trigger(.8,Transform3D.IDENTITY);await frames(8)
	check(app.calls.size()==2 and app.calls[1].path=="/services/bounty_track" and app.calls[1].payload.item_id=="502" and app.services.ui.terminal.is_empty(),"Held seeker trigger directly launches native tracking without an extra menu")
	app.bounty.droids[1].track_enabled=false;app.calls.clear();app.inventory.held_item=app.inventory_snapshot.items[1].duplicate(true)
	app.inventory.update_held_trigger(.0,Transform3D.IDENTITY);app.inventory.update_held_trigger(.8,Transform3D.IDENTITY);await frames(8)
	check(app.calls.size()==2 and app.calls[1].path=="/services/bounty_seek","Basic seeker direct launch falls back to native find only")
	app.bounty.droids[1].find_enabled=false;app.calls.clear();app.inventory.held_item=app.inventory_snapshot.items[1].duplicate(true)
	app.inventory.update_held_trigger(.0,Transform3D.IDENTITY);app.inventory.update_held_trigger(.8,Transform3D.IDENTITY);await frames(8)
	check(app.calls.size()==1 and app.calls[0].path=="/services/status","Native-disabled seeker does not mutate or invent a fallback")
	app.calls.clear();app.fail_next=true;app.inventory.held_item=app.inventory_snapshot.items[0].duplicate(true)
	app.inventory.update_held_trigger(.0,Transform3D.IDENTITY);app.inventory.update_held_trigger(.8,Transform3D.IDENTITY);await frames(8)
	check(app.calls.size()==1 and app.services.ui.terminal.is_empty(),"Rejected status cannot open a stale planetary action menu")
	app.services.accept_response(app.response());app.datapad.ui.set_owned_missions([{"id":"401"}]);app.datapad.ui.set_entries([{"id":"old-waypoint","category":"waypoints"}]);app.datapad.ui.select_category("data")
	check(app.datapad.ui.bounty_missions.size()==1 and app.datapad.ui.selected_entry.type=="bounty_mission" and app.datapad.ui.cancel_mission_button.visible,"Investigation survives ordinary datapad refresh and reuses native mission cancellation")
	app.bounty={"pve_only":true,"mission_id":"","droids":[],"informants":[]};app.services.accept_response(app.response())
	check(app.datapad.ui.bounty_missions.is_empty() and not app.datapad.ui.entries.any(func(row):return row.get("type","")=="bounty_mission"),"Mission completion or cancellation removes stale investigation projection")
	app.bounty=state();app.services.accept_response(app.response());app.calls.clear();app.hold_next=true;app.inventory.held_item=app.inventory_snapshot.items[0].duplicate(true)
	app.inventory.update_held_trigger(.0,Transform3D.IDENTITY);app.inventory.update_held_trigger(.8,Transform3D.IDENTITY);await frames()
	app.datapad_epoch+=1;app.services.reset();app.release_api.emit();await frames(8)
	check(app.services.ui.terminal.is_empty() and not app.services.bounty.busy and app.datapad.ui.bounty_missions.is_empty(),"Character epoch change discards in-flight droid response without reopening prior character UI")
	var observer:=EffectObserver.new();app.add_child(observer);observer.set_process(false);observer.app=app;observer.services=app.services
	app.services.state.bounty=state();app.services.state.bounty.stage="searching";app.services.state.bounty.probe={"id":"701","status":"searching","position":[0,0,0]};observer.observe({})
	check(observer.arrivals.is_empty(),"Reconnect to already landed probe does not replay original delivery effect")
	app.services.state.bounty.stage="probe_calling";app.services.state.bounty.probe={};observer.observe({})
	app.services.state.bounty.stage="searching";app.services.state.bounty.probe={"id":"702","status":"searching","position":[0,0,0]};observer.observe({});observer.observe({})
	check(observer.arrivals==["702"],"Observed native probe arrival plays one original delivery effect across repeated snapshots")
	observer.reset();observer.observe({})
	check(observer.arrivals==["702"],"Controller reset does not replay retained native probe arrival")
	app.services.state.bounty.mission_id="402";app.services.state.bounty.probe.id="703";observer.observe({})
	check(observer.arrivals==["702"],"Different mission cannot reuse previous investigation delivery transition")
	app.free();await frames()
	var report:Dictionary={"passed":failures.is_empty(),"checks":checks,"failures":failures,"renderer":"dummy","xr_mode":"off","scope":"production client interactions with controlled native HTTP fixtures; no live server or GPU/headset validation"}
	var output:=FileAccess.open("res://../runtime/evidence/bounty/client.json",FileAccess.WRITE);if output:output.store_string(JSON.stringify(report,"\t"))
	print(JSON.stringify(report));quit(0 if failures.is_empty() else 1)
