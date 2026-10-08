extends SceneTree
## Native failures simulated through the ordinary asynchronous session transport.
class Player extends CharacterBody3D:
	var feedback=preload("res://combat/player_feedback.gd").new()
class Host extends Node:
	var datapad_account:="fixture"
	var datapad_character_id:="123"
	var api_requests_in_flight:=0
	var world_ready:=true
	var session_leaving:=false
	var player:Player
	var stage:Node3D
	var vehicles:Node
	var medic:Node
	var asset_status:Label
	var calls:Array=[]
	var revision:=0
	var reject:=false
	var confirmed_feign:=false
	func source_position_at(p:Vector3)->Vector3:return p
	func envelope(kind:="core3_gameplay_session")->Dictionary:
		revision+=1
		return {"ok":true,"backend":"core3","source_kind":kind,"character_id":"123","session_id":"native","session_live":true,"sequence":revision,"snapshot":{"player":{"ham":[900,800,700],"max_ham":[1000,1000,1000],"wounds":[0,0,0],"posture":13 if confirmed_feign else 0,"dead":false,"incapacitated":false,"feigning_death":confirmed_feign,"feign_death_available":true,"shock_wounds":0}}}
	func api(method:HTTPClient.Method,path:String,payload:Dictionary={})->Dictionary:
		calls.append({"path":path,"payload":payload.duplicate(true)})
		await get_tree().process_frame
		if method==HTTPClient.METHOD_POST and reject:return {"ok":false,"error_code":"native_feign_rejected","error":"Core3 rejected the pose intent"}
		return envelope("core3_live_combat" if method==HTTPClient.METHOD_GET else "core3_gameplay_session")
var checks:=0
var errors:Array=[]
func check(value:bool,label:String)->void:
	checks+=1
	if not value:errors.append(label);push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	var app:=Host.new();root.add_child(app)
	app.player=Player.new();app.add_child(app.player);app.stage=Node3D.new();app.add_child(app.stage);app.asset_status=Label.new();app.add_child(app.asset_status)
	var session:=preload("res://scripts/gameplay_session.gd").new();app.add_child(session);session.setup(app);session.set_process(false)
	var abilities:=preload("res://combat/ability_state.gd").new()
	session.snapshot_applied.connect(func(state):
		var context:Dictionary=state.duplicate(true);context.character_id="123";app.player.feedback.observe(context);abilities.apply_authoritative(context))
	check(session.accept(app.envelope(),true),"Native initial state accepted")
	var profile:Dictionary={"abilities":[{"id":"last_ditch","activation":"native_ranged","base_sac":{"health":0,"action":0,"mind":0},"cooldown_seconds":15}]}
	check(abilities.select(profile,"last_ditch") and abilities.toggle_prime(profile),"Ranged ability starts armed")
	app.player.feedback.feign_pose.tracked=true;app.player.feedback.feign_pose.intent="feign"
	check(not app.player.feedback.combat_blocked(),"Physical feign intent cannot immobilize player before native confirmation")
	app.reject=true;await session.update_pose()
	check(session.live and not app.player.feedback.combat_blocked() and not session.busy,"Rejected feign start followed by native recovery snapshot remains unlocked and connected")
	check(abilities.primed,"Rejected feign cannot consume or silently unarm prepared ranged ability")
	app.reject=false;app.confirmed_feign=true;await session.update_pose()
	check(app.player.feedback.feigning_death and app.player.feedback.combat_blocked() and not app.player.feedback.life_locked,"Confirmed feign locks combat without actual incap recovery controls")
	app.player.feedback.feign_pose.intent="upright";app.reject=true;await session.update_pose()
	check(app.player.feedback.feigning_death and session.live and not session.busy,"Rejected upright release retains confirmed feign until authority changes")
	check(abilities.primed,"Feign start and failed release do not consume prepared ranged shot")
	app.reject=false;app.confirmed_feign=false;await session.update_pose()
	check(not app.player.feedback.combat_blocked() and session.last_smuggler_pose.upright,"Later confirmed upright release unlocks and acknowledges physical intent")
	app.free();await process_frame
	print(JSON.stringify({"checks":checks,"errors":errors,"mocked_native_failures":true,"headset_validated":false}));quit(0 if errors.is_empty() else 1)
