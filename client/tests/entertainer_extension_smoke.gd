extends SceneTree
## Production client controllers with mocked native replies and tracked poses.
const Gesture=preload("res://entertainment/register_location_gesture.gd")
const Fixture=preload("res://tests/entertainer_smoke.gd")
class Session extends Node:
	var live:=true
	var session_id:="native-fixture"
class Stage extends Node3D:
	var current_cell:Dictionary={"building_object_id":"77","cell_id":"77:2"}
class Body extends Fixture.ControlBody:
	var camera:Camera3D
	func get_camera()->Camera3D:return camera
class Host extends Node3D:
	var inventory:Node
	var datapad:Node
	var combat_rig:Node
	var tracked_avatar:Node
	var scout:Node
	var menu:Control
	var creator:Control
	var stage:Node3D
	var gameplay_session:Node
	var live_combat:Node
	var active_planet:="tatooine"
	var world_ready:=true
	var loading_stage:=false
	var xr_requested:=false
	var xr_focused:=true
	var datapad_account:="fixture"
	var datapad_character_id:="123"
	var calls:Array=[]
	var reply:Dictionary={}
	var appearance:Dictionary={}
	func apply_native_appearance(value:Dictionary)->void:appearance=value.duplicate(true)
	func source_position_at(point:Vector3)->Vector3:return Vector3(point.x+3500,point.y+5,-point.z-4800)
	func api(_method:HTTPClient.Method,path:String,payload:Dictionary={})->Dictionary:
		calls.append({"path":path,"payload":payload.duplicate(true)});await get_tree().process_frame;return reply.duplicate(true)
var failures:Array=[]
var checks:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);push_error(label)
func pose(x:float,y:float,z:=0.0)->Transform3D:return Transform3D(Basis.IDENTITY,Vector3(x,y,z))
func hold(gesture:RefCounted,seconds:float,tracked:=true,standing:=true,allowed:=true)->int:
	var count:=0
	for _i in range(roundi(seconds*90)):
		if gesture.sample(1.0/90,pose(0,1.7),pose(-.55,2.1),pose(.55,2.1),tracked,standing,allowed):count+=1
	return count
func reply(revision:int)->Dictionary:
	return {"ok":true,"source_kind":"core3_entertainer","character_id":"123","sequence":revision,"state":{"zone":"tatooine","skills":["social_entertainer_novice","social_dancer_novice"],"commands":["startdance+basic"],"flourishes":[1],"registration":{"eligible":true,"registered":false},"registrations":[],"nearby_players":[{"id":"123","name":"Self"}]},"mutation":{"success":true}}
