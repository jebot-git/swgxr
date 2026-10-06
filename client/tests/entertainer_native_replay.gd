extends SceneTree
## Recorded real Core3 replies through the production client authority/UI path.
const Fixture=preload("res://tests/entertainer_extension_smoke.gd")
class Host extends Fixture.Host:
	var vehicles:Node
var failures:Array=[]
var checks:=0
func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures.append(label);push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	var evidence:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/evidence/image-design-native.json"))
	var replayed:=0
	for row in evidence.responses:
		var reply:Dictionary=row.response
		if reply.get("source_kind","")!="core3_entertainer" or not reply.has("live_response"):continue
		var host:=Host.new();root.add_child(host);host.datapad_character_id=str(reply.character_id);host.stage=Fixture.Stage.new();host.add_child(host.stage)
		host.stage.set_meta("manifest",{"origin":[3500,5,-4800]})
		var body:=Fixture.Body.new();host.add_child(body);body.camera=Camera3D.new();body.add_child(body.camera);body.feedback=Fixture.Fixture.GroundedFeedback.new();body.feedback.configure(body,body.camera)
		var session:=preload("res://scripts/gameplay_session.gd").new();host.add_child(session);host.gameplay_session=session;session.setup(host);session.set_process(false);session.live=true;session.session_id=str(reply.live_response.session_id)
		var performer:=preload("res://entertainment/controller.gd").new();host.add_child(performer);performer.set_process(false);performer.set_physics_process(false);performer.native.set_process(false);performer.native.set_physics_process(false)
		performer.configure(host,body,null,{"context":{},"token":""},"fixture")
		check(performer.native.accept(reply),"Recorded native reply accepted: "+row.path)
		check(session.sequence==int(reply.sequence) and not session.player_state.is_empty(),"Real gameplay authority observes same native sequence")
		var design:Dictionary=reply.state.get("image_design",{})
		if design.get("active",false):
			check(performer.native.design_ui.terminal.get("id","")==str(design.session_id),"Active native image session opens production consent surface")
			var panel=performer.native.design_ui.panel
			check(panel.preview_avatar.report.get("error","").is_empty() and panel.preview_avatar.report.get("bones",0)>0,"Actual native appearance renders original avatar skeleton")
			replayed+=1
		var corrupt:Dictionary=reply.duplicate(true);corrupt.sequence=int(reply.sequence)+1;corrupt.live_response.session_id="foreign"
		check(not performer.native.accept(corrupt),"Foreign owned-session payload rejected before grants/appearance")
		host.free();await process_frame
	check(replayed>0,"Actual native image sessions were replayed")
	var report:Dictionary={"passed":failures.is_empty(),"checks":checks,"failures":failures,"active_designs":replayed,"source":"recorded real Core3 image-design replies","live_xr":false,"renderer":"dummy"}
	FileAccess.open("res://../runtime/evidence/entertainment/native-client-replay.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "));print(JSON.stringify(report));quit(0 if failures.is_empty() else 1)
