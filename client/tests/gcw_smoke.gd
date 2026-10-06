extends SceneTree
var checks:=0
var failures:Array=[]
func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures.append(label);push_error(label)
func hold(gesture:RefCounted,seconds:float,id:String="42",head:=Transform3D.IDENTITY,hand:=Vector3(.23,.04,-.05),right:=true,open:=true,tracked:=true,allowed:=true)->Array:
	var events:Array=[]
	for i in range(roundi(seconds*90)):
		var value:Dictionary=gesture.sample(1.0/90,id,head,head*hand,right,open,tracked,allowed)
		if not str(value.action).is_empty():events.append(value.action)
	return events
func _initialize()->void:call_deferred("run")
func run()->void:
	var gesture:=SwgSaluteGesture.new()
	check(hold(gesture,.8).is_empty(),"Brief hand movement near temple cannot toggle duty")
	check(hold(gesture,.3).size()==1 and hold(gesture,2).is_empty(),"Continuous one-second salute fires once per hold")
	hold(gesture,.2,"42",Transform3D.IDENTITY,Vector3(.23,.04,-.05),true,true,false)
	check(hold(gesture,2).is_empty(),"Tracking loss cannot rearm a completed salute")
	hold(gesture,.1,"42",Transform3D.IDENTITY,Vector3(.23,-.4,-.05))
	check(hold(gesture,1.1).size()==1,"Lowering hand rearms deliberate next salute")
	gesture.reset();hold(gesture,.6);hold(gesture,.1,"other");check(hold(gesture,.5).is_empty(),"Changing recruiter resets partial hold")
	gesture.reset();check(hold(gesture,2,"42",Transform3D.IDENTITY,Vector3(.0,.08,-.20)).is_empty(),"Center-brow Ranger shade pose is not a salute")
	gesture.reset();check(hold(gesture,2,"42",Transform3D.IDENTITY,Vector3(.23,.04,-.05),true,false).is_empty(),"Closed fist or held controller trigger cannot salute")
	gesture.reset();check(hold(gesture,2,"42",Transform3D.IDENTITY,Vector3(.23,.04,-.05),false).is_empty() and hold(gesture,1.1,"42",Transform3D.IDENTITY,Vector3(-.23,.04,-.05),false).size()==1,"Salute temple follows chosen dominant hand")
	gesture.reset();var fired:=false
	for i in range(200):
		var head:=Transform3D(Basis(Vector3.UP,float(i)*.01),Vector3(3,1.7,2));var result:Dictionary=gesture.sample(1.0/90,"42",head,head*Vector3(.23,.04,-.05),true,true,true,true);fired=fired or not str(result.action).is_empty()
	check(not fired,"Ranger-style head sweep cannot finish steady salute")
	gesture.reset();hold(gesture,.6);hold(gesture,.1,"42",Transform3D.IDENTITY,Vector3(.23,.04,-.05),true,true,true,false);check(hold(gesture,.5).is_empty(),"Menu or gameplay gate interruption resets partial salute")
	check(str(gesture.sample(NAN,"42",Transform3D.IDENTITY,Vector3.ZERO,true,true,true,true).action).is_empty(),"Nonfinite frame timing fails closed")
	var singular:=Transform3D(Basis(Vector3.ZERO,Vector3.ZERO,Vector3.ZERO),Vector3.ZERO)
	check(str(gesture.sample(.01,"42",singular,Vector3.ZERO,true,true,true,true).action).is_empty(),"Singular tracked head basis is rejected safely")
	var panel:=preload("res://gcw/panel.gd").new();root.add_child(panel)
	var reward:Dictionary={"id":"imperial:armor:bicep","name":"Stormtrooper armor","description":"Original faction uniform piece.","template":"object/tangible/wearables/armor/stormtrooper/armor_stormtrooper_bicep_l.iff","cost_faction_points":1000,"eligible":true}
	var record:Dictionary={"id":"42","kind":"recruiter","name":"Imperial recruiter","faction":"imperial","status":0,"gcw":{"status_name":"neutral"},"can_join":true,"recruiter_text":"Enlist or inspect our faction rewards.","rewards":[reward]}
	for i in range(12):var row:=reward.duplicate();row.id="reward-%d"%i;row.name="Reward %d"%i;record.rewards.append(row)
	panel.configure(record,{"cash":1000,"bank":0});var actions:Array=[];panel.action_requested.connect(func(action,detail):actions.append({"action":action,"detail":detail}))
	panel.click_at(Vector2(100,194));check(actions.is_empty() and panel.selected==1 and panel.preview_ready and panel.reward_preview.models.get_child_count()==1,"Selecting reward loads its original3D model without purchasing")
	var mesh:Node=panel.reward_preview.models.get_child(0).get_child(0)
	panel.refresh_details();check(panel.reward_preview.models.get_child(0).get_child(0)==mesh,"Unchanged reward preview reuses original mesh instance")
	panel.click_at(panel.CONFIRM_RECT.get_center());check(actions.size()==1 and actions[0].action=="recruiter_purchase" and actions[0].detail.reward_id==reward.id,"Separate confirmation submits exact native reward ID")
	panel.click_at(panel.CONFIRM_RECT.get_center());check(actions.size()==1,"Pending purchase cannot be repeated by held trigger")
	panel.set_pending(false);panel.navigate_at(Vector2(100,194),10);check(panel.selected==11 and panel.offset>=4 and panel.preview_ready,"Joystick navigation scrolls long native reward list and refreshes side preview")
	panel.click_at(panel.REFRESH_RECT.get_center());check(actions.back().action=="open" and actions.back().detail.terminal_id=="42","Refresh retains native recruiter identity")
	panel.configure(record,{});panel.set_pending(false);panel.offset=0;panel.click_at(Vector2(100,145));panel.confirm();check(actions.back().action=="recruiter_join","Enlistment requires explicit confirm on selected native option")
	var denied:=record.duplicate(true);denied.rewards[0].eligible=false;denied.rewards[0].reason="Insufficient native standing";panel.configure(denied,{});panel.set_pending(false);panel.click_at(Vector2(100,194));var before:=actions.size();panel.confirm();check(actions.size()==before and panel.message.contains("standing"),"Native blocked reward never sends purchase")
	denied=record.duplicate(true);denied.rewards[0].template="object/missing_original.iff";panel.configure(denied,{});panel.set_pending(false);panel.click_at(Vector2(100,194));panel.confirm();check(actions.size()==before and not panel.preview_ready,"Missing original preview cannot silently purchase unseen reward")
	var promoted:=record.duplicate(true);promoted.rank=0;promoted.rank_name="Private";promoted.next_rank_name="Lance corporal";promoted.promotion_cost_faction_points=200;promoted.can_promote=true;panel.configure(promoted,{});panel.set_pending(false);panel.offset=0;panel.click_at(Vector2(100,194));before=actions.size();check(panel.info.text.contains("200 faction points") and actions.size()==before,"Promotion displays native rank/cost before explicit confirmation");panel.confirm();check(actions.back().action=="recruiter_promote" and actions.back().detail.expected_rank==0,"Promotion request fences exact displayed native rank");promoted.can_promote=false;promoted.promotion_reason="Standing reserve required";panel.configure(promoted,{});panel.set_pending(false);before=actions.size();panel.confirm();check(actions.size()==before and panel.message.contains("reserve"),"Native blocked promotion does not submit request")
	panel.configure({"id":"scan:77","kind":"contraband","scan":{"id":"77","fine":500,"answer_pending":true}},{"cash":1000,"bank":0});before=actions.size();check(actions.size()==before,"Native fine prompt does not pay automatically")
	panel.click_at(panel.REFRESH_RECT.get_center());check(actions.back().action=="contraband_answer" and actions.back().detail.scan_id=="77" and actions.back().detail.accept,"Pay submits explicit answer tied to current native scan")
	panel.set_pending(false);panel.click_at(panel.CONFIRM_RECT.get_center());check(not actions.back().detail.accept and actions.back().detail.scan_id=="77","Refusal uses same native scan callback without local penalty mutation")
	var long_record:=record.duplicate(true);long_record.rewards[0].description="Original armor details. ".repeat(60);long_record.rewards[0].eligible=false;long_record.rewards[0].reason="Faction membership required.";panel.configure(long_record,{});panel.set_pending(false);panel.offset=0;panel.click_at(Vector2(100,194));await process_frame;await process_frame;var previous_selection:=panel.selected;panel.navigate_at(panel.info.position+Vector2(20,20),3);check(panel.info.get_v_scroll_bar().value>0 and panel.selected==previous_selection,"Pointed side information scrolls long original description without changing reward");check(panel.info.text.find("Faction membership required")<panel.info.text.find("Original armor details"),"Native blocked reason precedes long original reward description")
	panel.interface_closed();check(panel.reward_preview.render_target_update_mode==SubViewport.UPDATE_DISABLED,"Closing terminal suspends reward3D rendering")
	panel.configure({"id":"trainer","kind":"trainer","skills":[]},{});check(panel.rows.is_empty() and not panel.info.visible and not panel.preview_image.visible,"Existing trainer mode remains the shared service panel")
	panel.configure({"id":"missions","kind":"mission","missions":[]},{});var mission:Dictionary={"name":"Destroy enemy outpost","reward":750,"faction":"rebel","faction_points":{"rebel":15,"imperial":-7}};var details:=panel.detail_for(mission);check(details.contains("Reward: 750") and details.contains("Rebel standing: +15") and details.contains("Imperial standing: -7"),"Faction mission shows actual native standing gain and penalty alongside credits");mission.faction_points={"rebel":0,"imperial":0};check(not panel.detail_for(mission).contains("standing:"),"Zero standing fields do not add noise to ordinary mission layout");mission.erase("faction_points");check(not panel.detail_for(mission).contains("standing:"),"Legacy ordinary missions retain existing details without invented standing")
	panel.free();await process_frame
	var report:Dictionary={"passed":failures.is_empty(),"checks":checks,"failures":failures,"native_gesture":true,"native_api":"mocked","original_reward_preview":true,"renderer":"dummy","live_xr":false};FileAccess.open("res://../runtime/evidence/gcw-client.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "));print(JSON.stringify(report));quit(0 if failures.is_empty() else 1)
