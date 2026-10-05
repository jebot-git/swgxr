extends Node
## Linux Secret Service adapter. Passwords travel only through child process pipes.
## No credentials, session tokens, or raw child diagnostics are written to disk/logs.
signal completed(request_id: int, operation: String, result: Dictionary)
const APPLICATION := "swgxr"
const EXECUTABLE := "/usr/bin/secret-tool"
const TIMEOUT_MS := 10000
const MAX_SECRET_BYTES := 512
const MAX_DIAGNOSTIC_BYTES := 4096
const MAX_PENDING := 4
var available := false
var status := "Credential store is not initialized."
var busy: bool:
	get: return not _active.is_empty() or not _queue.is_empty()
var _queue: Array[Dictionary] = []
var _active: Dictionary = {}
var _process_info: Dictionary = {}
var _output := PackedByteArray()
var _stderr_count := 0
var _serial := 0
var _epoch := 0
var _deadline_ms := 0

func _ready() -> void:
	available = OS.get_name() == "Linux" and FileAccess.file_exists(EXECUTABLE)
	status = "Passwords can be saved in your OS keyring." if available else "Password remembering requires Linux Secret Service and secret-tool."

static func valid_key(origin: String, account: String) -> bool:
	if origin.length()>512 or account.length()>24: return false
	var expression := RegEx.new()
	expression.compile("^[a-z][a-z0-9_]{2,23}$")
	if expression.search(account)==null: return false
	expression.compile("^https://(?:\\[[0-9A-Fa-f:]+\\]|[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?)(?::([0-9]{1,5}))?$")
	var matched := expression.search(origin)
	if matched==null or matched.get_string(0)!=origin: return false
	var port := matched.get_string(1)
	return port.is_empty() or (int(port)>=1 and int(port)<=65535)

static func valid_password(password: String) -> bool:
	return password.length()>=12 and password.length()<=128 and password.to_utf8_buffer().size()<=MAX_SECRET_BYTES and _valid_utf8(password.to_utf8_buffer())

static func _valid_utf8(bytes: PackedByteArray) -> bool:
	# Validate before Godot decoding, which otherwise logs malformed input bytes.
	var index := 0
	while index<bytes.size():
		var first := int(bytes[index])
		if first==0: return false
		if first<128:
			index+=1; continue
		var count := 0
		var low := 128
		var high := 191
		if first>=194 and first<=223: count=1
		elif first>=224 and first<=239:
			count=2
			if first==224: low=160
			if first==237: high=159 # Surrogates are not Unicode scalar values.
		elif first>=240 and first<=244:
			count=3
			if first==240: low=144
			if first==244: high=143
		else: return false
		if index+count>=bytes.size(): return false
		if bytes[index+1]<low or bytes[index+1]>high: return false
		for offset in range(2,count+1):
			if bytes[index+offset]<128 or bytes[index+offset]>191: return false
		index+=count+1
	return true

func load_password(origin: String, account: String) -> int:
	return _enqueue("load",origin,account,"")

func store_password(origin: String, account: String, password: String) -> int:
	return _enqueue("store",origin,account,password)

func delete_password(origin: String, account: String) -> int:
	return _enqueue("delete",origin,account,"")

func _enqueue(operation: String, origin: String, account: String, password: String) -> int:
	_serial+=1
	var id := _serial
	var error := ""
	if not available: error=status
	elif not valid_key(origin,account): error="Cannot save credentials for an invalid HTTPS server or account."
	elif operation=="store" and not valid_password(password): error="This password cannot be represented safely in the OS keyring."
	elif _queue.size()>=MAX_PENDING: error="The OS keyring is busy. Please try again."
	if not error.is_empty():
		_deliver.call_deferred(id,operation,{"ok":false,"found":false,"message":error},_epoch)
	else:
		_queue.append({"id":id,"operation":operation,"origin":origin,"account":account,"password":password,"epoch":_epoch})
	return id

func _arguments(request: Dictionary) -> PackedStringArray:
	var args := PackedStringArray()
	match request.operation:
		"store": args.append_array(["store","--label=SWGXR account password"])
		"load": args.append("lookup")
		"delete": args.append("clear")
	args.append_array(["application",APPLICATION,"origin",request.origin,"account",request.account])
	return args

func _spawn(args: PackedStringArray) -> Dictionary:
	return OS.execute_with_pipe(EXECUTABLE,args,false)

