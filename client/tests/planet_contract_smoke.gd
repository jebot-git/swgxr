extends SceneTree
## Replays actual native ticket/transport envelopes without contacting Core3.
const Fixtures=preload("res://tests/services_controller_smoke.gd")
class Host extends Fixtures.Host:
	var active_planet:="tatooine"
	var planet_assets:Dictionary={}
	var planet_catalog=preload("res://scripts/planet_catalog.gd").new()
	var gameplay_session:Node
	var vehicles:Node
	var medic:Node
class RetryHost extends "res://scripts/main.gd":
	var retries:Array=[]
	func _ready()->void:pass
	func _process(_delta:float)->void:pass
	func perform_service_transport(value:Dictionary)->bool:retries.append(value);return false
var failures:Array=[]
var checks:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	var app:=Host.new();root.add_child(app);app.planet_catalog.configure()
	for zone in app.planet_catalog.ZONES:
		check(app.planet_catalog.readiness(zone).ok,"All feature manifests ready for "+zone)
		var environment:=preload("res://scripts/environment_presentation.gd").new();root.add_child(environment)
		check(environment.configure(app.planet_catalog.descriptor(zone).environment),"Original celestial/environment manifest loads for "+zone)
		environment.free()
	check(not app.planet_catalog.readiness("mustafar").ok,"Missing expansion source never creates a destination")
	var coordinator:=preload("res://scripts/services_controller.gd").new();app.add_child(coordinator);coordinator.app=app;coordinator.set_process(false)
	app.player=CharacterBody3D.new();app.add_child(app.player);app.stage=Fixtures.Stage.new();app.add_child(app.stage)
	app.live_combat=Fixtures.Live.new();app.add_child(app.live_combat)
	app.gameplay_session=preload("res://scripts/gameplay_session.gd").new();app.add_child(app.gameplay_session);app.gameplay_session.setup(app);app.gameplay_session.set_process(false)
	var proof:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/evidence/planets-native-roundtrip.json"))
	var board:Dictionary={}
	for row:Dictionary in proof.responses:
		if row.path=="/services/travel_board" and row.response.get("transport",{}).get("destination",{}).get("zone","")=="naboo":board=row.response;break
	check(not board.is_empty(),"Actual CoreCU Tatooine to Naboo transport fixture exists")
	app.datapad_character_id=str(board.character_id)
	app.gameplay_session.live=true;app.gameplay_session.session_id=str(board.live_response.session_id);app.gameplay_session.sequence=int(board.live_response.sequence)-1
	var deliveries:Array=[];app.gameplay_session.transport_required.connect(func(row):deliveries.append(row))
	check(coordinator.accept_response(board),"Newer owned cross-zone native receipt enters persistent transport flow")
	check(deliveries.size()==1 and deliveries[0].destination.zone=="naboo","Original CoreCU destination survives the client bridge unchanged")
	check(coordinator.state.is_empty(),"Destination UI rows are not installed into the previous world")
	var stale:=board.duplicate(true);stale.erase("live_response")
	check(not coordinator.accept_response(stale),"Cross-zone services without owned transport cannot replace source state")
	var foreign:=board.duplicate(true);foreign.live_response.session_id="foreign"
	check(not coordinator.accept_response(foreign),"Foreign transport cannot switch this character's planet")
	coordinator.set_allowed(true);coordinator.state.tickets=[{"id":"missing-assets","destination_planet":"mustafar"}]
	var denied:Dictionary=await coordinator.request("travel_board",{"ticket_id":"missing-assets"})
	check(not denied.get("ok",true) and app.calls.is_empty(),"Missing destination assets prevent boarding before any native ticket mutation")
	denied=await coordinator.request("travel_purchase",{"destination_planet":"mustafar","destination_id":"fixture"})
	check(not denied.get("ok",true) and app.calls.is_empty(),"Missing destination assets prevent purchase before debit")
	app.active_planet="naboo"
	check(coordinator.identity_payload().zone=="naboo" and app.gameplay_session.identity().zone=="naboo","Services and native movement send the active source-zone fence")
	var retry:=RetryHost.new();root.add_child(retry);retry.args={};retry.ensure_loading_screen();retry.loading_screen.fail("missing destination");retry.retry_transport={"destination":{"zone":"naboo"}};retry.retry_transport_service=true
	check(retry.dismiss_loading_error() and retry.retries.size()==1 and retry.loading_screen.active,"Loading failure retry preserves cover and retries the exact destination")
	var map:=preload("res://scripts/datapad_ui.gd").new();root.add_child(map)
	var map_catalog:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/assets/datapad/catalog.json"))
	map.configure(map_catalog,ProjectSettings.globalize_path("res://../runtime/assets/datapad"));map.set_planet("naboo")
	check(map.map.texture!=null and map.map.map_data.texture==map_catalog.maps.naboo.texture,"Datapad loads original destination raster")
	check(not map.map.source_services.is_empty() and str(map.map.map_data.service_directory).contains("/naboo/"),"Destination original terminals and trainers populate map references")
	check(map.entries.filter(func(row):return row.get("reference_only",false)).all(func(row):return row.planet=="naboo"),"Reference POIs contain only destination planet")
	map.free();retry.free();app.free();await process_frame
	var report:Dictionary={"passed":failures.is_empty(),"checks":checks,"failures":failures,"native_envelopes":"recorded actual CoreCU roundtrip","network":"none","xr":"off"}
	FileAccess.open("res://../runtime/evidence/planet-contract-smoke.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "));print(JSON.stringify(report));quit(0 if failures.is_empty() else 1)
