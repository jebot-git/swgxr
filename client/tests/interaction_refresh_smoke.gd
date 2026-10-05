extends SceneTree
const Anchor=preload("res://scripts/body_grab_anchor.gd")
class Session extends Node:
	var live:=true
	var session_id:="native-gameplay-fixture"
class Host extends Node3D:
	var datapad_character_id:="fixture"
	var datapad_account:="fixture"
	var datapad_epoch:=1
	var live_combat:Node
	var gameplay_session:Node
	var ensure_calls:=0
	var ensure_ok:=true
	func ensure_gameplay_session()->bool:
		ensure_calls+=1
		await get_tree().process_frame
		if not ensure_ok:return false
		gameplay_session=Session.new();add_child(gameplay_session);return true
	var stage:Node3D
	var datapad:Node
	var calls:Array=[]
	var background_allowed:=true
	func try_background_poll(_family:String)->bool:return background_allowed
	var reply:Dictionary={}
	func source_position_at(p:Vector3)->Vector3:return Vector3(p.x+100,p.y,-p.z+200)
	func api(method:HTTPClient.Method,path:String,payload:Dictionary={})->Dictionary:
		calls.append({"path":path,"payload":payload.duplicate(true)})
		await get_tree().process_frame
		return reply.duplicate(true)
var checks:=0
var errors:Array[String]=[]
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:errors.append(message);push_error(message)
func _initialize()->void:call_deferred("run")
func run()->void:
	var head:=Transform3D(Basis.IDENTITY,Vector3(4,1.7,8));var rig:=Transform3D.IDENTITY
	var hip:=Anchor.from_pose(head,rig,Vector3(-.22,-.75,0))
	head.basis=Basis.from_euler(Vector3(.6,PI/2,.3))
	check(Anchor.from_pose(head,rig,Vector3(-.22,-.75,0)).origin.is_equal_approx(Vector3(4,.95,8.22)),"Headset facing rotates grab offset independently of pitch and roll")
	rig.basis=Basis(Vector3.UP,PI/2)
	var turned:=Anchor.from_pose(head,rig,Vector3(-.22,-.75,0))
	check(turned.basis==Basis.IDENTITY and turned.origin.is_equal_approx(Vector3(4,.95,8.22)),"Rig heading does not add a second turn to headset-facing grab offset")
	var ui:=preload("res://scripts/datapad_ui.gd").new();root.add_child(ui)
	var icon:=ui.vehicle_icon({"template":"object/mobile/vehicle/landspeeder_x31.iff"})
	check(icon!=null and ui.vehicle_previews.size()==1,"Authoritative X31 mobile template renders original 3D datapad icon")
	check(ui.vehicle_icon({"template":"object/intangible/vehicle/landspeeder_x31_pcd.iff"})==null,"Unresolved control device never guesses a replacement vehicle model")
	check(ui.vehicle_icon({"template":"object/mobile/vehicle/landspeeder_x31.iff"})==icon and ui.vehicle_previews.size()==1,"Repeated selection reuses one bounded render-once original preview")
	if OS.get_cmdline_user_args().has("--capture"):
		root.size=Vector2i(1450,625);ui.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT);ui.size=Vector2(900,625)
		var detail:Control=ui.take_detail_panel();root.add_child(detail);detail.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT);detail.position=Vector2(910,0);detail.size=Vector2(540,625)
		var directory:=ProjectSettings.globalize_path("res://../runtime/assets/datapad")
		ui.configure(JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("catalog.json"))),directory)
		ui.set_entries([{"id":"fixture-device","category":"vehicles","name":"X31 Landspeeder","template":"object/mobile/vehicle/landspeeder_x31.iff","description":"Original vehicle model · synthetic UI fixture","spawned":false}]);ui.select_category("vehicles")
		for frame in range(8):await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../runtime/evidence/datapad-vehicle-preview.png"))
		detail.queue_free()
	var inv:=preload("res://scripts/inventory_ui.gd").new();root.add_child(inv);var inv_detail:Control=inv.configure_details();root.add_child(inv_detail)
	inv.set_snapshot({"inventory":{"id":"inventory","capacity":80},"containers":[{"id":"bag","parent_id":"inventory"}],"items":[{"id":"stack","container_id":"bag","quantity":10,"split_supported":true,"split_available":true,"split_max_quantity":9}]})
	inv.set_pending(true);inv.open_container("bag");inv.select_item(inv.snapshot.items[0])
	check(inv.container_id=="bag" and inv.pending and inv.split_button.disabled and not inv.container_switch.disabled,"Cached inventory remains browsable while authoritative mutation stays locked")
	inv.parent_container();check(inv.container_id=="inventory" and inv.pending,"Read-only parent navigation does not unlock mutation")
	inv.queue_free();inv_detail.queue_free()
	var host:=Host.new();root.add_child(host)
	var body:=CharacterBody3D.new();host.add_child(body);body.position=Vector3(3,2,5)
	var controller:=preload("res://vehicles/controller.gd").new();host.add_child(controller);controller.app=host;controller.body=body;controller.set_process(false);controller.set_physics_process(false)
	host.reply={"ok":true,"state":{"source_kind":"core3_vehicles","character_id":"fixture","vehicles":[],"datapad":[],"seat":{}},"mutation":{"pending":true}}
	await controller.request("call",{"device_id":"owned-device"})
	check(host.calls.size()==1 and host.calls[0].path=="/vehicles/call" and Vector3(host.calls[0].payload.position[0],host.calls[0].payload.position[1],host.calls[0].payload.position[2]).is_equal_approx(Vector3(103,2,195)),"Normal noncombat call sends actual source position")
	check(not host.calls[0].payload.has("live_session_id") and controller.pending_call_until>Time.get_ticks_msec()/1000.0,"Native delayed call is polled without fabricated live session")
	host.background_allowed=false;controller._process(1.0)
	check(host.calls.size()==1 and controller.poll_in<=0,"Denied shared background budget preserves pending poll for fair retry")
	host.background_allowed=true;controller._process(0.01)
	await process_frame;await process_frame
	check(host.calls.size()==2 and host.calls[1].path=="/vehicles/status","Pending original call schedules authoritative status poll")
	host.calls.clear();host.ensure_ok=false
	await controller.call_vehicle({"id":"owned-device"})
	check(host.calls.is_empty() and controller.status.contains("connected gameplay"),"Failed persistent session prevents transient call and reports reconnect requirement")
	host.ensure_ok=true
	await controller.call_vehicle({"id":"owned-device"})
	check(host.calls.size()==1 and host.calls[0].payload.get("live_session_id","")=="native-gameplay-fixture" and host.ensure_calls==2,"Call awaits persistent gameplay session before native mutation")
	await controller.call_vehicle({"id":"owned-device"})
	check(host.ensure_calls==2,"Further calls reuse persistent native gameplay identity")
	check(preload("res://scripts/native_session_identity.gd").id(host)=="native-gameplay-fixture","Shared RPG requests explicitly carry persistent gameplay identity")
	host.live_combat=Session.new();host.add_child(host.live_combat);host.live_combat.session_id="combat-session"
	check(preload("res://scripts/native_session_identity.gd").id(host)=="combat-session","Existing live combat identity takes precedence during authority handover")
	host.queue_free();ui.queue_free();await process_frame;await process_frame
	print(JSON.stringify({"checks":checks,"failures":errors}));quit(0 if errors.is_empty() else 1)
