extends SceneTree
class Codec extends Node:
	var available:=true
	var capture_enabled:=false
	var transmitting:=false
	var level:=0.0
	var frames:Array=[]
	var cleared:=0
	func set_capture_enabled(value:bool)->void:capture_enabled=value
	func set_transmitting(value:bool)->void:transmitting=value
	func clear_speakers()->void:cleared+=1;frames=[]
	func push_frame(id,sequence,payload,spatial,point)->void:frames.append({"id":id,"sequence":sequence,"payload":payload,"spatial":spatial,"point":point})
	func shutdown()->void:capture_enabled=false;transmitting=false
class Transport extends Node:
	var tunes:Array=[]
	var sent:=0
	func tune(channel:String)->bool:tunes.append(channel);return true
	func send_frame(_payload:PackedByteArray)->bool:sent+=1;return true
	func shutdown()->void:pass
class Cabin extends Node3D:
	func world(point:Array)->Vector3:return Vector3(point[0],10000+point[1],-point[2])
class Ship extends Node3D:
	var ship:Dictionary={"id":"77","crew":[{"id":"987"}]}
	var scene:Node3D
	var active:=true
	func aboard()->bool:return active
class Services extends Node:
	var called:=false
	var state_age:=100.0
	func identity_payload()->Dictionary:called=true;return {"zone":"wrong_ground_zone","position":[999,999,999]}
	func world(point:Array)->Vector3:return Vector3(point[0]-3000,point[1],-point[2]-4000)
class Host extends Node:
	var space:Node3D
	var services:Node
