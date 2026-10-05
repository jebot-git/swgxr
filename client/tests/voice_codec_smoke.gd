extends SceneTree
const Codec = preload("res://scripts/voice_codec.gd")
var failures := 0
var assertions := 0
var emitted := 0
func check(ok: bool, label: String) -> void:
	assertions += 1
	if not ok:
		failures += 1
		push_error(label)
func _initialize() -> void:
	call_deferred("run")
func frame(offset: int) -> PackedVector2Array:
	var result := PackedVector2Array()
	result.resize(960)
	for i in range(960):
		var t := float(offset+i)/48000.0
		var value := 0.2*sin(TAU*220.0*t)+0.1*sin(TAU*440.0*t)
		result[i]=Vector2(value,value)
	return result
func run() -> void:
	# Allow Godot AudioServer startup before creating/stopping many players.
	await create_timer(0.05).timeout
	var codec := Codec.new()
	root.add_child(codec)
	check(codec.available,"Pinned native extension loads")
	check(not codec.capture_enabled and not codec.transmitting,"Startup never enables microphone or transmission")
	var encoder := codec.make_encoder(48000,false)
	check(encoder!=null,"Native mono encoder initializes")
	var denoiser := codec.make_encoder(48000,true)
	check(denoiser!=null,"Native RNNoise encoder initializes")
	var packets: Array[PackedByteArray] = []
	var bytes := 0
	var start := Time.get_ticks_usec()
	for index in range(60):
		var pcm := frame(index*960)
		check(int(encoder.call("process_chunk",pcm))==960,"Native consumes exactly20ms")
		var packet: PackedByteArray = encoder.call("encode_chunk",PackedByteArray())
		check(Codec.packet_valid(packet),"Encoded raw Opus mono20ms validates")
		packets.append(packet); bytes+=packet.size()
		if index<4:
			check(int(denoiser.call("process_chunk",pcm))==960,"RNNoise native synthetic processing")
			check(Codec.packet_valid(denoiser.call("encode_chunk",PackedByteArray())),"RNNoise produces Opus")
	var elapsed := Time.get_ticks_usec()-start
	check(bytes<6000,"Encoded rate remains bounded around24kbps")
	# Real native decode and PCM mixing, independent of hardware and AudioServer output.
	var stream: AudioStream = ClassDB.instantiate("AudioStreamOpus")
	stream.set("opus_sample_rate",48000); stream.set("opus_channels",1); stream.set("buffer_length",0.25)
	var playback := stream.instantiate_playback()
	for i in range(4): playback.call("push_opus_packet",packets[i],0,0)
	check(int(playback.call("queue_length_frames"))==3840,"Native Opus decodes960samples per packet")
	playback.call("mark_end_opus_stream",true)
	var decoded := playback.mix_audio(1.0,2880)
	var energy := 0.0
	var finite := true
	for sample in decoded:
		finite = finite and sample.is_finite()
		energy+=sample.length_squared()
	check(finite,"All decoded PCM samples finite")
	check(energy>1.0,"Real compressed fixture decodes audible nonzeroPCM")
	codec.encoded_frame.connect(func(_packet:PackedByteArray): emitted+=1)
	codec.encode_pcm(frame(0)); check(emitted==0,"No capture means no send")
	# Inject synthetic encoder state; never call capture activation or a real input device.
	codec._encoder=encoder; codec.capture_enabled=true
	codec.encode_pcm(frame(0)); check(emitted==0,"Enabled capture with PTT released cannot send")
	codec.transmitting=true
	codec.encode_pcm(frame(960)); check(emitted==1,"Explicit synthetic PTT emits a packet")
	codec.capture_enabled=false; codec.transmitting=false; codec._encoder=null
	for i in [0,2,1,3]: codec.push_frame("alice",i,packets[i],false,Vector3.ZERO)
	check(codec.speakers.alice.pending.size()==4,"Sequence zero and out-of-order packets accepted")
	var entry: Dictionary = codec.speakers.alice
	for i in range(4): check(codec._decode_one(entry,Time.get_ticks_msec()),"Reorder decoder advances")
	check(entry.next==4 and codec._queued(entry)==3840,"Reordering outputs contiguous80ms before playback")
	codec.push_frame("alice",3,packets[3],false,Vector3.ZERO)
	check(entry.pending.is_empty(),"Old replay rejected")
	codec.push_frame("alice",5,packets[5],false,Vector3.ZERO)
	check(not codec._decode_one(entry,Time.get_ticks_msec()),"Missing packet gets bounded reordering grace")
	entry.pending[5].received_ms-=45
	check(codec._decode_one(entry,Time.get_ticks_msec()) and codec.concealed_frames==1,"Missing packet handled by native FEC/PLC")
	check(codec._decode_one(entry,Time.get_ticks_msec()) and entry.next==6,"Following packet decodes after concealment")
	for i in range(20): codec.push_frame("alice",6+i,packets[i],false,Vector3.ZERO)
	check(codec.speakers.alice.pending.size()+codec._queued(codec.speakers.alice)/960<=12,"Overflow cannot retain more than240ms")
	check(codec.get_child_count()==1,"Overflow frees native speaker immediately")
	for i in range(12): codec.push_frame("speaker%d"%i,0,packets[0],false,Vector3.ZERO)
	check(codec.speakers.size()==8 and codec.get_child_count()==8,"Speaker and native decoder cap enforced")
	codec.clear_speakers()
	codec.push_frame("short",0,packets[0],false,Vector3.ZERO)
	entry=codec.speakers.short
	entry.first_ms-=110; entry.last_ms-=110
	codec._process(0.02)
	check(entry.started and entry.ended,"Short utterance starts and receives bounded tail marker")
	codec.push_frame("short",0,packets[0],false,Vector3.ZERO)
	check(codec.speakers.short==entry,"Replay cannot reset ended stream")
	entry.last_ms-=3100; codec._process(0.02)
	check(codec.speakers.is_empty(),"Idle decoders cleaned up")
	var oversized := PackedByteArray(); oversized.resize(401)
	check(not Codec.packet_valid(oversized) and not Codec.packet_valid(PackedByteArray()),"Packet length bounds")
	check(not Codec.packet_valid(PackedByteArray([0])) and not Codec.packet_valid(PackedByteArray([252])),"Non20ms or stereo TOC rejected")
	codec.shutdown(); codec.free()
	print(JSON.stringify({"suite":"voice_codec_native","checks":assertions,"failures":failures,"encoded_bytes":bytes,"duration_seconds":1.2,"native_encode_fixture_usec":elapsed,"decoded_energy":energy,"microphone_activated":false,"renderer":"headless dummy; no XR/GPU validation"}))
	await create_timer(0.5).timeout
	call_deferred("quit",1 if failures else 0)
