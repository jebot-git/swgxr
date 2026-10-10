extends SceneTree
class Host extends "res://scripts/main.gd":
	func _ready()->void:pass
	func _process(_delta:float)->void:pass
	func _physics_process(_delta:float)->void:pass
func _initialize()->void:call_deferred("run")
func run()->void:
	var args:=OS.get_cmdline_user_args()
	var app:=Host.new();root.add_child(app);app.backend_url=args[0]
	if not app.remote_connection.configure({"base_url":args[0],"account":"alice","token":"A".repeat(43),"ca_certificate":args[1]}):quit(2);return
	# A native request in flight must not reserve the separate sync channel.
	app.native_http.busy=true
	var opened:=0
	for i in 3:
		var reply:Dictionary=await app.api(HTTPClient.METHOD_POST,"/session/sync",{"character_id":"123"})
		if not reply.get("ok",false) or app.presentation_http.client.get_status()!=HTTPClient.STATUS_CONNECTED:print(reply);quit(1);return
		if i==0:opened=app.presentation_http.opened_at
		elif app.presentation_http.opened_at!=opened:quit(1);return
	if not app.native_api_queue.is_empty():quit(1);return
	app.presentation_http.client.close();app.free()
	print("PRESENTATION_TLS_PASSED");quit()
