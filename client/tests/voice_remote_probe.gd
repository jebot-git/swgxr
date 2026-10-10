extends SceneTree
## Explicit native/WSS probe using two existing dedicated test profiles.
## Synthetic Opus only; no input device, avatar scene or headset is opened.
const Connection=preload("res://scripts/remote_connection.gd")
const Codec=preload("res://scripts/voice_codec.gd")
class ProbeTransport extends "res://scripts/voice_transport.gd":
	var failure_state: Dictionary={}
	func fail(message: String) -> void:
		failure_state={"hello_sent":hello_sent,"admitted":admitted,"websocket_state":socket.get_ready_state() if socket else -1,"close_code":socket.get_close_code() if socket else -1}
		super.fail(message)
var peers: Array=[]
var checks: Array=[]
var failed:=false
var received:=0
var decoded_energy:=0.0
var playback: AudioStreamPlayback
var audio_stream: AudioStream
var options: Dictionary={}
var disconnects: Array=[]
var events: Array=[]
func _initialize() -> void:call_deferred("run")
func check(value: bool,label: String) -> bool:
	checks.append({"passed":value,"label":label})
	if not value:failed=true
	return value
func request(connection: RefCounted,path: String,body: Variant=null) -> Dictionary:
	var http:=HTTPRequest.new();root.add_child(http);http.timeout=75
	var data: Dictionary={} if body==null else body
	var prepared: Dictionary=connection.apply_to(http,connection.base_url,path,data)
	if not prepared.get("ok",false):http.queue_free();return {}
	var method:=HTTPClient.METHOD_GET if body==null else HTTPClient.METHOD_POST
	var error:=http.request(connection.base_url+path,prepared.headers,method,"" if body==null else JSON.stringify(body))
	if error!=OK:http.queue_free();return {}
	var result: Array=await http.request_completed;http.queue_free()
	if result[0]!=HTTPRequest.RESULT_SUCCESS:return {}
	var parsed: Variant=JSON.parse_string(result[3].get_string_from_utf8())
	if not parsed is Dictionary:return {}
	parsed.ok=int(result[1])>=200 and int(result[1])<300
	return parsed
func wait_admission(peer: Dictionary,channel: String) -> bool:
	var end:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<end:
		if peer.failed:return false
		if peer.channel==channel and peer.wire.admitted:return true
		await create_timer(.02).timeout
	return false
func wait_roster(peer: Dictionary,other: Dictionary,present: bool) -> bool:
	var end:=Time.get_ticks_msec()+3000
	while Time.get_ticks_msec()<end:
		if peer.failed:return false
		var found:=false
		for member in peer.roster:
			if str(member.get("id",""))==str(other.identity.character_id):found=true
		if found==present:return true
		await create_timer(.02).timeout
	return false
func refresh_presence() -> bool:
	for peer in peers:
		var result:=await request(peer.connection,"/voice/presence",peer.identity)
		if not result.get("ok",false):return false
	return true
func receive_frame(_epoch: int,_sequence: int,_speaker: String,_point: Vector3,payload: PackedByteArray) -> void:
	received+=1
	playback.call("push_opus_packet",payload,0,0)
