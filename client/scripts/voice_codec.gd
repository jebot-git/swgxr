extends Node
## Pinned TwoVoIP native DSP; wire payload is raw Opus, without helper prefixes.
## Microphone activation requires an explicit set_capture_enabled(true) call.
signal encoded_frame(payload: PackedByteArray)
const RATE := 48000
const FRAME := 960
const MAX_PACKET := 400
const MAX_SPEAKERS := 8
const MAX_QUEUED := 12 # 240ms, across compressed and native PCM queues.
const PREFILL := 4 # 80ms.
const FRAME_BUDGET_USEC := 2500
var volume := 1.0
var level := 0.0
var available := false
var status := "Voice codec is not initialized."
var capture_enabled := false
var transmitting := false
var speakers: Dictionary = {}
var _encoder: RefCounted
var _input_chunk := FRAME
var _input_rate := RATE
var _speaker_cursor := 0
var _now_ms := 0
var dropped_frames := 0
var concealed_frames := 0
var _capture_retry_after_ms := 0
var input_preferences = preload("res://audio/input_preferences.gd").new()
var _device_clock := 0.0
var _effective_input := ""

func _ready() -> void:
	input_preferences.load_preferences()
	refresh_input_device()
	available = ClassDB.class_exists("TwovoipOpusEncoder") and ClassDB.class_exists("AudioStreamOpus")
	status = "Microphone off." if available else "Install the pinned TwoVoIP voice codec."

func make_encoder(input_rate: int, denoise := true) -> RefCounted:
	if not ClassDB.class_exists("TwovoipOpusEncoder"): return null
	var result: RefCounted = ClassDB.instantiate("TwovoipOpusEncoder")
	# Upstream enum values: RNNoise=2, disabled=0; AGC disabled=0.
	if result.call("initialize", input_rate, RATE, 1, 2 if denoise else 0, 0, FRAME) != OK: return null
	if not result.call("create_opus_encoder", 24000, 5, true): return null
	return result

func _drop_input() -> void:
	var count := mini(AudioServer.get_input_frames_available(), AudioServer.get_input_buffer_length_frames())
	if count > 0: AudioServer.get_input_frames(count)

func set_capture_enabled(enabled: bool) -> void:
	if not enabled:
		transmitting = false
		if capture_enabled: AudioServer.set_input_device_active(false)
		capture_enabled = false; _encoder = null; level = 0.0
		status = "Microphone off."
		return
	if capture_enabled: return
	if Time.get_ticks_msec() < _capture_retry_after_ms: return
	_capture_retry_after_ms = Time.get_ticks_msec()+2000
	if not available:
		status = "The native voice codec is unavailable."
		return
	var error := AudioServer.set_input_device_active(true)
	if error != OK:
		# Some drivers mark input active before opening it; reset before retry.
		AudioServer.set_input_device_active(false)
		status = "Microphone could not be activated: " + error_string(error)
		return
	_input_rate = int(AudioServer.get_input_mix_rate())
	_encoder = make_encoder(_input_rate)
	if _encoder == null:
		AudioServer.set_input_device_active(false)
		status = "Native RNNoise/Opus initialization failed."
		return
	_input_chunk = int(_encoder.call("get_required_input_chunk_size"))
	capture_enabled = true; _drop_input()
	status = "Microphone enabled; hold push-to-talk."

func set_transmitting(enabled: bool) -> void:
	var next := enabled and capture_enabled and _encoder != null
	if next == transmitting: return
	flush_transmit()
	transmitting = next and _encoder != null
	status = "Transmitting voice." if transmitting else ("Microphone enabled; hold push-to-talk." if capture_enabled else "Microphone off.")

func flush_transmit() -> void:
	# Discard captured pre-PTT/channel audio, including RNNoise history.
	if capture_enabled:
		_drop_input()
		_encoder = make_encoder(_input_rate)
		if _encoder == null:
			set_capture_enabled(false)
			status = "Native voice codec reset failed."

