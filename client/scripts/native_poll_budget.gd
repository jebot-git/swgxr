extends RefCounted
## Fair admission for optional one-shot status reads; never queues a UI action.
var waiting: Dictionary={}
var last_seen: Dictionary={}
var last_grant_ms: int=-100000
var interval_ms:=3000
func reset() -> void:
	waiting.clear();last_seen.clear();last_grant_ms=-100000
func admit(family: String, now_ms: int, occupied: bool) -> bool:
	for key in waiting.keys():
		if now_ms-int(last_seen.get(key,now_ms))>1500:forget(str(key))
	last_seen[family]=now_ms
	if not waiting.has(family):waiting[family]=now_ms
	if occupied or now_ms-last_grant_ms<interval_ms:return false
	var oldest: String=str(waiting.keys()[0])
	for key: String in waiting:
		if int(waiting[key])<int(waiting[oldest]):oldest=key
	if family!=oldest:return false
	forget(family);last_grant_ms=now_ms
	return true
func forget(family: String) -> void:
	waiting.erase(family);last_seen.erase(family)
