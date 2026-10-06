extends SceneTree
## Read-only replay of saved native packets through production scout/UI consumers.
const Fixture=preload("res://tests/ranger_inventory_integration.gd")
var checks:=0
var failures:Array=[]
func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures.append(label);push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	var evidence:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/evidence/ranger-native.json"))
	if not evidence.get("passed",false):push_error("Final passing native Ranger recording required");quit(2);return
	var host:=Fixture.Host.new();root.add_child(host);host.world_ready=true;host.loading_stage=false;host.xr_requested=false;host.datapad_account="recording"
	var rig:XROrigin3D=load("res://xr/player_rig.tscn").instantiate();host.add_child(rig);host.player=rig.get_node("PlayerBody");host.player.active=true;host.player.set_physics_process(false)
	var bag:=preload("res://scripts/xr_inventory.gd").new();host.add_child(bag);host.inventory=bag;bag.configure(rig,host.player);bag.set_process(false);bag.set_allowed(true)
	host.inventory_snapshot={"source_kind":"core3_inventory","items":[],"equipment":[]}
	var scout:=preload("res://scout/controller.gd").new();host.add_child(scout);host.scout=scout;scout.setup(host,bag);scout.set_process(false);scout.ranger.set_process(false);scout.ranger.set_physics_process(false)
	var observed:Dictionary={"conceal":false,"zero_skill_conceal":false,"pending":false,"results":false,"rescue":false}
	var records:=0;var best:Dictionary={};var score:=-1;var kit:=""
	check(evidence.get("responses",[]).size()<=1024,"Native recording remains within bounded replay budget")
	for row:Dictionary in evidence.get("responses",[]).slice(0,1024):
		if not str(row.get("path","")).begins_with("/scout/"):continue
		var response:Dictionary=row.get("response",{})
		var native:Dictionary=response.get("state",{})
		var character:=str(native.get("character_id",row.get("owner","")))
		if character!=host.datapad_character_id:
			host.datapad_epoch+=1;host.datapad_character_id=character;scout.reset();host.inventory_snapshot={"source_kind":"core3_inventory","items":[],"equipment":[]}
		host.reply=response.duplicate(true);host.reply.ok=not native.is_empty();host.reply.http_status=200 if host.reply.ok else 400
		var before:Dictionary=host.inventory_snapshot.duplicate(true)
		await scout.request(str(row.path).get_file());records+=1
		if native.is_empty():
			check(before==host.inventory_snapshot and not scout.ranger.message.is_empty(),"Recorded native rejection preserves inventory and reports the error")
			continue
		check(scout.ranger.state==native.get("ranger",{}),"Recorded native grants and Ranger state reach the production consumer")
		check(host.inventory_snapshot.get("items",[])==native.get("inventory",{}).get("items",[]),"Native inventory/charge snapshot is reconciled without local consumption")
		for item:Dictionary in host.inventory_snapshot.get("items",[]):
			if preload("res://scout/ranger_input.gd").is_kit(item):kit=str(item.template);break
		var ranger:Dictionary=scout.ranger.state;var tracking:Dictionary=ranger.get("tracking",{});scout.ranger.panel.panel.apply(ranger)
		var mutation:Dictionary=response.get("mutation",{})
		if mutation.get("action","")=="conceal":
			observed.conceal=true;check(int(mutation.get("charges_consumed",0))==1,"Actual native kit receipt reports one charge consumed")
			if int(ranger.get("camouflage",-1))==0:
				observed.zero_skill_conceal=true;check(mutation.get("conceal",{}).get("active",false) and int(mutation.conceal.power)>0,"Actual zero-skill profession receives nonzero native camouflage")
		if mutation.get("action","")=="rescue":
			observed.rescue=true
			check(scout.ranger.message.contains("succeeded") if mutation.get("rescued",false) else scout.ranger.message.contains("failed"),"Actual Rescue outcome controls success/failure wording")
		if tracking.get("state","")=="pending":
			observed.pending=true;check(scout.ranger.panel.panel.pending and scout.ranger.panel.panel.notice().contains("six seconds"),"Real pending native search preserves six-second stillness instruction")
		if tracking.get("state","")=="failed":check(not scout.ranger.panel.panel.notice().contains("No tracks"),"Native interruption cannot appear as a successful empty result")
		if tracking.get("state","")=="succeeded" and tracking.has("total_results"):
			check(int(tracking.total_results)>=tracking.get("results",[]).size(),"Native qualified count bounds returned source results")
			if tracking.get("truncated",false):check(scout.ranger.panel.panel.notice().contains("of %d"%int(tracking.total_results)),"Actual native truncated count reaches the tracking notice")
		if tracking.get("state","")=="succeeded" and not tracking.get("results",[]).is_empty():
			observed.results=true;var richness:int=tracking.results.size()+10000*int(tracking.has("total_results"))
			for track:Dictionary in tracking.results:
				check(not track.has("position") and not track.has("id"),"Original tracking results expose no exact coordinates or identities")
				richness+=int(track.has("direction"))+int(track.has("distance"))
			if richness>score:score=richness;best=ranger.duplicate(true)
	for field in observed:check(observed[field],"Actual recorded coverage present: "+field)
	check(not best.is_empty() and not kit.is_empty(),"Native results and owned original kit are ready for desktop capture")
	FileAccess.open("res://../runtime/evidence/ranger-preview.json",FileAccess.WRITE).store_string(JSON.stringify({"ranger":best,"kit_template":kit,"source":"recorded real native Ranger state"},"  "))
	host.free();await process_frame
	var report:Dictionary={"passed":failures.is_empty(),"checks":checks,"failures":failures,"records":records,"source":"recorded real native Ranger state","native_requests_sent":0,"renderer":"dummy","live_xr":false};FileAccess.open("res://../runtime/evidence/ranger-native-replay.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "));print(JSON.stringify(report));quit(0 if failures.is_empty() else 1)