func exercise() -> void:
	# Reproduce entry after normal gameplay/loading, beyond the heartbeat interval.
	# Enabling automatic pings before admission used to reject this connection.
	await create_timer(5.2).timeout
	for index in range(2):
		var connection:=Connection.new()
		if not check(connection.load_profile(str(options.get("profile"+str(index+1),""))),"Private test profile loads with pinned CA"):return
		if not check(connection.account==["nettest_one","nettest_two"][index] or connection.account.begins_with("voicetest_"),"Only dedicated existing test accounts permitted"):return
		var roster:=await request(connection,"/characters")
		if not check(roster.get("ok",false) and roster.get("characters",[]).size()>0,"Existing native character available; no creation"):return
		var identity: Dictionary={"account":connection.account,"character_id":str(roster.characters[0].id)}
		var entry:=await request(connection,"/enter",identity)
		if not check(entry.get("ok",false) and entry.get("source_location") is Dictionary,"Probe uses current native spawn instead of moving its fixture"):return
		for field in ["zone","position","building_id"]:identity[field]=entry.source_location[field]
		identity.cell_index=int(entry.source_location.cell_index)
		var ticket:=await request(connection,"/voice/session",identity)
		if not check(ticket.get("ok",false) and ticket.get("protocol")=="swgxr-voice-v1","Authenticated Core3 voice ticket issued: "+str(ticket.get("error",""))):return
		var wire:=ProbeTransport.new();root.add_child(wire)
		var peer: Dictionary={"connection":connection,"identity":identity,"wire":wire,"channel":"","failed":false,"grants":[],"roster":[]}
		peers.append(peer)
		wire.control_received.connect(func(message: Dictionary):
			if message.get("type") in ["hello","tuned"]:events.append({"character_id":peer.identity.character_id,"type":message.type,"channel":message.channel,"elapsed_seconds":Time.get_ticks_msec()/1000.0})
			if message.get("type") in ["hello","tuned"]:peer.channel=message.channel;peer.grants=message.granted_channels
			if message.get("type")=="roster":peer.roster=message.peers)
		wire.disconnected.connect(func(message: String):
			peer.failed=true
			disconnects.append({"character_id":peer.identity.character_id,"message":message,"elapsed_seconds":Time.get_ticks_msec()/1000.0,"transport_state":peer.wire.failure_state}))
		if index==1:wire.frame_received.connect(receive_frame)
		var certificate:=X509Certificate.new();certificate.load(connection.ca_certificate_path)
		var expression:=RegEx.new();expression.compile("^https://([^:/]+)(?::[0-9]+)?$")
		var matched:=expression.search(connection.base_url)
		if not check(matched!=null,"Remote voice host derives from verified profile"):return
		peer.url="wss://"+matched.get_string(1)+":18444/voice";peer.certificate=certificate
		var result:=wire.connect_voice(peer.url,certificate,str(ticket.get("ticket","")))
		ticket.clear()
		if not check(result==OK and wire.socket.heartbeat_interval==0.0,"Automatic heartbeat waits for admission"):return
		if not check(result==OK and await wait_admission(peer,"proximity"),"Actual Godot WSS admission defaults to proximity"):return
		if not check(wire.socket.heartbeat_interval==5.0,"Admitted connection enables heartbeat"):return
	if not check(await refresh_presence(),"Both native voice memberships refresh"):return
	if not check(await wait_roster(peers[0],peers[1],true) and await wait_roster(peers[1],peers[0],true),"Connected players appear in both proximity rosters"):return
	var codec:=Codec.new();root.add_child(codec);codec.set_process(false)
	var encoder:=codec.make_encoder(48000,false)
	if not check(encoder!=null and not codec.capture_enabled,"Native encoder runs without microphone capture"):codec.free();return
	var packets: Array[PackedByteArray]=[]
	for frame in range(10):
		var samples:=PackedVector2Array();samples.resize(960)
		for i in range(960):samples[i]=Vector2.ONE*.25*sin(TAU*330*float(frame*960+i)/48000.0)
		encoder.call("process_chunk",samples)
		packets.append(encoder.call("encode_chunk",PackedByteArray()))
	for packet in packets:
		peers[0].wire.send_frame(packet);await create_timer(.025).timeout
	await create_timer(.25).timeout
	# End the synthetic utterance so native prebuffering permits its final PCM.
	playback.call("mark_end_opus_stream",true)
	var pcm:=playback.mix_audio(1.0,mini(9600,int(playback.call("queue_length_frames"))))
	for sample in pcm:decoded_energy+=sample.length_squared()
	if not check(received>=8 and decoded_energy>0.1,"Synthetic Opus crosses remote TLS relay and decodes audible PCM"):codec.free();return
	peers[1].channel="";peers[1].wire.tune("planet")
	if not check(await wait_admission(peers[1],"planet"),"Planetary channel switch acknowledged"):codec.free();return
	if not check(await wait_roster(peers[0],peers[1],false) and await wait_roster(peers[1],peers[0],false),"Changing channel removes players from each other's old roster"):codec.free();return
	var before:=received
	for packet in packets.slice(0,4):peers[0].wire.send_frame(packet);await create_timer(.03).timeout
	await create_timer(.2).timeout
	if not check(received==before,"Planetary listener receives no proximity-channel audio"):codec.free();return
	peers[0].channel="";peers[0].wire.tune("planet")
	if not check(await wait_admission(peers[0],"planet"),"Sender switches into matching planetary channel"):codec.free();return
	if not check(await wait_roster(peers[0],peers[1],true) and await wait_roster(peers[1],peers[0],true),"Matching planetary channel restores both roster entries"):codec.free();return
	for packet in packets.slice(0,4):peers[0].wire.send_frame(packet);await create_timer(.03).timeout
	await create_timer(.2).timeout
	check(received>before,"Matching planetary channel delivers voice")
	check("group" not in peers[0].grants and "faction" not in peers[0].grants,"Solo neutral native character cannot access group/faction")
	for denied in ["group","faction"]:
		peers[0].channel="";peers[0].wire.tune(denied)
		if not check(await wait_admission(peers[0],"proximity"),"Unauthorized "+denied+" tune falls back to proximity"):codec.free();return
	peers[0].channel="";peers[0].wire.tune("planet")
	if not check(await wait_admission(peers[0],"planet") and await wait_roster(peers[1],peers[0],true),"Player can return to planetary channel after denied tune"):codec.free();return
	peers[0].wire.shutdown()
	if not check(await wait_roster(peers[1],peers[0],false),"Disconnect immediately removes player from remaining listener roster"):codec.free();return
	if not check(await refresh_presence(),"Native memberships remain valid for reconnect"):codec.free();return
	var renewed:=await request(peers[0].connection,"/voice/session",peers[0].identity)
	if not check(renewed.get("ok",false) and not str(renewed.get("ticket","")).is_empty(),"Reconnect obtains fresh one-use native ticket"):codec.free();return
	peers[0].channel="";peers[0].failed=false;peers[0].roster=[]
	var reconnect: int=peers[0].wire.connect_voice(peers[0].url,peers[0].certificate,str(renewed.ticket));renewed.clear()
	if not check(reconnect==OK and await wait_admission(peers[0],"proximity"),"Disconnected player reconnects with proximity default"):codec.free();return
	peers[0].channel="";peers[0].wire.tune("planet")
	if not check(await wait_admission(peers[0],"planet") and await wait_roster(peers[1],peers[0],true),"Reconnected player rejoins planetary roster"):codec.free();return
	before=received
	for packet in packets.slice(0,4):peers[0].wire.send_frame(packet);await create_timer(.03).timeout
	await create_timer(.2).timeout
	check(received>before,"Reconnected speaker delivers fresh Opus frames")
	peers[0].wire.shutdown()
	check(await wait_roster(peers[1],peers[0],false),"Second disconnect removes reconnected player without ghost membership")
	codec.shutdown();codec.free()
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		var fields:=arg.trim_prefix("--").split("=",true,1)
		if fields.size()==2:options[fields[0]]=fields[1]
	audio_stream=ClassDB.instantiate("AudioStreamOpus")
	audio_stream.set("opus_sample_rate",48000);audio_stream.set("opus_channels",1);audio_stream.set("buffer_length",.25)
	playback=audio_stream.instantiate_playback()
	await exercise()
	for peer in peers:peer.wire.shutdown();peer.wire.queue_free();peer.connection.clear_session()
	playback=null;audio_stream=null
	await process_frame
	var report: Dictionary={"passed":not failed,"checks":checks,"disconnects":disconnects,"events":events,"received_frames":received,"decoded_energy":decoded_energy,"microphone_activated":false,"xr":"off","transport":"actual Godot WSS and Core3 metadata","character_creation":false}
	if options.has("evidence"):
		var file:=FileAccess.open(options.evidence,FileAccess.WRITE)
		if file!=null:file.store_string(JSON.stringify(report,"\t"));file.close()
	print(JSON.stringify({"passed":not failed,"checks":checks.size(),"received_frames":received,"decoded_energy":decoded_energy,"microphone_activated":false,"xr":"off"}))
	quit(1 if failed else 0)
