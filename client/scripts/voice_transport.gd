extends Node
## Bounded encrypted prototype voice transport; no login credentials in URLs/logs.
signal control_received(message: Dictionary)
signal frame_received(epoch: int, sequence: int, speaker: String, point: Vector3, payload: PackedByteArray)
signal disconnected(message: String)
var socket: WebSocketPeer
var ticket := ""
var hello_sent := false
var admitted := false
var deadline := 0.0
var epoch := 0
var sequence := 0
var dropped_frames := 0
var last_poll := 0.0
const MAX_FRAME := 400

func connect_voice(url: String, certificate: X509Certificate, one_use_ticket: String) -> Error:
	shutdown()
	if not url.begins_with("wss://") and not url.begins_with("ws://127.0.0.1:"):
		return ERR_INVALID_PARAMETER
	if url.begins_with("wss://") and certificate == null: return ERR_INVALID_PARAMETER
	if one_use_ticket.is_empty() or one_use_ticket.length()>2048: return ERR_INVALID_PARAMETER
	socket=WebSocketPeer.new()
	socket.inbound_buffer_size=65536
	socket.outbound_buffer_size=8192
	socket.max_queued_packets=128
	# Godot may send its first automatic ping immediately when the engine has
	# already been running for this interval. Admission requires hello first.
	socket.heartbeat_interval=0.0
	ticket=one_use_ticket
	deadline=Time.get_ticks_msec()/1000.0+10.0
	last_poll=Time.get_ticks_msec()/1000.0
	var result:=socket.connect_to_url(url,TLSOptions.client(certificate) if certificate else null)
	if result!=OK: shutdown()
	return result

func _process(_delta: float) -> void:
	if socket==null:return
	var now:=Time.get_ticks_msec()/1000.0
	# TCP retransmission can delay voice. Do not play a backlog after a frame stall.
	if admitted and now-last_poll>0.5:
		fail("Voice paused after a client stall; reconnecting.");return
	last_poll=now
	socket.poll()
	var state:=socket.get_ready_state()
	if state==WebSocketPeer.STATE_CLOSED:
		fail("Voice connection closed.");return
	if not admitted and now>deadline:
		fail("Voice connection timed out.");return
	if state!=WebSocketPeer.STATE_OPEN:return
	if not hello_sent:
		socket.set_no_delay(true)
		hello_sent=true
		var result:=socket.send_text(JSON.stringify({"type":"hello","ticket":ticket}))
		ticket=""
		if result!=OK:fail("Voice admission failed.");return
	if socket.get_available_packet_count()>96:
		fail("Voice receive queue exceeded its latency budget.");return
	for _index in range(32):
		if socket==null or socket.get_available_packet_count()==0:break
		var data:=socket.get_packet()
		if socket.was_string_packet():
			if data.size()>16384:fail("Voice control message too large.");return
			var parsed: Variant=JSON.parse_string(data.get_string_from_utf8())
			if not parsed is Dictionary:fail("Invalid voice control message.");return
			if parsed.get("type","") in ["hello","tuned"]:
				var next_epoch: Variant=parsed.get("epoch")
				if not (next_epoch is int or next_epoch is float) or float(next_epoch)!=floorf(float(next_epoch)) or int(next_epoch)<=0 or int(next_epoch)>0xffffffff:
					fail("Invalid voice channel epoch.");return
				epoch=int(next_epoch);sequence=0;admitted=true
				socket.heartbeat_interval=5.0
			control_received.emit(parsed)
		else:
			if not admitted or data.size()<29 or data.size()>28+MAX_FRAME:continue
			var packet_epoch:=int(data.decode_u32(0))
			if packet_epoch!=epoch:continue
			var point:=Vector3(data.decode_float(16),data.decode_float(20),data.decode_float(24))
			if not point.is_finite() or point.length()>35000:continue
			var speaker:=str(data.decode_u64(8))
			if speaker=="0":continue
			frame_received.emit(packet_epoch,int(data.decode_u32(4)),speaker,point,data.slice(28))

func tune(channel: String) -> bool:
	if not admitted or socket==null or channel not in ["proximity","group","planet","sector","faction"]:return false
	return socket.send_text(JSON.stringify({"type":"tune","channel":channel}))==OK

func send_frame(payload: PackedByteArray) -> bool:
	if not admitted or socket==null or payload.is_empty() or payload.size()>MAX_FRAME:return false
	if socket.get_current_outbound_buffered_amount()>4096:
		dropped_frames+=1
		fail("Voice send queue exceeded its latency budget.");return false
	if sequence>=0xfffffffe:fail("Voice sequence renewed.");return false
	var packet:=PackedByteArray();packet.resize(8)
	packet.encode_u32(0,epoch);packet.encode_u32(4,sequence);sequence+=1
	packet.append_array(payload)
	return socket.put_packet(packet)==OK

func fail(message: String) -> void:
	shutdown();disconnected.emit(message)

func shutdown() -> void:
	if socket!=null:socket.close(-1)
	socket=null;ticket="";hello_sent=false;admitted=false;epoch=0;sequence=0

func _exit_tree() -> void:shutdown()
