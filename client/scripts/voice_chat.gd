extends Node
## Account-bound voice orchestration. Audio work stays in the native codec.
signal status_changed(state: Dictionary)
const Transport=preload("res://scripts/voice_transport.gd")
const CHANNELS=["proximity","group","planet","faction"]
var app: Node
var transport: Node
var codec: Node
var account := ""
var character_id := ""
var auth_revision := -1
var live_session_id := ""
var generation := 0
var connection_revision := 0
var allowed := false
var connected := false
var busy := false
var presence_busy := false
var needs_presence := false
var presence_interval := 5.0
var presence_clock := 0.0
var retry_at := 0.0
var retry_delay := 2.0
var active_channel := "proximity"
var mic_mode := "muted"
var ptt := false
var transmitting := false
var granted_channels: Array[String]=[]
var reasons: Dictionary={}
var error := "Enter the galaxy to connect voice."
var pending_channel := ""
var tune_deadline := 0.0
var level := 0.0
var voice_hold := 0.0
var status_clock := 0.0
var peers: Array=[]

func configure(owner_app: Node) -> void:
	app=owner_app
	if transport!=null:return
	transport=Transport.new();add_child(transport)
	transport.control_received.connect(_control)
	transport.frame_received.connect(_frame)
	transport.disconnected.connect(_disconnected)
	var codec_script: Script=load("res://scripts/voice_codec.gd")
	if codec_script==null:error="Voice codec is unavailable.";return
	codec=codec_script.new();add_child(codec)
	codec.encoded_frame.connect(_encoded)
	_emit()

func set_context(value_account: String, value_character: String, revision: int, session_id: String="") -> void:
	if account==value_account and character_id==value_character and auth_revision==revision and live_session_id==session_id:return
	_reset()
	account=value_account;character_id=value_character;auth_revision=revision;live_session_id=session_id
	mic_mode="muted";active_channel="proximity";retry_at=0;retry_delay=2
	error="Connecting voice…" if not character_id.is_empty() else "Enter the galaxy to connect voice."
	_emit()

func set_allowed(value: bool) -> void:
	if allowed==value:return
	allowed=value
	if not allowed:
		ptt=false;voice_hold=0;transmitting=false
		if codec!=null:codec.set_transmitting(false);codec.set_capture_enabled(false);codec.clear_speakers()
	_emit()

func set_channel(channel: String) -> void:
	if channel not in CHANNELS:return
	if channel not in granted_channels:
		error=str(reasons.get(channel,"Channel is not available for this character."));_emit();return
	if not connected or channel==active_channel or not pending_channel.is_empty():return
	pending_channel=channel;transmitting=false;voice_hold=0
	if codec!=null:codec.set_transmitting(false);codec.clear_speakers()
	tune_deadline=Time.get_ticks_msec()/1000.0+5
	if not transport.tune(channel):_disconnected("Could not switch voice channel.")
	_emit()

func set_mic_mode(value: String) -> void:
	if value not in ["muted","vox","ptt"]:return
	mic_mode=value;ptt=false;voice_hold=0;transmitting=false
	if codec!=null:codec.set_transmitting(false);codec.set_capture_enabled(false)
	_emit()

func set_ptt(value: bool) -> void:ptt=value and allowed and mic_mode=="ptt"

func get_state() -> Dictionary:
	return {"granted_channels":granted_channels.duplicate(),"reasons":reasons.duplicate(),
		"active_channel":active_channel,"pending_channel":pending_channel,"mic_mode":mic_mode,
		"transmitting":transmitting,"connected":connected,"error":error,"level":level,
		"allowed":allowed,"peers":peers.duplicate(),"codec_available":codec!=null and bool(codec.get("available"))}

func _emit() -> void:status_changed.emit(get_state())

func _process(delta: float) -> void:
	if app==null or transport==null:return
	var now:=Time.get_ticks_msec()/1000.0
	if allowed and not character_id.is_empty() and not connected and not busy and now>=retry_at:
		_connect()
	if not pending_channel.is_empty() and now>tune_deadline:
		transport.shutdown();_disconnected("Voice channel switch timed out.")
	if connected and needs_presence and allowed:
		presence_clock+=delta
		if presence_clock>=presence_interval and not presence_busy:
			presence_clock=0;_presence()
	if codec!=null:
		var capture:=allowed and connected and pending_channel.is_empty() and mic_mode!="muted" and active_channel in granted_channels
		codec.set_capture_enabled(capture)
		capture=capture and bool(codec.get("capture_enabled"))
		if allowed and connected and mic_mode!="muted" and not capture and pending_channel.is_empty():
			error=str(codec.get("status"))
		level=float(codec.get("level")) if capture else 0.0
		voice_hold=0.25 if capture and level>=0.018 else maxf(0,voice_hold-delta)
		transmitting=capture and (ptt if mic_mode=="ptt" else voice_hold>0)
		codec.set_transmitting(transmitting)
	status_clock+=delta
	if status_clock>=0.15:status_clock=0;_emit()

func _identity() -> Dictionary:
	var result: Dictionary={"account":account,"character_id":character_id}
	if is_instance_valid(app.get("services")) and app.services.has_method("identity_payload"):
		result=app.services.identity_payload()
	elif is_instance_valid(app.get("player")):
		var point: Vector3=app.source_position_at(app.player.global_position)
		result.merge({"position":[point.x,point.y,point.z],"building_id":"0","cell_index":0})
	if not live_session_id.is_empty():result.session_id=live_session_id
	return result