func set_input_device(device: String) -> void:
	input_preferences.device = device
	refresh_input_device()

func refresh_input_device() -> void:
	var device: String = input_preferences.effective_device(AudioServer.get_input_device_list())
	if device == _effective_input: return
	# Tear down the encoder and discard buffered samples before changing inputs.
	# Voice orchestration alone decides whether capture/transmission can resume.
	set_capture_enabled(false)
	AudioServer.input_device = device
	_effective_input = device
	_capture_retry_after_ms = 0

static func packet_valid(payload: PackedByteArray) -> bool:
	if payload.is_empty() or payload.size() > MAX_PACKET: return false
	var toc := int(payload[0])
	if (toc & 4) != 0: return false # Fixed mono wire contract.
	var config := toc >> 3
	var samples: int
	if config < 12: samples = [480,960,1920,2880][config & 3]
	elif config < 16: samples = [480,960][config & 1]
	else: samples = [120,240,480,960][config & 3]
	var count := 1
	match toc & 3:
		1, 2: count = 2
		3:
			if payload.size() < 2: return false
			count = int(payload[1]) & 63
	return count > 0 and samples * count == FRAME

func _new_speaker(id: String, spatial: bool, point: Vector3, sequence: int) -> Dictionary:
	var stream: AudioStream = ClassDB.instantiate("AudioStreamOpus")
	stream.set("opus_sample_rate", RATE); stream.set("opus_channels", 1); stream.set("buffer_length", 0.25)
	var player: Node = AudioStreamPlayer3D.new() if spatial else AudioStreamPlayer.new()
	player.set("stream", stream); add_child(player)
	if spatial:
		player.set("top_level", true); player.set("global_position", point)
		player.set("max_distance", 64.0); player.set("unit_size", 5.0)
	player.set("volume_db", linear_to_db(clampf(volume,0.0001,1.0)))
	player.call("play")
	var playback: RefCounted = player.call("get_stream_playback")
	var entry := {"node":player,"playback":playback,"spatial":spatial,"pending":{},"next":sequence,
		"first_ms":_now_ms,"last_ms":_now_ms,"started":false,"ended":false,"decoded":0}
	speakers[id] = entry
	return entry

func push_frame(speaker_id: String, sequence: int, payload: PackedByteArray, spatial: bool, point: Vector3) -> void:
	if not available or speaker_id.is_empty() or speaker_id.length()>64 or sequence<0 or not point.is_finite() or not packet_valid(payload):
		dropped_frames += 1; return
	_now_ms = Time.get_ticks_msec()
	var entry: Dictionary = speakers.get(speaker_id,{})
	if not entry.is_empty() and (sequence<int(entry.next) or entry.pending.has(sequence)):
		dropped_frames += 1; return
	if not entry.is_empty() and (entry.spatial != spatial or entry.ended or sequence-int(entry.next)>=MAX_QUEUED):
		remove_speaker(speaker_id); entry = {}
	if entry.is_empty():
		if speakers.size() >= MAX_SPEAKERS:
			dropped_frames += 1; return
		entry = _new_speaker(speaker_id, spatial, point, sequence)
	if sequence < int(entry.next) or entry.pending.has(sequence):
		dropped_frames += 1; return
	var queued: int = _queued(entry)/FRAME + entry.pending.size()
	if queued >= MAX_QUEUED:
		# Resume near real time; never build a seconds-long voice backlog.
		remove_speaker(speaker_id)
		entry = _new_speaker(speaker_id, spatial, point, sequence)
		dropped_frames += 1
	entry.pending[sequence] = {"data":payload,"received_ms":_now_ms}
	entry.last_ms = _now_ms
	if spatial: entry.node.global_position = point

func _queued(entry: Dictionary) -> int:
	# Upstream PCM ring indices are shared with Godot's mixer thread.
	AudioServer.lock()
	var result := int(entry.playback.call("queue_length_frames"))
	AudioServer.unlock()
	return result

