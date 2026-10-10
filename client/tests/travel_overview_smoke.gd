extends SceneTree
var failures:Array[String]=[]
var checks:=0
func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures.append(label);push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	var panel:=preload("res://scripts/service_panel.gd").new();root.add_child(panel)
	var calls:Array=[];panel.action_requested.connect(func(action,payload):calls.append({"action":action,"payload":payload}))
	var rows:Array=[{"id":"Mos Eisley","name":"Mos Eisley Starport","planet":"tatooine","position":[3528,5,-4804],"price":100},{"id":"Bestine","name":"Bestine Starport","planet":"tatooine","position":[-1290,0,-3590],"price":120},{"id":"Theed","name":"Theed Starport","planet":"naboo","position":[-4858,6,4162],"price":500}]
	panel.configure({"id":"terminal","kind":"travel","name":"STARPORT · TRAVEL","destinations":rows},{"cash":2000,"bank":5000});panel.selected=0
	var map=panel.travel_overview;map.setup()
	check(map.catalog.maps.has("tatooine") and map.catalog.maps.has("naboo"),"Original planet map descriptors load")
	var p:Vector2=map.pixel(rows[0]);check(map.RECT.has_point(p) and p.x>map.RECT.get_center().x and p.y>map.RECT.get_center().y,"Native east/south arrival coordinates map to correct image quadrant")
	check(map.select_at(map.pixel(rows[1]),rows,0)==1,"Map marker selects matching native destination on current planet")
	panel.click_at(map.pixel(rows[1]));check(panel.selected==1 and calls.is_empty(),"Marker selection never buys a ticket")
	panel.click_at(panel.CONFIRM_RECT.get_center());check(calls.size()==1 and calls[0].action=="travel_purchase" and calls[0].payload.destination_id=="Bestine" and calls[0].payload.destination_planet=="tatooine","Explicit purchase preserves selected native route identity")
	panel.set_pending(false);panel.selected=2
	check(map.select_at(map.pixel(rows[0]),rows,2)==-1,"Another planet's destination cannot be selected on current map")
	check(panel.row_at(map.RECT.get_center())==-1,"Map cannot be misread as list row")
	check(not map.pixel({"planet":"tatooine"}).is_finite(),"Missing location is not invented")
	if "--capture" in OS.get_cmdline_user_args():
		panel.selected=0;root.size=Vector2i(860,620)
		for i in range(8):await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../runtime/evidence/ship-flight-20261010/travel-overview.png"))
	print(JSON.stringify({"passed":failures.is_empty(),"checks":checks,"failures":failures,"native_transport":"mocked"}));quit(0 if failures.is_empty() else 1)
