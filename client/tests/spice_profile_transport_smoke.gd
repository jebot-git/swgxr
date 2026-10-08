extends SceneTree
class Harness extends "res://scripts/main.gd":
	func _ready()->void:pass
	func _process(_delta:float)->void:pass
	func _physics_process(_delta:float)->void:pass
class Endpoint extends Node:
	var server:=TCPServer.new()
	var peers:Array=[]
	var paths:Array=[]
	func _process(_delta:float)->void:
		if server.is_connection_available():peers.append({"peer":server.take_connection(),"text":""})
		for row in peers.duplicate():
			row.peer.poll()
			if row.peer.get_available_bytes()>0:row.text+=row.peer.get_utf8_string(row.peer.get_available_bytes())
			if "\r\n\r\n" in row.text:
				paths.append(row.text.get_slice("\r\n",0))
				var payload:='{"backend":"core3","weapons":[],"player_combat":{},"fixture":"loopback mock"}'
				row.peer.put_data(("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n"%payload.to_utf8_buffer().size()+payload).to_utf8_buffer());peers.erase(row)
				# Keep the stream alive until the HTTP client drains it.
				get_tree().create_timer(.5).timeout.connect(row.peer.disconnect_from_host)
var checks:=0
var errors:Array=[]
func check(value:bool,label:String)->void:
	checks+=1
	if not value:errors.append(label);push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	create_timer(10).timeout.connect(func():quit(2))
	var endpoint:=Endpoint.new();root.add_child(endpoint)
	check(endpoint.server.listen(0,"127.0.0.1")==OK,"Isolated loopback HTTP fixture listens")
	var app:=Harness.new();root.add_child(app);app.backend_url="http://127.0.0.1:%d"%endpoint.server.get_local_port();app.live_combat_reserved=true
	var result:=await app.api(HTTPClient.METHOD_GET,"/weapons?account=fixture&character_id=500")
	check(result.get("ok",false) and endpoint.paths.size()==1 and endpoint.paths[0].begins_with("GET /weapons?"),"Reserved live session permits owner weapon-profile read through actual main HTTP transport")
	var denied:=await app.api(HTTPClient.METHOD_GET,"/inventory?account=fixture&character_id=500")
	check(not denied.ok and endpoint.paths.size()==1,"Other legacy GET remains blocked without touching server")
	denied=await app.api(HTTPClient.METHOD_POST,"/weapons?account=fixture&character_id=500",{})
	check(not denied.ok and endpoint.paths.size()==1,"Weapon exception permits reads only")
	check(app.api_requests_in_flight==0,"Profile read leaves no outstanding request gate")
	app.queue_free();endpoint.server.stop();endpoint.queue_free();await process_frame
	print(JSON.stringify({"checks":checks,"errors":errors,"transport":"real loopback HTTP, mocked backend","renderer":"dummy","headset_validated":false}));quit(0 if errors.is_empty() else 1)