func _start_next() -> void:
	if _queue.is_empty(): return
	_active=_queue.pop_front()
	_process_info=_spawn(_arguments(_active))
	_output.clear(); _stderr_count=0; _deadline_ms=Time.get_ticks_msec()+TIMEOUT_MS
	if _process_info.is_empty():
		_finish({"ok":false,"found":false,"message":"The OS keyring helper could not start."}); return
	if _active.operation=="store":
		# ≤512 bytes is below Linux PIPE_BUF: one nonblocking write is atomic.
		var bytes: PackedByteArray = str(_active.password).to_utf8_buffer()
		var io: FileAccess = _process_info.stdio
		io.store_buffer(bytes)
		var success := io.get_error()==OK
		bytes.fill(0); bytes.clear(); _active.erase("password")
		# secret-tool store reads until EOF and has no successful stdout payload.
		# stderr has its own pipe and remains available after closing stdin/stdout.
		io.close(); _process_info.erase("stdio")
		if not success: _abort("The password could not be passed to the OS keyring.")
	else:
		_active.erase("password")

func _read_outputs() -> bool:
	if _process_info.has("stderr"):
		var diagnostics: FileAccess = _process_info.stderr
		var count := int(diagnostics.get_length())
		if count+_stderr_count>MAX_DIAGNOSTIC_BYTES:
			_abort("The OS keyring returned an invalid response."); return false
		if count>0:
			# Do not decode, retain, log, or surface child stderr: it may contain secrets.
			var discarded := diagnostics.get_buffer(count)
			_stderr_count+=discarded.size(); discarded.fill(0)
	if _process_info.has("stdio"):
		var io: FileAccess = _process_info.stdio
		var count := int(io.get_length())
		if count+_output.size()>MAX_SECRET_BYTES:
			_abort("The OS keyring returned an invalid response."); return false
		if count>0: _output.append_array(io.get_buffer(count))
	return true

func _process(_delta: float) -> void:
	if _active.is_empty(): _start_next()
	if _active.is_empty(): return
	if Time.get_ticks_msec()>=_deadline_ms:
		_abort("The OS keyring timed out. Unlock it and try again."); return
	if not _read_outputs(): return
	var pid := int(_process_info.pid)
	if OS.is_process_running(pid): return
	# Read once more after child exit to drain bytes written just before termination.
	if not _read_outputs(): return
	var code := OS.get_process_exit_code(pid)
	var operation: String = _active.operation
	if code==0:
		if operation=="load":
			if not _valid_utf8(_output):
				_finish({"ok":false,"found":false,"message":"The saved password is invalid. Enter it again."}); return
			var password := _output.get_string_from_utf8()
			if password.to_utf8_buffer()!=_output or not valid_password(password):
				_finish({"ok":false,"found":false,"message":"The saved password is invalid. Enter it again."})
			else:
				_finish({"ok":true,"found":true,"password":password,"message":"Password loaded from the OS keyring."})
		else:
			_finish({"ok":true,"found":false,"message":"Password saved in the OS keyring." if operation=="store" else "Saved password removed from the OS keyring."})
	elif code==1 and _stderr_count==0 and _output.is_empty() and operation in ["load","delete"]:
		_finish({"ok":true,"found":false,"message":"No saved password for this server and account."})
	else:
		_finish({"ok":false,"found":false,"message":"The OS keyring is unavailable or locked. Unlock it and try again."})

func _abort(message: String) -> void:
	_kill_child()
	_finish({"ok":false,"found":false,"message":message})

func _kill_child() -> void:
	var pid := int(_process_info.get("pid",-1))
	if pid>0 and OS.is_process_running(pid): OS.kill(pid)

func _close_pipes() -> void:
	for name in ["stdio","stderr"]:
		if _process_info.has(name): _process_info[name].close()
	_process_info.clear()
	_output.fill(0); _output.clear(); _stderr_count=0

func _finish(result: Dictionary) -> void:
	var request := _active
	_active={}; _close_pipes()
	status=str(result.message)
	_deliver.call_deferred(int(request.id),str(request.operation),result,int(request.epoch))
	request.clear()

func _deliver(id: int, operation: String, result: Dictionary, epoch: int) -> void:
	if epoch==_epoch: completed.emit(id,operation,result)

func cancel_context() -> void:
	_epoch+=1
	for request in _queue: request.clear()
	_queue.clear(); _kill_child(); _close_pipes(); _active.clear()

func _exit_tree() -> void:
	cancel_context()