var checks:=0
var failures:Array=[]
func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures.append(label);push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	var host:=Host.new();root.add_child(host);host.space=Ship.new();host.add_child(host.space);host.space.scene=Cabin.new();host.space.add_child(host.space.scene);host.services=Services.new();host.add_child(host.services)
	var voice:=preload("res://scripts/voice_chat.gd").new();root.add_child(voice);voice.set_process(false);voice.app=host
	var codec:=Codec.new();voice.add_child(codec);voice.codec=codec;var wire:=Transport.new();voice.add_child(wire);voice.transport=wire
	voice.set_context("tester","123",1,"owned-session");voice.set_world_context("tatooine");voice.set_allowed(true)
	var identity:Dictionary=voice._identity()
	check(identity=={"account":"tester","character_id":"123","session_id":"owned-session"} and not host.services.called,"Live voice sends only owned session identity, never stale ground coordinates or claimed ship membership")
	voice._control({"type":"hello","channel":"proximity","epoch":1,"scope":"planet","zone":"tatooine","ship_id":"0","granted_channels":["proximity","planet","group"]})
	voice.set_channel("planet");voice._control({"type":"tuned","channel":"planet","epoch":2,"scope":"planet","zone":"tatooine","ship_id":"0","granted_channels":["proximity","planet","group"]});wire.tunes.clear()
	check(voice.context_confirmed and voice.active_channel=="planet" and voice.connected,"Native ground admission confirms the selected planetary channel")
	voice.set_mic_mode("ptt");voice.set_ptt(true);voice._process(.02)
	check(codec.transmitting,"Explicit push-to-talk works before boarding")
	voice.set_world_context("space_tatooine","77")
	check(not codec.capture_enabled and not codec.transmitting and not voice.ptt and not voice.context_confirmed and voice.granted_channels.is_empty(),"Boarding flushes old audio and held PTT before changing coordinate scope")
	voice._frame(1,1,"987",Vector3.ZERO,PackedByteArray([0xf8,0xff,0xfe]))
	check(codec.frames.is_empty(),"Frames cannot play while relay location is unconfirmed")
	voice._control({"type":"tuned","channel":"planet","epoch":2,"scope":"planet","zone":"tatooine","ship_id":"0","granted_channels":["proximity","planet"]})
	check(not voice.context_confirmed,"Delayed old-planet acknowledgment cannot reopen ship audio")
	voice._control({"type":"tuned","channel":"sector","epoch":3,"scope":"sector","zone":"space_tatooine","ship_id":"77","granted_channels":["proximity","sector","group"]})
	check(voice.context_confirmed and voice.active_channel=="sector" and "planet" not in voice.granted_channels,"Authoritative Planet-to-Sector tuning preserves the location-wide channel choice")
	voice._process(.02);check(codec.capture_enabled and not codec.transmitting,"Boarding does not revive an old push-to-talk hold")
	voice._frame(3,2,"555",Vector3.ZERO,PackedByteArray([0xf8,0xff,0xfe]))
	check(codec.frames.size()==1 and not codec.frames[0].spatial,"Sector voice admits another ship as non-spatial radio")
	voice.set_channel("proximity");check(wire.tunes==["proximity"],"Crew proximity remains an explicit normal channel choice")
	voice._control({"type":"tuned","channel":"proximity","epoch":4,"scope":"sector","zone":"space_tatooine","ship_id":"77","granted_channels":["proximity","sector","group"]})
	voice._frame(4,3,"555",Vector3.ZERO,PackedByteArray([0xf8,0xff,0xfe]))
	check(codec.frames.is_empty(),"Proximity refuses a different hull occupant even at the same local origin")
	voice._frame(4,4,"987",Vector3(2,.4,20),PackedByteArray([0xf8,0xff,0xfe]))
	check(codec.frames.size()==1 and codec.frames[0].spatial and codec.frames[0].point.distance_to(Vector3(2,10001.95,-20))<.001,"Same-hull proximity maps original source-local voice to the rendered POB cabin")
	voice.set_channel("group");voice._control({"type":"tuned","channel":"group","epoch":5,"scope":"sector","zone":"space_tatooine","ship_id":"77","granted_channels":["proximity","sector","group"]})
	voice._frame(5,5,"555",Vector3.ZERO,PackedByteArray([0xf8,0xff,0xfe]))
	check(codec.frames.size()==1 and not codec.frames[0].spatial,"Native party radio remains independent of flight crew or hull")
	voice.set_world_context("space_tatooine","88");host.space.ship={"id":"88","crew":[{"id":"666"}]}
	voice._control({"type":"tuned","channel":"group","epoch":6,"scope":"sector","zone":"space_tatooine","ship_id":"88","granted_channels":["proximity","sector","group"]})
	check(voice.context_confirmed and voice.active_channel=="group","Native hull change preserves the selected group channel")
	voice.set_channel("sector");voice._control({"type":"tuned","channel":"sector","epoch":7,"scope":"sector","zone":"space_tatooine","ship_id":"88","granted_channels":["proximity","sector"]})
	host.space.active=false;voice.set_world_context("tatooine");voice._control({"type":"tuned","channel":"planet","epoch":8,"scope":"planet","zone":"tatooine","ship_id":"0","granted_channels":["proximity","planet"]})
	check(voice.active_channel=="planet" and voice.context_confirmed,"Authoritative landing maps selected Sector back to Planet")
	var panel:=preload("res://scripts/voice_panel.gd").new();root.add_child(panel);panel.set_active(true)
	panel.apply_state({"scope":"sector","active_channel":"sector","granted_channels":["proximity","sector"],"mic_mode":"muted"})
	check(panel.buttons.sector.visible and not panel.buttons.planet.visible and not panel.buttons.sector.disabled and panel.status.text.contains("SECTOR"),"Wrist/desktop controls replace Planet with Sector in space")
	var chosen:Array=[];panel.channel_requested.connect(func(channel):chosen.append(channel));panel.activate("channel:sector")
	check(chosen==["sector"],"Sector selection emits the exact authenticated relay channel ID")
	panel.apply_state({"scope":"planet","active_channel":"planet","granted_channels":["proximity","planet"],"mic_mode":"muted"})
	check(panel.buttons.planet.visible and not panel.buttons.sector.visible,"Landing restores the single Planet button")
	voice.shutdown();host.free();voice.free();panel.free()
	print(JSON.stringify({"passed":failures.is_empty(),"checks":checks,"failures":failures,"audio":"synthetic routing only; no microphone or live relay","renderer":"dummy","live_xr":false}));quit(0 if failures.is_empty() else 1)
