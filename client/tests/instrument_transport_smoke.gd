extends SceneTree
const Fixture=preload("res://tests/spice_profile_transport_smoke.gd")
var checks:=0
var errors:Array=[]
func check(value:bool,label:String)->void:
	checks+=1
	if not value:errors.append(label);push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	create_timer(10).timeout.connect(func():quit(2))
	var endpoint:=Fixture.Endpoint.new();root.add_child(endpoint)
	check(endpoint.server.listen(0,"127.0.0.1")==OK,"Isolated instrument HTTP fixture listens")
	var app:=Fixture.Harness.new();root.add_child(app);app.backend_url="http://127.0.0.1:%d"%endpoint.server.get_local_port();app.live_combat_reserved=true
	for path in ["/entertainer/status","/entertainer/perform","/entertainer/flourish","/entertainer/image_open","/performance","/inventory/equip","/inventory/unequip"]:
		var count:=endpoint.paths.size()
		var result:=await app.api(HTTPClient.METHOD_POST,path,{"account":"fixture","character_id":"500","live_session_id":"owned"})
		check(result.get("ok",false) and endpoint.paths.size()==count+1 and endpoint.paths.back().begins_with("POST "+path+" "),"Live instrument path reaches real main HTTP transport: "+path)
	var count:=endpoint.paths.size()
	var denied:=await app.api(HTTPClient.METHOD_POST,"/inventory/consume",{})
	check(not denied.ok and endpoint.paths.size()==count,"Unreviewed inventory mutation stays blocked by reserved-session gate")
	denied=await app.api(HTTPClient.METHOD_GET,"/entertainer/status")
	check(not denied.ok and endpoint.paths.size()==count,"Instrument exception only permits supported POST requests")
	app.queue_free();endpoint.server.stop();endpoint.queue_free();await process_frame
	print(JSON.stringify({"checks":checks,"errors":errors,"transport":"actual loopback HTTP, mocked backend","renderer":"dummy","headset_validated":false}));quit(0 if errors.is_empty() else 1)
