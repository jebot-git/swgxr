extends SceneTree
## Exercise the production voice state machine with reordered native/relay
## receipts. Synthetic codec only: no microphone, network, GPU or live headset.
const Fixture=preload("res://tests/jtl_voice_smoke.gd")
var checks:=0
var failures:Array=[]
var epoch:=0
func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures.append(label);push_error(label)
func packet(channel:String,zone:String="tatooine",ship:String="0",kind:String="tuned",extra:Array=["group","faction"])->Dictionary:
	epoch+=1
	var scope:="sector" if zone=="space_tatooine" else "planet"
	return {"type":kind,"epoch":epoch,"channel":channel,"scope":scope,"zone":zone,"ship_id":ship,"granted_channels":["proximity",scope]+extra,"reasons":{"group":"Join a group.","faction":"Faction membership required."}}
func _initialize()->void:call_deferred("run")
func run()->void:
	var host:=Fixture.Host.new();root.add_child(host)
	var voice:=preload("res://scripts/voice_chat.gd").new();root.add_child(voice);voice.set_process(false);voice.app=host
	var codec:=Fixture.Codec.new();voice.add_child(codec);voice.codec=codec
	var wire:=Fixture.Transport.new();voice.add_child(wire);voice.transport=wire
	voice.set_context("fixture","123",1,"native-session");voice.set_world_context("tatooine");voice.set_allowed(true)
	voice._control(packet("proximity","tatooine","0","hello"));voice.set_channel("planet");voice._control(packet("planet"))
	voice.set_mic_mode("vox");codec.level=.2;voice._process(.02)
	check(voice.desired_channel=="planet" and codec.transmitting,"Explicit Planet selection and VOX establish the original audience")
	# Relay publication can precede the native HTTP boarding result. A formerly
	# expired context timer must not immediately disconnect this fresh change.
	voice.context_deadline=-1
	voice._control(packet("sector","space_tatooine","77"))
	voice._process(.02);voice._encoded(PackedByteArray([1]))
	check(voice.connected and not voice.context_confirmed and voice.context_deadline>Time.get_ticks_msec()/1000.0,"Relay-first context gets a fresh bounded reconciliation deadline")
	check(not codec.capture_enabled and not codec.transmitting and wire.sent==0,"Future relay context immediately closes both capture and transmission")
	voice.set_world_context("space_tatooine","77");voice._process(.02)
	check(voice.context_confirmed and voice.desired_channel=="sector" and voice.active_channel=="sector" and codec.transmitting,"Later native boarding consumes the buffered acknowledgment and preserves Planet-to-Sector VOX")
	voice._encoded(PackedByteArray([1]));check(wire.sent==1,"Only confirmed Sector audio reaches the transport")
	# Reverse order, with an intervening old relay packet.
	voice.set_world_context("tatooine");voice._control(packet("sector","space_tatooine","77"));voice._process(.02)
	check(not voice.context_confirmed and not codec.capture_enabled,"Native-first landing rejects the old ship context")
	voice._control(packet("planet"));voice._process(.02)
	check(voice.desired_channel=="planet" and voice._channel_ready() and codec.transmitting,"Matching relay landing preserves Sector-to-Planet audience")
	# Cache only the latest context, never an earlier epoch from the same socket.
	voice._control(packet("sector","space_tatooine","88"));voice._control(packet("sector","space_tatooine","99"))
	voice.set_world_context("space_tatooine","88");voice._process(.02)
	check(not voice.context_confirmed and not codec.capture_enabled,"Intermediate hull cannot consume an older superseded acknowledgment")
	voice.set_world_context("space_tatooine","99");voice._process(.02)
	check(voice._channel_ready() and codec.transmitting,"Final native hull consumes the latest acknowledgment")
	# New sockets always start at proximity. Preserve area or private intent and
	# prevent VOX from using that temporary default before its tune is confirmed.
	for selected in ["sector","group","faction"]:
		voice.set_channel(selected)
		if not voice.pending_channel.is_empty():voice._control(packet(selected,"space_tatooine","99"))
		voice.set_mic_mode("vox");voice._process(.02)
		voice._disconnected("Synthetic relay interruption")
		check(voice.relay_context.is_empty() and voice.desired_channel==selected,"Disconnect clears socket context while retaining "+selected+" intent")
		var sent_before:int=wire.sent
		voice._control(packet("proximity","space_tatooine","99","hello"));voice._process(.02);voice._encoded(PackedByteArray([1]))
		check(voice.pending_channel==selected and wire.tunes[-1]==selected and voice.mic_mode=="vox","Reconnect requests the previously selected "+selected+" channel")
		check(not codec.capture_enabled and not codec.transmitting and wire.sent==sent_before,"Reconnect cannot transmit VOX to temporary proximity for "+selected)
		voice._frame(epoch,1,"999",Vector3.ZERO,PackedByteArray([1]));check(codec.frames.is_empty(),"Temporary proximity playback is also closed for "+selected)
		voice._control(packet(selected,"space_tatooine","99"));voice._process(.02);voice._encoded(PackedByteArray([1]))
		check(voice._channel_ready() and codec.transmitting and wire.sent==sent_before+1,"Matching "+selected+" acknowledgment resumes authorized VOX")
	# Native grant loss must require explicit user choice, even though the relay
	# keeps its compatibility fallback and an existing selected VOX mode.
	var panel:=preload("res://scripts/voice_panel.gd").new();root.add_child(panel);panel.set_active(true)
	for selected in ["group","faction"]:
		voice._control(packet(voice.active_channel,"space_tatooine","99"));voice.set_channel(selected)
		if not voice.pending_channel.is_empty():voice._control(packet(selected,"space_tatooine","99"))
		voice.set_mic_mode("vox");voice._process(.02)
		voice._control(packet("proximity","space_tatooine","99","tuned",[]));voice._process(.02)
		check(voice.desired_channel==selected and voice.mic_mode=="muted" and not voice._channel_ready() and not codec.capture_enabled,"Lost "+selected+" grant explicitly mutes without adopting public proximity")
		panel.apply_state(voice.get_state())
		check(panel.status.text.contains(selected.to_upper()) and panel.status.text.contains("UNAVAILABLE") and panel.detail.text.contains("Microphone muted"),"Unavailable "+selected+" selection and mute reason remain visible")
		voice.set_mic_mode("vox");voice._process(.02)
		check(not codec.capture_enabled and not codec.transmitting,"Selecting VOX alone cannot authorize a fallback audience after "+selected+" loss")
		voice.set_channel("proximity");voice._process(.02)
		check(voice._channel_ready() and codec.transmitting,"Explicit proximity choice authorizes the fallback audience after "+selected+" loss")
	# Same behavior when the native grant disappeared during a reconnect.
	voice._control(packet("proximity","space_tatooine","99"));voice.set_channel("group");voice._control(packet("group","space_tatooine","99"));voice.set_mic_mode("vox")
	voice._disconnected("Group removed while disconnected");voice._control(packet("proximity","space_tatooine","99","hello",[]));voice._process(.02)
	check(voice.desired_channel=="group" and voice.mic_mode=="muted" and not codec.capture_enabled,"Reconnect with a vanished group grant remains muted")
	# A tune rejection also cannot silently revive the previous audience.
	voice._control(packet("proximity","space_tatooine","99"));voice.set_mic_mode("vox")
	voice._control({"type":"error","error":"Native channel permission changed."});voice._process(.02)
	check(voice.mic_mode=="muted" and not codec.capture_enabled and voice.desired_channel=="group","Rejected restore leaves the intended channel selected and microphone muted")
	# A PTT hold may not span a hull or channel change.
	voice.set_channel("proximity");voice.set_mic_mode("ptt");voice.set_ptt(true);voice._process(.02)
	check(codec.transmitting,"PTT regression begins with an explicit hold")
	voice._control(packet("proximity","space_tatooine","100"));voice.set_ptt(true);voice.set_world_context("space_tatooine","100");voice._process(.02)
	check(voice._channel_ready() and not voice.ptt and not codec.transmitting,"Reconciled boarding never revives old or unconfirmed PTT")
	# Waiting is bounded, and repeated mismatches cannot keep stale audio alive.
	voice._control(packet("proximity","space_tatooine","101"));voice.context_deadline=Time.get_ticks_msec()/1000.0-.1
	var expired:float=voice.context_deadline
	voice._control(packet("proximity","space_tatooine","102"))
	check(voice.context_deadline==expired,"Repeated future contexts do not extend a pending deadline")
	voice._process(.02)
	check(not voice.connected and voice.relay_context.is_empty() and not codec.capture_enabled,"Unmatched context eventually disconnects and discards cached acknowledgments")
	voice.set_world_context("space_tatooine","102");check(not voice.context_confirmed,"Old socket acknowledgment cannot be consumed after disconnect")
	voice.set_context("new-account","456",2,"new-session")
	check(voice.desired_channel=="proximity" and voice.mic_mode=="muted" and voice.relay_context.is_empty(),"Account change resets voice intent and clears all buffered permissions")
	voice.free();host.free();panel.free()
	print(JSON.stringify({"passed":failures.is_empty(),"checks":checks,"failures":failures,"audio":"mock codec; microphone never activated","network":"reordered authenticated relay/native fixtures","renderer":"dummy","live_xr":false}));quit(0 if failures.is_empty() else 1)
