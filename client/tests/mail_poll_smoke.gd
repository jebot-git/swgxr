extends SceneTree
class Host extends Node:
	var datapad_epoch:=1
	var datapad:Node
	var xr_requested:=false
	var world_ready:=true
	var menu:Control
class Service extends Node:
	signal reply
	var busy:=false
	var calls:Array=[]
	var controller:Node
	func request(action:String,detail:Dictionary)->Dictionary:
		busy=true;calls.append({"action":action,"detail":detail.duplicate(true)})
		await reply;busy=false
		var response:Dictionary={"ok":true,"state":{"mail":{"unread":1,"total":1}},"mutation":{}}
		controller.observe(response);return response
var errors:Array=[]
func check(ok:bool,label:String)->void:
	if not ok:errors.append(label);push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	var app:=Host.new();root.add_child(app);app.menu=Control.new();app.add_child(app.menu);app.menu.hide()
	var service:=Service.new();app.add_child(service)
	var controller=preload("res://mail/controller.gd").new();app.add_child(controller);controller.set_process(false);controller.app=app;controller.services=service;controller.epoch=1;service.controller=controller
	controller.panel=preload("res://mail/panel.gd").new();app.add_child(controller.panel);controller.panel.compose();controller.active=true
	controller.request("mail_status",{})
	check(controller.pending and controller.panel.recipient.editable,"Background mail notification does not lock composition")
	controller.request("mail_send",{"recipient":"Tester","subject":"Hello","body":"Mail"})
	check(service.calls.size()==1 and not controller.queued.is_empty(),"Send during a notification poll waits without losing intent")
	service.reply.emit();await process_frame;await process_frame
	check(service.calls.size()==2 and service.calls[1].action=="mail_send" and controller.panel.pending,"Queued send begins after summary completes")
	service.reply.emit();await process_frame
	check(not controller.pending and controller.panel.status.text=="Mail sent." and controller.unread==1,"Send confirmation and new-mail notification update independently")
	app.free();print(JSON.stringify({"passed":errors.is_empty(),"errors":errors,"network":"mocked","renderer":"dummy"}));quit(0 if errors.is_empty() else 1)