func _initialize()->void:call_deferred("run")
func run()->void:
	var gesture:=Gesture.new()
	check(hold(gesture,9.9)==0 and gesture.progress>.98,"Registration requires the full continuous ten seconds")
	check(hold(gesture,.1)==1 and hold(gesture,15)==0,"A sustained completed pose fires exactly once")
	hold(gesture,.1,false);check(hold(gesture,11)==0,"Tracking loss cannot rearm a completed held pose")
	gesture.sample(.01,pose(0,1.7),pose(-.2,1.2),pose(.2,1.2),true,true,true)
	check(hold(gesture,10)==1,"Observed lowered arms rearm the next deliberate hold")
	gesture.reset();hold(gesture,9);hold(gesture,.1,false)
	check(hold(gesture,9)==0 and hold(gesture,1)==1,"Tracking interruption resets partial progress")
	for gate in ["standing","allowed"]:
		gesture.reset();hold(gesture,9);hold(gesture,.1,true,gate!="standing",gate!="allowed")
		check(hold(gesture,9)==0,"Crouch or UI/focus gate cancels partial hold: "+gate)
	gesture.reset();hold(gesture,9);gesture.sample(.2,pose(0,1.7),pose(-.55,2.1),pose(.55,2.1),true,true,true)
	check(hold(gesture,9)==0,"A long tracking/frame gap cannot complete registration")
	check(not gesture.raised_pose(pose(0,1.7),pose(-.15,2.1),pose(.15,2.1)),"Hands close together are not a wide V")
	check(not gesture.raised_pose(pose(0,1.7),pose(-.55,1.3),pose(.55,1.3)),"Shoulder-height arms are not a raised V")
	var rotation:=Transform3D(Basis(Vector3.UP,1.1),Vector3(14,0,-30))
	check(gesture.raised_pose(rotation*pose(0,1.7),rotation*pose(-.55,2.1),rotation*pose(.55,2.1)),"World translation and locomotion yaw do not alter V geometry")
	var host:=Host.new();root.add_child(host);host.stage=Stage.new();host.add_child(host.stage);host.stage.set_meta("manifest",{"origin":[3500,5,-4800]})
	host.gameplay_session=Session.new();host.add_child(host.gameplay_session)
	var body:=Body.new();host.add_child(body);body.camera=Camera3D.new();body.add_child(body.camera);body.feedback=Fixture.GroundedFeedback.new();body.feedback.configure(body,body.camera)
	var performer:=preload("res://entertainment/controller.gd").new();host.add_child(performer);performer.set_process(false);performer.set_physics_process(false);performer.native.set_process(false);performer.native.set_physics_process(false)
	performer.configure(host,body,null,{"token":"fixture","context":{}},"fixture")
	var native:Node=performer.native
	check(native.accept(reply(1)),"Current owned native state supplies entertainer permissions")
	performer.item={}
	check(performer.assets.performances(performer.context,performer.item).size()==1,"Only the native learned dance is selectable")
	var learned:=reply(2);learned.state.commands.append("startdance+rhythmic");learned.state.flourishes=[1,2,3]
	check(native.accept(learned) and performer.context.flourishes==[1,2,3] and performer.assets.performances(performer.context,performer.item).size()==2,"Learned dances and random flourish pool refresh without relogging")
	check(not native.accept(reply(1)) and performer.context.flourishes==[1,2,3],"Stale native reply cannot revoke or overwrite newer grants")
	var foreign:=reply(10);foreign.character_id="other"
	check(not native.accept(foreign),"Another character cannot grant image or performer abilities")
	performer.selected={"id":"dance:rhythmic:dance"};performer.primed=true
	check(native.accept(reply(3)) and performer.selected.is_empty() and not performer.primed,"Revoked selection is disarmed immediately")
	host.reply=reply(4)
	await native.request("flourish")
	check(host.calls.back().path=="/entertainer/flourish" and not host.calls.back().payload.has("index"),"Existing trigger delegates random learned flourish choice to CoreCU")
	check(host.calls.back().payload.position==[3500.0,5.0,-4800.0] and host.calls.back().payload.live_session_id=="native-fixture" and host.calls.back().payload.cell_index==2,"Native actions preserve owned session and source location/cell")
	var before:int=host.calls.size();host.menu=Control.new();host.add_child(host.menu)
	for i in range(1000):native.sample_registration(1.0/90,pose(0,1.7),pose(-.55,2.1),pose(.55,2.1),true,true)
	check(host.calls.size()==before and native.gesture.progress==0,"Production menu gate cannot register through an open menu")
	host.menu.hide();native.age=0
	for i in range(900):native.sample_registration(1.0/90,pose(0,1.7),pose(-.55,2.1),pose(.55,2.1),true,true)
	await process_frame;await process_frame
	check(host.calls.size()==before+1 and host.calls.back().path=="/entertainer/register_location","Production completed hold requests native registration once")
	var panel:=preload("res://entertainment/image_design_panel.gd").new();root.add_child(panel)
	var state:Dictionary={"session_id":"777","revision":7,"role":"designer","can_accept":true,"draft":{"attributes":{},"price":25},"options":{"controls":[{"id":"shape","label":"Face shape","type":"shape","min":0,"max":1}],"hair":[{"template":"source/hair.iff","label":"Learned hair"}],"holoemotes":["sparks"],"allow_bald":true}}
	panel.apply_design(state)
	var actions:Array=[];panel.action_requested.connect(func(action,payload):actions.append({"action":action,"payload":payload}))
	panel.click_at(Vector2(100,128+3*44+20));panel.pointer_begin(panel.slider.position+Vector2(500,42));panel.pointer_end(panel.slider.position+Vector2(500,42))
	panel.click_at(panel.CONFIRM_RECT.get_center())
	check(actions.size()==1 and actions[0].action=="image_propose" and actions[0].payload.revision==7 and float(actions[0].payload.draft.attributes.shape)>.8,"Finger-drag source control sends a revision-bound proposal, never commits appearance")
	state.revision=8;state.draft=actions[0].payload.draft;state.role="recipient";panel.apply_design(state);actions.clear();panel.click_at(panel.CONFIRM_RECT.get_center())
	check(actions.size()==1 and actions[0].action=="image_accept" and actions[0].payload.revision==8,"Recipient explicitly accepts the exact price/appearance revision")
	state.revision=9;state.can_accept=false;panel.apply_design(state);actions.clear();panel.click_at(panel.CONFIRM_RECT.get_center())
	check(actions.is_empty(),"Unavailable or already submitted consent cannot emit another acceptance")
	state.role="designer";state.revision=10;state.options.controls=[]
	for i in range(12):state.options.controls.append({"id":"shape%d"%i,"label":"Shape %d"%i,"type":"shape","min":0,"max":1})
	panel.apply_design(state);panel.pointer_begin(Vector2(100,330));panel.pointer_move(Vector2(100,-330));panel.pointer_end(Vector2(100,-330))
	check(panel.offset==10,"Finger drag reaches every source control, including the final five-row page")
	panel.draft.attributes["shape11"]=.8;state.options.controls=[];panel.apply_design(state)
	check(not panel.draft.attributes.has("shape11") and panel.rows.size()==3,"Changed native permissions discard stale unsubmitted options")
	var offer:=reply(20);offer.state.skills=[];offer.state.commands=[];offer.state.flourishes=[]
	offer.state.image_design={"active":true,"session_id":"777","revision":1,"role":"recipient","can_accept":true,"draft":{"attributes":{},"price":25},"options":{}}
	offer.state.appearance={"source":"core3_image_design","race":"human_male"}
	check(native.accept(offer) and native.design_ui.terminal.get("id","")=="777" and not performer.context.entertainer,"A non-entertainer receives the native consent interface")
	check(host.appearance==offer.state.appearance,"Confirmed native appearance reaches the host refresh hook")
	var inactive:=reply(21);inactive.state.image_design={"active":false};native.accept(inactive)
	check(native.design_ui.terminal.is_empty(),"Inactive native image sessions close the consent interface")
	var invite:=reply(22);invite.state.skills=[];invite.state.commands=[];invite.state.group_inviter_id="456";invite.state.group_inviter_name="Designer";native.accept(invite)
	check(performer.owns_controls() and performer.eligible_menu().any(func(row):return row.id=="group_join"),"Ungrouped non-entertainers can accept the native group invitation")
	var map_ui:=preload("res://scripts/datapad_ui.gd").new();root.add_child(map_ui)
	map_ui.set_registered_locations([{"building_id":"77","registered":true,"zone":"tatooine","position":[3500,5,-4800],"name":"Cantina","category":"cantina"},{"building_id":"88","registered":true,"zone":"naboo","position":[0,0,0]}])
	check(map_ui.map.registered_locations.size()==1 and map_ui.map.registered_locations[0].id=="77","Planetary map accepts only current-zone native registered venues")
	map_ui.set_registered_locations([]);check(map_ui.map.registered_locations.is_empty(),"Native venue removal clears its map marker")
	map_ui.free()
	panel.free();host.free();await process_frame
	var report:Dictionary={"passed":failures.is_empty(),"checks":checks,"failures":failures,"native":"mocked owned envelopes","tracking":"mocked","renderer":"dummy","live_xr":false}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://../runtime/evidence/entertainment"));FileAccess.open("res://../runtime/evidence/entertainment/extensions-client.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "));print(JSON.stringify(report));quit(0 if failures.is_empty() else 1)