func _mark_end(entry: Dictionary, clear_mark: bool) -> void:
	AudioServer.lock()
	entry.playback.call("mark_end_opus_stream",clear_mark)
	AudioServer.unlock()

func _decode_one(entry: Dictionary, now: int) -> bool:
	if entry.pending.is_empty() or _queued(entry)>=MAX_QUEUED*FRAME-FRAME: return false
	var packet: PackedByteArray
	var fec := 0
	if entry.pending.has(entry.next):
		packet = entry.pending[entry.next].data; entry.pending.erase(entry.next)
	else:
		var keys: Array = entry.pending.keys(); keys.sort()
		var earliest: Dictionary = entry.pending[keys[0]]
		if now-int(earliest.received_ms)<40: return false
		packet = earliest.data; fec = 1; concealed_frames += 1
	AudioServer.lock()
	var before := int(entry.playback.call("queue_length_frames"))
	entry.playback.call("push_opus_packet",packet,0,fec)
	var after := int(entry.playback.call("queue_length_frames"))
	AudioServer.unlock()
	entry.next = int(entry.next)+1
	if after <= before:
		dropped_frames += 1 # Malformed entropy payload rejected by native Opus.
	entry.decoded = int(entry.decoded)+1
	return true

func _process(_delta: float) -> void:
	_device_clock += _delta
	if _device_clock >= 1.0:
		_device_clock = 0.0
		refresh_input_device()
	if not available: return
	var start := Time.get_ticks_usec()
	_now_ms = Time.get_ticks_msec()
	if capture_enabled and _encoder != null:
		var count := AudioServer.get_input_frames_available()
		if count > _input_chunk*MAX_QUEUED:
			AudioServer.get_input_frames(count-_input_chunk*2)
			dropped_frames += 1
		for _frame in range(2):
			if Time.get_ticks_usec()-start>=FRAME_BUDGET_USEC: break
			var pcm := AudioServer.get_input_frames(_input_chunk)
			if pcm.is_empty(): break
			encode_pcm(pcm)
	var ids: Array = speakers.keys()
	for index in range(ids.size()):
		var id: String = ids[(_speaker_cursor+index)%ids.size()]
		var entry: Dictionary = speakers[id]
		entry.node.volume_db = linear_to_db(clampf(volume,0.0001,1.0))
		if _now_ms-int(entry.last_ms)>3000:
			remove_speaker(id); continue
		for _frame in range(2):
			if Time.get_ticks_usec()-start>=FRAME_BUDGET_USEC or not _decode_one(entry,_now_ms): break
		var queued := _queued(entry)
		if not entry.started and (queued>=FRAME*PREFILL or (_now_ms-int(entry.first_ms)>=100 and queued>0)):
			_mark_end(entry,true); entry.started=true
		if entry.pending.is_empty() and _now_ms-int(entry.last_ms)>=100 and not entry.ended:
			_mark_end(entry,false); entry.ended=true
	if not ids.is_empty(): _speaker_cursor=(_speaker_cursor+1)%ids.size()

func encode_pcm(pcm: PackedVector2Array) -> void:
	# Also accepts synthetic frames in tests; never starts hardware capture.
	if not capture_enabled or _encoder == null: return
	if int(_encoder.call("process_chunk",pcm))<0: return
	level = clampf(float(_encoder.call("get_rms")),0.0,1.0)
	if not transmitting: return
	var packet: PackedByteArray = _encoder.call("encode_chunk",PackedByteArray())
	if packet_valid(packet): encoded_frame.emit(packet)
	else: dropped_frames += 1

func remove_speaker(speaker_id: String) -> void:
	if not speakers.has(speaker_id): return
	var entry: Dictionary = speakers[speaker_id]
	entry.node.call("stop"); entry.node.free()
	entry.clear()
	speakers.erase(speaker_id)

func clear_speakers() -> void:
	for id: String in speakers.keys(): remove_speaker(id)

func shutdown() -> void:
	set_capture_enabled(false); clear_speakers()

func _exit_tree() -> void:
	shutdown()