func _connect() -> void:
	if codec==null or not bool(codec.get("available")):
		error="Voice codec unavailable; install the pinned TwoVoIP dependency.";retry_at=Time.get_ticks_msec()/1000.0+30;return
	busy=true;connection_revision+=1
	var connection_version:=connection_revision
	var version:=generation
	var reply: Dictionary=await app.api(HTTPClient.METHOD_POST,"/voice/session",_identity())
	if version!=generation or connection_version!=connection_revision:return
	busy=false
	if not reply.get("ok",false) or reply.get("backend")!="core3" or reply.get("protocol")!="swgxr-voice-v1":
		_disconnected(str(reply.get("error","Voice service is unavailable.")));return
	var connection: RefCounted=app.remote_connection
	var certificate: X509Certificate
	var url: String
	if connection.configured:
		var expression:=RegEx.new();expression.compile("^https://(\\[[0-9A-Fa-f:]+\\]|[A-Za-z0-9.-]+)(?::[0-9]{1,5})?$")
		var matched:=expression.search(connection.base_url)
		if matched==null or int(reply.get("relay_port",0))!=18444:
			_disconnected("Voice relay endpoint is invalid.");return
		certificate=X509Certificate.new()
		if certificate.load(connection.ca_certificate_path)!=OK:
			_disconnected("Voice TLS certificate is unavailable.");return
		url="wss://"+matched.get_string(1)+":18444/voice"
	else:
		# Only the explicit trusted loopback development backend permits cleartext.
		if app.backend_url!="http://127.0.0.1:18080" or int(reply.get("relay_port",0))!=18084:
			_disconnected("Local voice requires the trusted loopback backend.");return
		url="ws://127.0.0.1:18084/voice"
	needs_presence=bool(reply.get("needs_presence",true))
	presence_interval=clampf(float(reply.get("presence_interval",5)),5,10);presence_clock=0
	var ticket: String=str(reply.get("ticket",""))
	reply.erase("ticket")
	var result: Error=transport.connect_voice(url,certificate,ticket)
	ticket=""
	if result!=OK:_disconnected("Could not open the voice connection.")
	else:
		# Transport admission is asynchronous; avoid issuing another ticket meanwhile.
		busy=true;error="Connecting voice…"
	_emit()

func _presence() -> void:
	# Services already refresh native membership/placement on their own cadence.
	# Avoid a second legacy login while that source observation is still fresh.
	if is_instance_valid(app.get("services")) and float(app.services.get("state_age"))<4.0:return
	presence_busy=true
	var connection_version:=connection_revision
	var version:=generation
	var result: Dictionary=await app.api(HTTPClient.METHOD_POST,"/voice/presence",_identity())
	if version!=generation or connection_version!=connection_revision:return
	presence_busy=false
	if not result.get("ok",false):
		transport.shutdown();_disconnected("Native voice presence is unavailable.")

func _control(message: Dictionary) -> void:
	var kind: String=str(message.get("type",""))
	if kind in ["hello","tuned"]:
		var channel: String=str(message.get("channel",""))
		var grants: Variant=message.get("granted_channels")
		if channel not in CHANNELS or not grants is Array or grants.size()>4:
			transport.shutdown();_disconnected("Invalid voice permissions.");return
		granted_channels.clear()
		for grant in grants:
			if grant is String and grant in CHANNELS and grant not in granted_channels:granted_channels.append(grant)
		if channel not in granted_channels:
			transport.shutdown();_disconnected("Voice channel is no longer available.");return
		reasons=message.get("reasons",{}) if message.get("reasons",{}) is Dictionary else {}
		active_channel=channel;pending_channel="";connected=true;busy=false;retry_delay=2;error=""
		if codec!=null:codec.clear_speakers()
	elif kind=="roster":
		var entries: Variant=message.get("peers",[])
		peers=entries.slice(0,128) if entries is Array else []
	elif kind=="error":
		pending_channel="";error=str(message.get("error","Voice request was rejected.")).left(180)
	_emit()

func _frame(_epoch: int, serial: int, speaker: String, source: Vector3, payload: PackedByteArray) -> void:
	if not connected or not allowed or codec==null or not pending_channel.is_empty() or speaker==character_id:return
	var point:=source
	if is_instance_valid(app.get("services")) and app.services.has_method("world"):
		point=app.services.world([source.x,source.y,source.z])
	codec.push_frame(speaker,serial,payload,active_channel=="proximity",point+Vector3.UP*1.55)

func _encoded(payload: PackedByteArray) -> void:
	if transmitting and allowed and connected and pending_channel.is_empty():transport.send_frame(payload)

func _disconnected(message: String) -> void:
	# Invalidate HTTP callbacks from this socket, including same-account reconnects.
	connection_revision+=1;presence_busy=false
	if transport!=null:transport.shutdown()
	connected=false;busy=false;transmitting=false;pending_channel="";ptt=false;voice_hold=0
	granted_channels.clear();peers.clear();error=message.left(180)
	if codec!=null:codec.set_transmitting(false);codec.set_capture_enabled(false);codec.clear_speakers()
	retry_at=Time.get_ticks_msec()/1000.0+retry_delay;retry_delay=minf(30,retry_delay*2)
	_emit()

func _reset() -> void:
	generation+=1;connection_revision+=1;connected=false;busy=false;presence_busy=false;needs_presence=false;pending_channel=""
	granted_channels.clear();reasons.clear();peers.clear();ptt=false;voice_hold=0;transmitting=false
	if transport!=null:transport.shutdown()
	if codec!=null:codec.set_transmitting(false);codec.set_capture_enabled(false);codec.clear_speakers()

func shutdown() -> void:
	_reset();allowed=false;account="";character_id="";mic_mode="muted"
	if codec!=null:codec.shutdown()

func _exit_tree() -> void:shutdown()
