extends SceneTree
const Wrist=preload("res://scripts/xr_voice_controls.gd")
const Lifecycle=preload("res://scripts/voice_lifecycle.gd")
class Harness extends "res://scripts/main.gd":
	func _ready() -> void:pass
	func _process(_delta: float) -> void:pass
class Body extends CharacterBody3D:
	var feedback: Dictionary={"life_locked":false}
	var active:=false
class VoiceProbe extends Node:
	var contexts: Array=[]
	var allowed:=true
	var ptt:=false
	func set_context(account: String,character: String,revision: int,session_id: String="") -> void:contexts.append([account,character,revision,session_id])
	func set_allowed(value: bool) -> void:allowed=value
	func set_ptt(value: bool) -> void:ptt=value
var checks:=0
var failures: Array[String]=[]
func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures.append(message);push_error(message)
func frames() -> void:
	for _frame in range(3):await process_frame
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var rig:=XROrigin3D.new();root.add_child(rig)
	var wrist:=Wrist.new();root.add_child(wrist);wrist.configure(rig,"left");wrist.set_process(false)
	var modes: Array=[];var channels: Array=[];var ptt: Array=[]
	wrist.mode_requested.connect(func(mode):modes.append(mode))
	wrist.channel_requested.connect(func(channel):channels.append(channel))
	wrist.ptt_changed.connect(func(held):ptt.append(held))
	var state: Dictionary={"granted_channels":["proximity","planet"],"reasons":{"group":"Join a group to use group voice","faction":"Faction voice requires native membership"},"active_channel":"proximity","mic_mode":"muted","connected":true,"transmitting":false}
	wrist.apply_state(state);wrist.set_allowed(true);wrist.update_tracking(true,true,true);await frames()
	check(wrist.panel.state.mic_mode=="muted" and ptt.is_empty(),"Mic starts off without capture/PTT activation")
	check(wrist.visible and wrist.viewport.render_target_update_mode==SubViewport.UPDATE_WHEN_VISIBLE,"Tracked wrist renders only while visible")
	check(wrist.panel.buttons.group.disabled and wrist.panel.buttons.faction.disabled,"Native missing group/faction grants disable channel buttons")
	wrist.panel.set_hover("channel:group");check(wrist.panel.detail.text.contains("Join a group"),"Disabled channel explains authoritative eligibility")
	wrist.panel.activate("channel:group");check(channels.is_empty(),"Unavailable channel never emits tune request")
	wrist.panel.activate("channel:planet");check(channels==["planet"],"Available planetary channel emits exact relay ID")
	for side in ["left","right"]:
		wrist.set_offhand(side)
		var transform: Transform3D=wrist.underside_mount(Transform3D.IDENTITY)
		var sign_value:=1.0 if side=="left" else -1.0
		check(transform.origin.x*sign_value>0.04 and transform.basis.z.dot(Vector3.RIGHT*sign_value)>0.99,"%s display remains on palm-facing underside"%side)
		check(transform.basis.determinant()>0.99,"%s underside mount remains a valid unmirrored orientation"%side)
	wrist.set_offhand("left");wrist.global_transform=Transform3D.IDENTITY
	var front:=Vector3(0,0,0.08)
	check(not wrist.hit_test(front,Vector3.FORWARD).is_empty(),"Close pointing finger intersects underside panel")
	check(wrist.hit_test(Vector3(0,0,-0.08),Vector3.BACK).is_empty(),"Finger on dorsal/back side cannot select underside controls")
	check(wrist.hit_test(Vector3(0,0,0.6),Vector3.FORWARD).is_empty(),"Distant weapon/controller ray cannot select wrist controls")
	var vox: Vector2=wrist.panel.mode_buttons.vox.get_global_rect().get_center()
	var local_point:=Vector3((vox.x/640.0-0.5)*Wrist.METERS.x,(0.5-vox.y/320.0)*Wrist.METERS.y,0.08)
	var projected: Dictionary=wrist.hit_test(local_point,Vector3.FORWARD)
	check(not projected.is_empty() and projected.pixel.distance_to(vox)<0.01,"Native finger projection resolves the rendered VOX button pixel")
	wrist.pointer_frame({"pixel":vox},0.8);check(modes.is_empty(),"Held trigger on arrival cannot activate microphone")
	wrist.pointer_frame({"pixel":vox},0.0);wrist.pointer_frame({"pixel":vox},0.8)
	check(modes==["vox"],"Explicit finger+trigger selects voice activation exactly once")
	wrist.pointer_frame({"pixel":vox},0.9);check(modes.size()==1,"Sustained trigger does not repeat mode activation")
	check(wrist.blocks_combat(),"Wrist selection captures combat interaction before ranged process")
	state.mic_mode="ptt";wrist.apply_state(state)
	var talk: Vector2=wrist.panel.talk.get_global_rect().get_center()
	wrist.pointer_frame({"pixel":talk},0);wrist.pointer_frame({"pixel":talk},0.8)
	check(wrist.ptt_down and ptt[-1],"Finger hold on TALK drives push-to-talk")
	wrist.pointer_frame({},0.8);check(not wrist.ptt_down and not ptt[-1],"Leaving TALK immediately releases microphone transmit")
	wrist.pointer_frame({"pixel":talk},0);wrist.pointer_frame({"pixel":talk},0.8)
	wrist.update_tracking(true,false,true)
	check(not wrist.ptt_down and not wrist.visible and not wrist.blocks_combat(),"Offhand tracking loss releases PTT and hides controls")
	wrist.update_tracking(true,true,true);wrist.pointer_frame({"pixel":talk},0.8)
	check(not wrist.ptt_down,"Tracking regain requires trigger release before transmitting")
	wrist.pointer_frame({"pixel":talk},0);wrist.pointer_frame({"pixel":talk},0.8);wrist.set_allowed(true,false,"Hands occupied")
	check(not wrist.ptt_down and not wrist.blocks_combat(),"Held tool/item blocks voice pointer without using grip input")
	wrist.set_allowed(false);check(wrist.viewport.render_target_update_mode==SubViewport.UPDATE_DISABLED,"Blocked lifecycle stops wrist redraw")
	var valid: Dictionary={"authenticated":true,"character":true,"world":true,"loading":false,"alive":true,"focused":true,"tracked":true,"menu":false}
	check(Lifecycle.evaluate(valid).allowed,"Active tracked focused living character allows listening/explicit mic")
	for key in valid:
		var blocked:=valid.duplicate();blocked[key]=not blocked[key]
		check(not Lifecycle.evaluate(blocked).allowed,"Voice gate blocks "+key+" invalid state")
	var app:=Harness.new();root.add_child(app);app.player=Body.new();app.add_child(app.player)
	app.menu=PanelContainer.new();app.add_child(app.menu);app.menu.hide()
	app.creator=Control.new();app.add_child(app.creator);app.creator.hide()
	app.voice_chat=VoiceProbe.new();app.add_child(app.voice_chat)
	app.datapad_account="fixture";app.datapad_character_id="123";app.auth_revision=7
	app.world_ready=true;app.loading_stage=true;app.update_voice_chat()
	check(not app.voice_chat.allowed and app.voice_chat.contexts[-1]==["fixture","123",7,""],"Main passes exact authoritative account context and blocks loading")
	app.datapad_character_id="";app.auth_revision=8;app.update_voice_chat()
	check(app.voice_chat.contexts[-1][1].is_empty() and app.voice_chat.contexts[-1][2]==8,"Account reset invalidates voice identity before further transmit")
	app.queue_free();wrist.queue_free();rig.queue_free();await frames()
	print(JSON.stringify({"passed":failures.is_empty(),"checks":checks,"failures":failures,"xr":"mocked; hardware not tested","audio":"no microphone or network"}))
	quit(0 if failures.is_empty() else 1)
