extends SceneTree
## Original models in the real nested wrist viewports; network snapshots are fixtures.
class Host extends Node3D:
	var datapad:Node3D
	var datapad_character_id:="preview-fixture"
	var tracked_avatar:Node3D
var errors:Array[String]=[]
var checks:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:errors.append(label);push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	var capture:=OS.get_cmdline_user_args().has("--capture")
	var app:=Host.new();root.add_child(app)
	var rig=load("res://xr/player_rig.tscn").instantiate();app.add_child(rig)
	var body:CharacterBody3D=rig.get_node("PlayerBody");body.active=false
	app.datapad=preload("res://scripts/xr_datapad.gd").new();app.add_child(app.datapad)
	app.datapad.configure(rig,body);app.datapad.set_process(false)
	var ui:Control=app.datapad.ui
	var controller:=preload("res://vehicles/controller.gd").new();app.add_child(controller)
	controller.set_process(false);controller.set_physics_process(false);controller.app=app
	var device:Dictionary={"id":"owned-x31","category":"vehicles","name":"X31 Landspeeder","template":"object/intangible/vehicle/shared_landspeeder_x31_pcd.iff"}
	var mobile:Dictionary={"id":"owned-x31","name":"X31 Landspeeder","template":"object/mobile/vehicle/landspeeder_x31.iff","spawned":false}
	var snapshot:Dictionary={"source_kind":"core3_vehicles","character_id":app.datapad_character_id,"vehicles":[],"datapad":[mobile],"seat":{}}
	ui.set_entries([device]);ui.select_category("vehicles")
	check(ui.vehicle_icon(device)==null,"Unresolved native control device never guesses a replacement model")
	controller.observe(snapshot)
	check(ui.filtered_entries[0].template==mobile.template and ui.detail_preview.visible,"Native vehicle snapshot supplies original preview model")
	for i in range(5):
		ui.set_entries([device,{"id":"waypoint","category":"waypoints","name":"Survey"}])
		ui.select_category("vehicles")
		check(ui.selected_entry.template==mobile.template and ui.detail_preview.visible,"Datapad or waypoint refresh retains authoritative model %d"%i)
	ui.set_entries([]);ui.set_entries([device]);controller.observe(snapshot)
	check(ui.selected_entry.template==mobile.template,"Identical vehicle snapshot repairs a recreated datapad")
	# Exercise render-once icons created while the parent wrist screen is closed.
	if capture:
		root.size=Vector2i(1400,900)
		var camera:=Camera3D.new();app.add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=.85;camera.position=Vector3(.15,.14,1);camera.current=true
		for i in range(8):await process_frame
		app.datapad.set_allowed(true);app.datapad.set_open(true)
		for i in range(12):await process_frame
		await RenderingServer.frame_post_draw
		var icon:Image=ui.detail_preview.texture.get_image()
		var opaque:=0
		for y in range(icon.get_height()):
			for x in range(icon.get_width()):
				if icon.get_pixel(x,y).a>.5:opaque+=1
		check(opaque>1000,"Nested wrist viewport renders more than 1000 opaque original vehicle pixels")
		icon.save_png("res://../runtime/evidence/live-regressions/vehicle-preview-icon.png")
		root.get_texture().get_image().save_png("res://../runtime/evidence/live-regressions/vehicle-datapad-vulkan.png")
	ui.set_entries([])
	check(ui.vehicle_details.is_empty(),"Character clear removes vehicle identity associations")
	var report:Dictionary={"checks":checks,"passed":errors.is_empty(),"errors":errors,"renderer":"forward_plus" if capture else "dummy","network":"fixture","headset_tested":false}
	FileAccess.open("res://../runtime/evidence/live-regressions/vehicle-datapad-"+("vulkan" if capture else "headless")+".json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print(JSON.stringify(report));app.free();quit(0 if errors.is_empty() else 1)
