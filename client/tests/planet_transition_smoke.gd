extends SceneTree
## Actual original world/terrain/collision transitions. No Core3 session or XR.
class Host extends "res://scripts/main.gd":
	func _ready()->void:pass
	func _process(_delta:float)->void:pass
	func _physics_process(_delta:float)->void:pass
var errors:Array=[]
var checks:=0
var rows:Array=[]
var app:Host
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:errors.append(label);push_error(label)
func _initialize()->void:
	create_timer(180).timeout.connect(func():print("PLANET_TIMEOUT "+JSON.stringify({"loading":app.loading_screen.message,"terrain":app.terrain.report if is_instance_valid(app.terrain) else {},"world":app.world_stream.report if is_instance_valid(app.world_stream) else {}}));quit(2))
	call_deferred("run")
func run()->void:
	app=Host.new();root.add_child(app)
	app.args={"desktop":true,"planet":"corellia"};app.screenshot_path="planet-test"
	app.configure_inputs();app.player=app.PlayerScript.new();app.add_child(app.player)
	app.player.active=false;app.player.set_physics_process(false);app.make_ui()
	var timer:=Timer.new();app.add_child(timer);timer.wait_time=10;timer.timeout.connect(func():print("PLANET_PROGRESS "+(app.loading_screen.message if is_instance_valid(app.loading_screen) else "setup")));timer.start()
	await app.enter_stage(true)
	check(app.world_ready and app.active_planet=="corellia","Production offline entry loads Corellia")
	var native:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/evidence/planets-native-roundtrip.json"))
	for zone in ["naboo","tatooine"]:
		var descriptor:Dictionary=app.planet_catalog.descriptor(zone)
		var point:Array=descriptor.default_entry
		var destination:Dictionary={"zone":zone,"position":point,"building_id":"0","cell_index":0}
		for row:Dictionary in native.responses:
			if row.path=="/services/travel_board" and row.response.get("transport",{}).get("destination",{}).get("zone","")==zone:
				destination=row.response.transport.destination.duplicate(true);break
		var old_stage:WeakRef=weakref(app.stage)
		var epoch:int=app.datapad_epoch
		var travelled:bool=await app.perform_service_transport({"id":"fixture-"+zone,"destination":destination})
		check(travelled,"Safe actual-source placement completes for "+zone)
		check(app.active_planet==zone and app.world_ready and not app.loading_screen.active,"World published only after destination placement: "+zone)
		check(old_stage.get_ref()==null and app.datapad_epoch==epoch+1,"Previous world and collision retired with RPC epoch fenced: "+zone)
		check(app.stage.get_meta("planet")==zone and app.terrain.source_manifest.planet==zone,"Original terrain/stage contexts follow destination: "+zone)
		rows.append({"planet":zone,"source_position":str(app.source_position_at(app.player.global_position)),"placement":travelled,"world":app.world_stream.report,"terrain":app.terrain.report})
		if not travelled:break
	var old_stage=app.stage
	var unsupported:Dictionary=await app.prepare_destination_world({"zone":"mustafar","position":[0,0,0]})
	check(not unsupported.ok and app.stage==old_stage,"Unsupported planet preflight preserves current world")
	# Simulate unavailable converted data after the native transport was accepted.
	var destination:Dictionary={"zone":"tatooine","position":[3599.894,5,-4780.4487],"building_id":"0","cell_index":0}
	app.planet_catalog.manifest.planets.tatooine.ready=false
	check(not await app.perform_service_transport({"id":"retry-fixture","destination":destination}),"Missing destination assets stop placement")
	check(app.loading_screen.active and app.loading_screen.failed and not app.world_ready and not app.player.is_physics_processing(),"Failed transport remains covered and cannot transmit movement")
	check(app.dismiss_loading_error(),"Menu retries the retained authoritative destination")
	var deadline:=Time.get_ticks_msec()+20000
	while app.loading_stage and Time.get_ticks_msec()<deadline:await process_frame
	check(app.world_ready and app.retry_transport.is_empty() and not app.loading_screen.active,"Fresh asset preflight retries actual placement and restores the world")
	var report:Dictionary={"passed":errors.is_empty(),"checks":checks,"errors":errors,"rows":rows,"renderer":"dummy" if DisplayServer.get_name()=="headless" else RenderingServer.get_current_rendering_method(),"live_xr":false,"native_transport":"recorded actual Core3 roundtrip","original_world_and_collision":true}
	FileAccess.open("res://../runtime/evidence/planet-transition-smoke.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "));print(JSON.stringify(report))
	app.queue_free();await process_frame;await process_frame;quit(0 if errors.is_empty() else 1)
