extends RefCounted
## External Ogg files bypass Godot imports. Workers only construct private audio
## resources; the main thread owns cache publication and every scene/audio player.
const MAX_WORKERS := 2
const MAX_PENDING := 32
const MAX_STREAMS := 32
const MAX_BYTES := 67108864
var cached: Dictionary = {}
var failed: Dictionary = {}
var queued: Array[Dictionary] = []
var workers: Array[Dictionary] = []
var stamp := 0
var bytes := 0
var decoded := 0
var evicted := 0
var dropped := 0
var peak_pending := 0
var decode_max_ms := 0.0

func request(path: String, loop: bool) -> AudioStream:
	var key := path+":"+str(loop)
	if cached.has(key):
		stamp += 1
		cached[key].stamp = stamp
		return cached[key].audio
	if failed.has(key): return null
	for item in queued:
		if item.key==key: return null
	for item in workers:
		if item.key==key: return null
	if queued.size()+workers.size()>=MAX_PENDING:
		dropped += 1
		return null
	queued.append({"key":key,"path":path,"loop":loop})
	peak_pending = maxi(peak_pending,queued.size()+workers.size())
	return null

static func decode(path: String, loop: bool) -> Dictionary:
	var start := Time.get_ticks_usec()
	var audio: AudioStreamOggVorbis
	var size := 0
	var file := FileAccess.open(path,FileAccess.READ)
	if file!=null:
		size = file.get_length()
		if size<=MAX_BYTES:
			audio = AudioStreamOggVorbis.load_from_buffer(file.get_buffer(size))
	if audio!=null: audio.loop = loop
	return {"audio":audio,"bytes":size,"milliseconds":float(Time.get_ticks_usec()-start)/1000.0}

func is_failed(path: String, loop: bool) -> bool:
	return failed.has(path+":"+str(loop))

func poll() -> void:
	for i in range(workers.size()-1,-1,-1):
		var job := workers[i]
		if job.thread.is_alive(): continue
		var result: Dictionary = job.thread.wait_to_finish()
		workers.remove_at(i)
		decode_max_ms = maxf(decode_max_ms,float(result.milliseconds))
		if result.audio==null:
			# Failures are bounded by the same admitted queue and source manifest.
			if failed.size()<MAX_STREAMS*2: failed[job.key] = job.path
			continue
		stamp += 1
		cached[job.key] = {"audio":result.audio,"bytes":int(result.bytes),"stamp":stamp}
		bytes += int(result.bytes)
		decoded += 1
		trim()
	while workers.size()<MAX_WORKERS and not queued.is_empty():
		var job: Dictionary = queued.pop_front()
		var thread := Thread.new()
		var status := thread.start(decode.bind(job.path,job.loop))
		if status!=OK:
			failed[job.key] = job.path
			continue
		job["thread"] = thread
		workers.append(job)

func trim() -> void:
	while cached.size()>MAX_STREAMS or bytes>MAX_BYTES:
		var oldest := ""
		var age := 9223372036854775807
		for key in cached:
			if int(cached[key].stamp)<age: age = cached[key].stamp; oldest = key
		bytes -= int(cached[oldest].bytes)
		cached.erase(oldest)
		evicted += 1

func shutdown() -> void:
	queued.clear()
	for job in workers: job.thread.wait_to_finish()
	workers.clear()
	cached.clear()
	bytes = 0

func statistics() -> Dictionary:
	return {"workers":workers.size(),"pending":queued.size(),"max_workers":MAX_WORKERS,"max_pending":MAX_PENDING,"streams":cached.size(),"max_streams":MAX_STREAMS,"compressed_bytes":bytes,"max_compressed_bytes":MAX_BYTES,"decoded":decoded,"evicted":evicted,"failed":failed.values(),"dropped":dropped,"peak_pending":peak_pending,"decode_max_ms":decode_max_ms,"main_thread_file_decode":false}
