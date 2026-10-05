extends SceneTree
const Store = preload("res://scripts/credential_store.gd")
const ORIGIN := "https://example.invalid:18443"
const PASSWORD := " synthetic 🔑\nfixture password \n"
class FakeStore:
	extends "res://scripts/credential_store.gd"
	var seen_arguments: Array[PackedStringArray] = []
	var spawn_count := 0
	func _ready() -> void:
		available=true; status="Synthetic test keyring."
	func _spawn(args: PackedStringArray) -> Dictionary:
		seen_arguments.append(args); spawn_count+=1
		var command := PackedStringArray([ProjectSettings.globalize_path("res://tests/fixtures/credential_secret_tool.py")])
		command.append_array(args)
		return OS.execute_with_pipe("/usr/bin/python3",command,false)
var checks := 0
var failures := 0
var results: Dictionary = {}
func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok:
		failures+=1; push_error(message)
func _initialize() -> void: call_deferred("run")
func result_for(id: int) -> Dictionary:
	var until := Time.get_ticks_msec()+2500
	while not results.has(id) and Time.get_ticks_msec()<until:
		await process_frame
	if not results.has(id):
		check(false,"Credential request completed within fixture deadline")
		return {"ok":false,"found":false,"message":"Fixture timeout"}
	var result: Dictionary = results[id]; results.erase(id)
	return result
func run() -> void:
	check(Store.valid_key(ORIGIN,"alice"),"Valid exact origin/account")
	for origin in ["http://example.invalid","https://user:pass@example.invalid","https://example.invalid/","https://example.invalid?token=x","https://example.invalid:99999","https://example.invalid\n"]:
		check(not Store.valid_key(origin,"alice"),"Invalid credential origin rejected")
	for account in ["Alice","a"," alice","a\nb","user/name"]:
		check(not Store.valid_key(ORIGIN,account),"Noncanonical account rejected")
	check(Store.valid_password(PASSWORD),"Exact Unicode/newline fixture password accepted")
	var store := FakeStore.new(); root.add_child(store)
	store.completed.connect(func(id:int,_operation:String,value:Dictionary): results[id]=value)
	var result: Dictionary = await result_for(store.store_password(ORIGIN,"alice",PASSWORD))
	check(result.ok,"Password passes only via pipe; EOF completes store")
	check(not result.has("password"),"Store acknowledgement excludes secret")
	result=await result_for(store.load_password(ORIGIN,"alice"))
	check(result.ok and result.found and result.password==PASSWORD,"Lookup preserves exact bytes including surrounding whitespace")
	check(not str(store.seen_arguments).contains(PASSWORD),"Password excluded from process arguments")
	result=await result_for(store.delete_password(ORIGIN,"alice"))
	check(result.ok and not result.found,"Delete completes")
	result=await result_for(store.load_password(ORIGIN,"missing"))
	check(result.ok and not result.found,"Absent lookup is distinguished from failure")
	result=await result_for(store.load_password(ORIGIN,"error"))
	check(not result.ok and not str(result).contains(PASSWORD),"Child stderr is redacted")
	result=await result_for(store.load_password(ORIGIN,"overflow"))
	check(not result.ok and not result.has("password"),"Oversized output rejected")
	result=await result_for(store.load_password(ORIGIN,"badutf"))
	check(not result.ok and not result.has("password"),"Invalid UTF8 rejected without decoding/logging")
	var count := store.spawn_count
	result=await result_for(store.load_password("https://example.invalid/path","alice"))
	check(not result.ok and store.spawn_count==count,"Invalid origin never spawns a process")
	var id := store.load_password(ORIGIN,"hang")
	await process_frame
	check(store.busy and not store._process_info.is_empty(),"Long keyring request remains nonblocking")
	var pid := int(store._process_info.pid)
	store._deadline_ms=Time.get_ticks_msec()-1
	result=await result_for(id)
	check(not result.ok and str(result.message).contains("timed out"),"Timeout has actionable redacted result")
	check(not FileAccess.file_exists("/proc/%d/status"%pid),"Timeout kills child")
	id=store.load_password(ORIGIN,"hang")
	await process_frame
	pid=int(store._process_info.pid)
	var queued_id := store.store_password(ORIGIN,"alice",PASSWORD)
	count=store.spawn_count
	store.cancel_context()
	await create_timer(0.03).timeout
	check(not store.busy and not results.has(id) and not results.has(queued_id),"Context cancellation suppresses queued/inflight responses")
	check(not FileAccess.file_exists("/proc/%d/status"%pid) and store.spawn_count==count,"Cancellation kills child and clears queued store without spawning")
	# Errors are also deferred/fenced, so old-form replies cannot populate a new form.
	id=store.load_password("bad","alice"); store.cancel_context()
	await process_frame
	check(not results.has(id),"Deferred failure is canceled with context")
	# Queue cap retains at most four passwords/operations awaiting one child.
	var ids: Array[int]=[]
	for i in range(6): ids.append(store.load_password(ORIGIN,"missing"))
	check(store._queue.size()==4,"Pending operation memory is bounded")
	for index in range(ids.size()):
		result=await result_for(ids[index])
		check(result.ok if index<4 else not result.ok,"Serialized operations and overload errors complete")
	store.cancel_context(); store.free()
	print(JSON.stringify({"suite":"credential_store_fake_process","checks":checks,"failures":failures,"real_keyring_used":false,"passwords_logged":false}))
	call_deferred("quit",1 if failures else 0)
