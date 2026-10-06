extends SceneTree
const Fixture=preload("res://tests/ranger_inventory_integration.gd")
var checks:=0
var failures:Array=[]
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	var source:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/evidence/gcw-native.json"))
	if not source.get("passed",false):push_error("Complete passing native evidence is required");quit(2);return
	var host:=Fixture.Host.new();root.add_child(host);host.world_ready=true;host.xr_requested=true;host.xr_focused=true
	var rig:XROrigin3D=load("res://xr/player_rig.tscn").instantiate();host.add_child(rig);host.xr_origin=rig;host.player=rig.get_node("PlayerBody");host.player.set_physics_process(false);rig.get_node("XRCamera3D").position=Vector3(0,1.7,0)
	var services:=preload("res://scripts/services_controller.gd").new();host.add_child(services);host.services=services;services.app=host;services.set_process(false)
	services.ui=preload("res://scripts/xr_services.gd").new();services.add_child(services.ui);services.ui.configure(rig,host.player,"left");services.ui.set_process(false)
	services.gcw=preload("res://gcw/controller.gd").new();services.add_child(services.gcw);services.gcw.setup(services);services.gcw.set_physics_process(false)
	var packets:=0;var queued:=0;var fines:=0;var recruiter:=0;var promotions:=0;var actions:Array=[];services.ui.panel.action_requested.connect(func(action,detail):actions.append({"action":action,"detail":detail.duplicate(true)}))
	var preview:Dictionary={}
	for row:Dictionary in source.get("responses",[]):
		var result:Dictionary=row.get("response",{});var state:Dictionary=result.get("state",{})
		if result.get("source_kind","")!="core3_services" or not result.get("ok",false) or state.is_empty():continue
		var identity:=str(result.get("character_id",""))
		if identity!=host.datapad_character_id:services.gcw.reset();services.ui.close_interface();host.datapad_character_id=identity
		services.set_allowed(true)
		check(services.accept_response(result),"Actual native services envelope accepted: "+str(row.get("path","")));packets+=1
		check(services.state.gcw==state.get("gcw",{}),"Client preserves recorded native faction, queued duty, scan and standing authority")
		if state.get("gcw",{}).get("changing",false):
			queued+=1;check(services.gcw.pending_text().contains("in about") or services.gcw.pending_text().contains("Awaiting native"),"Recorded pending duty remains a queued timer")
		var scan:Dictionary=state.get("gcw",{}).get("scan",{})
		if scan.get("active",false) and scan.get("answer_pending",false):
			fines+=1;check(services.ui.terminal.get("scan",{}).get("id","")==str(scan.id),"Actual native fine is tied to correct local scan prompt")
		var terminal:Dictionary=state.get("terminal",{})
		if terminal.get("kind","")!="recruiter":continue
		recruiter+=1;terminal=terminal.duplicate(true);terminal.gcw=state.get("gcw",{});services.ui.panel.configure(terminal,state.get("wallet",{}));services.ui.panel.set_pending(false)
		check(services.ui.panel.rows.size()==terminal.get("rewards",[]).size()+1+(1 if terminal.has("rank") else 0),"Every original reward and native promotion appears in recruiter list")
		for i in range(services.ui.panel.rows.size()):
			var item:Dictionary=services.ui.panel.rows[i]
			if item.get("kind")=="promotion" and item.get("eligible",false):
				services.ui.panel.selected=i;services.ui.panel.refresh_details();services.ui.panel.confirm();check(actions.back().action=="recruiter_promote" and actions.back().detail.expected_rank==int(terminal.rank),"Actual native eligible promotion emits expected rank fence");promotions+=1;services.ui.panel.set_pending(false)
			if item.get("kind")=="reward" and preview.is_empty():
				services.ui.panel.selected=i;services.ui.panel.refresh_details();check(services.ui.panel.preview_ready,"Recorded original reward resolves genuine3D preview");preview={"terminal":terminal,"selected_reward":str(item.id)}
	check(packets>10 and recruiter>0 and queued>0,"Native replay covers real recruiter and asynchronous duty states")
	check(fines>0,"Native recording covers original contraband answer prompt")
	check(promotions>0,"Native recording covers earnable original rank progression")
	check(host.calls.is_empty(),"Saved native replay performs no live server requests")
	if not preview.is_empty():FileAccess.open("res://../runtime/evidence/gcw-native-preview.json",FileAccess.WRITE).store_string(JSON.stringify(preview,"  "))
	host.free();await process_frame
	var report:Dictionary={"passed":failures.is_empty(),"checks":checks,"failures":failures,"native_packets":packets,"recruiter_views":recruiter,"queued_states":queued,"fine_states":fines,"native_evidence":"gcw-native.json","renderer":"dummy","live_xr":false};FileAccess.open("res://../runtime/evidence/gcw-native-replay.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "));print(JSON.stringify(report));quit(0 if failures.is_empty() else 1)
