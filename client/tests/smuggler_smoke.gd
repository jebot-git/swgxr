extends SceneTree
const Feign=preload("res://smuggler/feign_pose.gd")
const Feedback=preload("res://combat/player_feedback.gd")
const Abilities=preload("res://combat/ability_state.gd")
const ServicePanel=preload("res://scripts/service_panel.gd")
var checks:=0
var errors:Array=[]
func check(value:bool,label:String)->void:
	checks+=1
	if not value:errors.append(label);push_error(label)
func _initialize()->void:call_deferred("run")
func hold(pose:RefCounted,height:float,angle:float,tracked:=true)->Dictionary:
	var value:Dictionary={}
	for i in range(6):value=pose.sample({"eye_height":height,"tracked":tracked,"grounded":true},Basis(Vector3.RIGHT,deg_to_rad(angle)),1.7,0.1)
	return value
func run()->void:
	var pose:=Feign.new()
	check(not hold(pose,1.7,45).feign,"Ordinary upward gaze does not trigger feign")
	check(not pose.sample({"tracked":true,"grounded":true,"eye_height":1.7},Basis(Vector3.RIGHT,deg_to_rad(80)),1.7,0.1).feign,"Brief backward tilt is debounced")
	check(hold(pose,1.7,80).feign,"Sustained strong backward tilt requests Feign Death")
	check(not hold(pose,1.7,80,false).tracked,"Lost tracking cannot start or cancel authoritative feign")
	check(hold(pose,1.7,0).upright,"Standing upright with neutral head requests release")
	pose.reset()
	check(not hold(pose,.4,0).feign,"Low crouch with forward gaze is not supine")
	check(hold(pose,.4,55).feign,"Low supine upward-facing pose requests feign")
	check(not hold(pose,.8,0).upright,"Partial rise cannot prematurely leave feign")
	var feedback:=Feedback.new()
	feedback.observe({"character_id":"test","posture":13,"feigning_death":true})
	check(feedback.combat_blocked() and not feedback.life_locked,"Feign immobilizes without exposing actual incap recovery UI")
	check(feedback.animation_context().life_animation=="incapacitated" and feedback.animation_context().feigning_death,"Feign requests original incap clip with tracking-specific flag")
	feedback.observe({"character_id":"test","posture":0,"feigning_death":false})
	check(not feedback.combat_blocked(),"Only native standing snapshot unlocks movement")
	feedback.observe({"character_id":"test","posture":14,"feigning_death":true})
	check(feedback.life_locked and not feedback.feigning_death,"Deathblow supersedes feign and exposes native death flow")
	var native:=preload("res://scripts/gameplay_session.gd").new()
	var state:Dictionary={"ham":[900,800,700],"max_ham":[1000,1000,1000],"wounds":[0,0,0],"posture":13,"dead":false,"incapacitated":false,"feigning_death":true,"shock_wounds":0}
	check(native.valid_player(state),"Authoritative feign posture13 with incapacitated=false passes native snapshot validation")
	state.feigning_death=false
	check(not native.valid_player(state),"Unflagged posture13 cannot hide actual incapacitation")
	native.free()
	var abilities:=Abilities.new()
	abilities.apply_authoritative({"ham":[300,100,30],"max_ham":[1000,1000,1000],"wounds":[0,0,0]})
	var profile:Dictionary={"abilities":[{"id":"last_ditch","base_sac":{"health":0,"action":0,"mind":0},"cooldown_seconds":15.0}]}
	check(abilities.select(profile,"last_ditch") and abilities.toggle_prime(profile),"Last Ditch uses marksman preparation and arming")
	var shot:Dictionary={};abilities.apply_to_attack(shot,profile)
	check(abilities.ham[0]==300 and abilities.ham[3]==1 and abilities.ham[6]==1,"Last Ditch spends action and mind to one, leaves health unchanged")
	check(is_equal_approx(float(shot.ability.damage_multiplier),4.57),"30% health, 10% action and 3% mind produces requested 457% damage")
	var second:Dictionary={};abilities.apply_to_attack(second,profile)
	check(not second.has("ability"),"Last Ditch consumes prepared state exactly once")
	var panel:=ServicePanel.new();root.add_child(panel)
	var calls:Array=[];panel.action_requested.connect(func(action,payload):calls.append({"action":action,"payload":payload}))
	panel.target_id="200"
	panel.configure({"id":"200","kind":"payment","recipient_name":"Recipient"},{"cash":500,"bank":1000,"faction_delegation":true,"faction_points":{"imperial":2000,"rebel":1500},"faction_limits":{"imperial":700,"rebel":400},"delegation_ratio":1.5})
	check(panel.faction_sliders.imperial.visible and panel.faction_sliders.rebel.visible and panel.faction_sliders.imperial.maximum==700,"Wallet exposes separate native-limited Imperial and Rebel sliders")
	panel.faction_sliders.imperial.amount=123;panel.faction_sliders.rebel.amount=45
	panel.confirm()
	check(calls.size()==1 and calls[0].payload.amount==0 and calls[0].payload.faction_points=={"imperial":123,"rebel":45},"Zero-credit delegation submits both selected faction currencies once")
	panel.confirm();check(calls.size()==1,"Pending payment cannot be submitted twice")
	panel.configure({"id":"200","kind":"payment"},{"cash":500,"bank":1000,"faction_delegation":false})
	check(not panel.faction_sliders.imperial.visible and panel.faction_sliders.imperial.amount==0,"Lost native delegation privilege hides and clears proposals")
	panel.configure({"id":"301","kind":"underworld","dialogue":"Carry this parcel.","eligible":true,"confirm_action":"underworld_accept","front_money":500,"tier":1},{"cash":500})
	check(panel.delivery_dialogue.visible and panel.delivery_dialogue.text=="Carry this parcel.","Underworld broker reuses existing conversation window")
	panel.confirm();check(calls.back().action=="underworld_accept" and calls.back().payload.terminal_id=="301","Broker confirmation dispatches native Underworld acceptance")
	panel.free();await process_frame
	var report:Dictionary={"checks":checks,"errors":errors,"mocked_tracking":true,"dummy_renderer":true,"live_headset_validated":false}
	print(JSON.stringify(report));quit(0 if errors.is_empty() else 1)
