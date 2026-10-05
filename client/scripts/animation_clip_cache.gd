extends RefCounted
## Shared Animation resources are immutable after publication. Players/libraries
## retain independent playback state. Keys cover imported content and bind policy.
const MAX_CLIPS := 256
const MAX_TRACK_KEYS := 500000
static var entries := {}
static var serial := 0
static var hits := 0
static var misses := 0
static var evictions := 0
static var total_track_keys := 0

static func digest(value: Variant) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(var_to_bytes(value))
	return hash.finish().hex_encode()

static func key(clip_name: String, clip: Dictionary, skeleton_key: String) -> String:
	return digest(["original_clip_v1_root_xz_rest_jump_y_clamp",clip_name,skeleton_key,clip])

static func find(cache_key: String) -> Animation:
	serial += 1
	if not entries.has(cache_key):
		misses += 1
		return null
	hits += 1
	entries[cache_key].used = serial
	return entries[cache_key].animation

static func publish(cache_key: String, animation: Animation) -> void:
	var count := 0
	for track in range(animation.get_track_count()): count += animation.track_get_key_count(track)
	if count>MAX_TRACK_KEYS: return
	while not entries.is_empty() and (entries.size()>=MAX_CLIPS or total_track_keys+count>MAX_TRACK_KEYS):
		var oldest: String = entries.keys()[0]
		for candidate in entries:
			if entries[candidate].used<entries[oldest].used: oldest = candidate
		total_track_keys -= int(entries[oldest].keys)
		entries.erase(oldest)
		evictions += 1
	serial += 1
	entries[cache_key] = {"animation":animation,"used":serial,"keys":count}
	total_track_keys += count

static func statistics() -> Dictionary:
	return {"hits":hits,"misses":misses,"resident_clips":entries.size(),"resident_track_keys":total_track_keys,"evictions":evictions,"max_clips":MAX_CLIPS,"max_track_keys":MAX_TRACK_KEYS}

static func clear() -> void:
	entries.clear()
	serial = 0; hits = 0; misses = 0; evictions = 0; total_track_keys = 0
