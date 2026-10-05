extends SceneTree
class MockCodec extends Node:
	signal encoded_frame(payload: PackedByteArray)
	var available:=true
	var level:=0.0
	var capture:=false
	var capture_enabled:=false
	var transmitting:=false
	var received:=0
	var cleared:=0
	func set_capture_enabled(value: bool) -> void:capture=value;capture_enabled=value
	func set_transmitting(value: bool) -> void:transmitting=value
	func clear_speakers() -> void:cleared+=1
	func push_frame(_id,_seq,_payload,_spatial,_position) -> void:received+=1
	func shutdown() -> void:capture=false;transmitting=false
class MockTransport extends Node:
	var sent:=0
	var tuned: Array=[]
	var closed:=0
	func tune(channel: String) -> bool:tuned.append(channel);return true
	func send_frame(_payload: PackedByteArray) -> bool:sent+=1;return true
	func shutdown() -> void:closed+=1
class PendingPresence extends RefCounted:
	signal completed(value: Dictionary)
class MockApp extends Node:
	var services: Node
	var pending: Array=[]
	func api(_method, _path, _payload) -> Dictionary:
		var request:=PendingPresence.new()
		pending.append(request)
		return await request.completed
class Harness extends "res://scripts/voice_chat.gd":
	var attempts:=0
	func _connect() -> void:attempts+=1;busy=true
var failures: Array[String]=[]
var checks:=0
func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures.append(message);push_error(message)
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var app:=MockApp.new();root.add_child(app)
	var voice:=Harness.new();root.add_child(voice);voice.set_process(false);voice.app=app
	var codec:=MockCodec.new();voice.add_child(codec);voice.codec=codec
	var transport:=MockTransport.new();voice.add_child(transport);voice.transport=transport
	codec.encoded_frame.connect(voice._encoded)
	voice.set_context("fixture","123",1)
	voice.set_allowed(true);voice._process(.02)
	check(voice.attempts==1 and not codec.capture,"Entry connects listening without opening microphone")
	voice._control({"type":"hello","epoch":1,"channel":"proximity","granted_channels":["proximity","planet"],"reasons":{"group":"Join a group"}})
	voice._process(.02)
	check(voice.connected and voice.mic_mode=="muted" and not codec.capture,"Voice begins muted after admission")
	voice.set_channel("group")
	check(transport.tuned.is_empty() and voice.error=="Join a group","Unpermitted group cannot be tuned")
	voice.set_mic_mode("vox");codec.level=.2;voice._process(.02)
	check(codec.capture and codec.transmitting,"Explicit VOX enables microphone and gates detected speech")
	codec.encoded_frame.emit(PackedByteArray([0xf8,0xff,0xfe]))
	check(transport.sent==1,"Admitted active speech reaches transport")
	codec.level=0;voice._process(.3)
	check(not codec.transmitting,"VOX ends after silence hangover")
	voice.set_channel("planet")
	check(transport.tuned==["planet"] and not voice.pending_channel.is_empty(),"Channel switch awaits server confirmation")
	voice._frame(1,1,"456",Vector3.ZERO,PackedByteArray([0xf8,0xff,0xfe]))
	codec.encoded_frame.emit(PackedByteArray([0xf8,0xff,0xfe]))
	check(codec.received==0 and transport.sent==1,"Pending switch drops old receive and transmit audio")
	voice._control({"type":"tuned","epoch":2,"channel":"planet","granted_channels":["proximity","planet"]})
	check(voice.active_channel=="planet" and voice.pending_channel.is_empty(),"Server tune acknowledgment selects planetary channel")
	voice.set_mic_mode("ptt");voice._process(.02)
	check(codec.capture and not codec.transmitting,"PTT requires explicit hold after selecting its mode")
	voice.set_ptt(true);voice._process(.02)
	check(codec.transmitting,"PTT hold transmits")
	voice.set_ptt(false);voice._process(.02)
	check(not codec.transmitting,"PTT release immediately stops transmission")
	voice.set_allowed(false)
	check(not codec.capture and not codec.transmitting,"Focus/menu/lifecycle gate closes microphone")
	voice._frame(2,2,"456",Vector3.ZERO,PackedByteArray([0xf8,0xff,0xfe]))
	check(codec.received==0,"Disallowed state never queues voice playback")
	voice.set_context("other","789",2)
	check(not voice.connected and voice.mic_mode=="muted" and voice.granted_channels.is_empty(),"Account change clears credentials/channel grants and resets microphone")
	check(transport.closed>=2 and codec.cleared>=3,"Account/channel/focus changes flush audio")
	voice.set_allowed(true)
	voice._control({"type":"hello","epoch":3,"channel":"proximity","granted_channels":["proximity"]})
	voice._presence()
	check(app.pending.size()==1 and voice.presence_busy,"Native presence request can remain in flight")
	var old_revision: int=voice.connection_revision
	voice._disconnected("Fixture connection loss")
	check(voice.connection_revision>old_revision and not voice.presence_busy,"Connection loss invalidates pending native observations")
	voice._control({"type":"hello","epoch":4,"channel":"proximity","granted_channels":["proximity"]})
	voice._presence()
	var close_count: int=transport.closed
	app.pending[0].completed.emit({"ok":false})
	check(voice.connected and transport.closed==close_count,"Old failed presence reply cannot close a reconnected socket")
	check(voice.presence_busy,"Old completion cannot clear the new presence request busy flag")
	app.pending[1].completed.emit({"ok":true})
	check(voice.connected and not voice.presence_busy,"Current connection accepts its own successful presence reply")
	voice._presence()
	app.pending[2].completed.emit({"ok":false})
	check(not voice.connected and transport.closed>close_count,"Current failed native presence still disconnects securely")
	voice.shutdown()
	check(voice.character_id.is_empty() and not codec.capture,"Shutdown releases identity and microphone")
	var wire:=preload("res://scripts/voice_transport.gd").new();root.add_child(wire)
	check(wire.connect_voice("ws://example.com:18444/voice",null,"private-fixture")==ERR_INVALID_PARAMETER,"Remote cleartext voice is rejected")
	check(wire.connect_voice("wss://example.com:18444/voice",null,"private-fixture")==ERR_INVALID_PARAMETER,"Encrypted voice requires explicit trusted CA")
	check(not wire.send_frame(PackedByteArray([1])),"Unadmitted transport cannot send voice")
	app.queue_free();voice.queue_free();wire.queue_free();await process_frame
	print(JSON.stringify({"passed":failures.is_empty(),"checks":checks,"failures":failures,"microphone":"mocked; never activated","xr":"off"}))
	quit(0 if failures.is_empty() else 1)
