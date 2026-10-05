extends SceneTree
## Real main.gd HTTP orchestration, dedicated Core3 fixture; XR stays disabled.
class Harness extends "res://scripts/main.gd":
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass
	func _physics_process(_delta: float) -> void: pass
class Pad extends Node3D:
	var ui: Control
class Terrain extends Node3D:
	var evaluator := SwgTerrainEvaluator.new()
var errors: Array[String] = []
func _initialize() -> void:call_deferred("run")
func check(value: bool, message: String) -> void:
	if not value:errors.append(message);push_error(message)
func run() -> void:
	var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/server/datapad-fixture.json"))
	var app := Harness.new();root.add_child(app)
	app.datapad=Pad.new();app.add_child(app.datapad)
	app.datapad.ui=load("res://scripts/datapad_ui.gd").new();app.datapad.add_child(app.datapad.ui)
	app.datapad.ui.configure(JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/assets/datapad/catalog.json")),ProjectSettings.globalize_path("res://../runtime/assets/datapad"))
	app.datapad_account=fixture.account;app.datapad_character_id=fixture.id
	app.player=CharacterBody3D.new();app.add_child(app.player);app.player.position=Vector3(-77.5,0.64,1.67)
	app.loader.report.origin=[3618.98388671875,5,-4801.0859375]
	var source := app.datapad_source_position()
	check(source.distance_to(Vector3(3541.48388671875,5.64,-4802.7559375))<0.001,"Stage position conversion disagrees with SWG XYZ")
	await app.refresh_datapad()
	var ui=app.datapad.ui
	var initial: Array=ui.entries.duplicate(true)
	check(not ui.waypoint_button.disabled and not app.datapad_request_pending,"Core3 refresh did not restore controls")
	check(initial.any(func(row):return row.get("template","")=="object/intangible/pet/shared_nhelper_droid.iff"),"Authoritative starter helper droid missing")
	check(initial.filter(func(row):return row.category=="schematics").size()==30,"Artisan learned recipes missing")
	var label := "Godot main " + str(Time.get_ticks_usec())
	await app.create_datapad_waypoint(source,label)
	var matches: Array=ui.entries.filter(func(row):return row.name==label)
	check(matches.size()==1,"Main waypoint create did not populate authoritative UI record")
	var waypoint: Dictionary=matches[0] if not matches.is_empty() else {}
	if not waypoint.is_empty():
		check(typeof(waypoint.id)==TYPE_STRING,"64-bit waypoint identifier lost string representation")
		check(Vector3(waypoint.position[0],waypoint.position[1],waypoint.position[2]).distance_to(source)<0.002,"Waypoint coordinate roundtrip changed positions")
	await app.refresh_datapad()
	check(ui.entries.any(func(row):return row.get("id","")==waypoint.get("id","!")),"Fresh main refresh lost Core3 waypoint")
	if not waypoint.is_empty():
		check(waypoint.get("deletable",false),"Personal waypoint deletion permission missing")
		await app.delete_datapad_entry(waypoint)
		check(not ui.entries.any(func(row):return row.get("id","")==waypoint.id),"Main delete retained waypoint")
		await app.refresh_datapad()
		check(not ui.entries.any(func(row):return row.get("id","")==waypoint.id),"Deleted waypoint returned after login")
	app.backend_url="http://127.0.0.1:1"
	await app.refresh_datapad()
	check(ui.waypoint_button.disabled and ui.connection_status.text.contains("unavailable"),"Offline HTTP error not visible and creation not disabled")
	app.datapad_character_id=""
	await app.refresh_datapad()
	check(ui.entries.all(func(row):return row.get("reference_only",false)),"Offline inspection retained private character records")
	check(ui.waypoint_button.disabled,"Offline reference mode permits waypoint writes")
	var report := {"passed":errors.is_empty(),"errors":errors,"fixture_id":fixture.id,"waypoint":waypoint,"real_core3_http":true,"hardware_tested":false,"test":"main_datapad_refresh_create_offline"}
	FileAccess.open("res://../runtime/evidence/datapad-main-http-smoke.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print(JSON.stringify(report));app.queue_free();await process_frame;quit(0 if errors.is_empty() else 1)
