extends RefCounted
## Portable, revocable saved logins. Never stores passwords or gameplay sessions.
const MAX_BYTES:=65536
const MAX_ENTRIES:=32
var path:="user://remembered_logins.json"
static func valid_key(origin:String,account:String)->bool:
	return preload("res://scripts/credential_store.gd").valid_key(origin,account)
static func valid_token(token:Variant)->bool:
	if not token is String:return false
	var expression:=RegEx.new();expression.compile("^swgr_[A-Za-z0-9_-]{43}$")
	return expression.search(token)!=null and token.length()==48
func read_entries()->Dictionary:
	if not FileAccess.file_exists(path):return {"ok":true,"entries":{}}
	var file:=FileAccess.open(path,FileAccess.READ)
	if file==null:return {"ok":false,"error":"Cannot read saved logins."}
	if file.get_length()>MAX_BYTES:return {"ok":false,"error":"Saved login file is invalid."}
	var parser:=JSON.new()
	if parser.parse(file.get_as_text())!=OK:return {"ok":false,"error":"Saved login file is invalid."}
	var data:Variant=parser.data
	if not data is Dictionary or data.get("version")!=1 or not data.get("entries") is Dictionary or data.entries.size()>MAX_ENTRIES:return {"ok":false,"error":"Saved login file is invalid."}
	for id in data.entries:
		var entry:Variant=data.entries[id]
		if not entry is Dictionary or not entry.get("origin") is String or not entry.get("account") is String:return {"ok":false,"error":"Saved login file is invalid."}
		if not valid_key(entry.origin,entry.account) or id!=key(entry.origin,entry.account) or not valid_token(entry.get("remember_token")):return {"ok":false,"error":"Saved login file is invalid."}
		var expiry:Variant=entry.get("expires_at")
		if not (expiry is int or expiry is float) or not is_finite(float(expiry)):return {"ok":false,"error":"Saved login file is invalid."}
	return {"ok":true,"entries":data.entries}
func key(origin:String,account:String)->String:return origin.sha256_text()+":"+account
func load_login(origin:String,account:String)->Dictionary:
	if not valid_key(origin,account):return {"ok":false,"error":"Invalid server or account."}
	var data:=read_entries()
	if not data.ok:return data
	var entry:Variant=data.entries.get(key(origin,account),{})
	if not entry is Dictionary:return {"ok":false,"error":"Saved login entry is invalid."}
	if entry.is_empty():return {"ok":true,"found":false}
	var expiry:Variant=entry.get("expires_at")
	if entry.get("origin")!=origin or entry.get("account")!=account or not valid_token(entry.get("remember_token")) or not (expiry is int or expiry is float) or not is_finite(float(expiry)):return {"ok":false,"error":"Saved login entry is invalid."}
	if float(expiry)<=Time.get_unix_time_from_system():return {"ok":true,"found":false,"expired":true}
	return {"ok":true,"found":true,"account":account,"remember_token":entry.remember_token,"expires_at":expiry}
func save_login(origin:String,account:String,value:Dictionary)->Dictionary:
	if not valid_key(origin,account) or value.get("account")!=account or not valid_token(value.get("remember_token")):return {"ok":false,"error":"Server returned an invalid saved login."}
	var expiry:Variant=value.get("expires_at")
	if not (expiry is int or expiry is float) or not is_finite(float(expiry)) or float(expiry)<=Time.get_unix_time_from_system():return {"ok":false,"error":"Server returned an expired saved login."}
	var data:=read_entries()
	if not data.ok:return data
	for id in data.entries.keys():
		if data.entries[id] is Dictionary and float(data.entries[id].get("expires_at",0))<=Time.get_unix_time_from_system():data.entries.erase(id)
	var id:=key(origin,account)
	if not data.entries.has(id) and data.entries.size()>=MAX_ENTRIES:return {"ok":false,"error":"Saved login limit reached. Forget an unused login first."}
	data.entries[id]={"origin":origin,"account":account,"remember_token":value.remember_token,"expires_at":expiry}
	return write_entries(data.entries)
func remove_login(origin:String,account:String)->Dictionary:
	var data:=read_entries()
	if not data.ok:return data
	data.entries.erase(key(origin,account));return write_entries(data.entries)
func write_entries(entries:Dictionary)->Dictionary:
	var temp:=path+"."+Crypto.new().generate_random_bytes(16).hex_encode()+".tmp"
	var file:=FileAccess.open(temp,FileAccess.WRITE)
	if file==null:return {"ok":false,"error":"Cannot write saved login file."}
	# Set private permissions before writing any secret bytes.
	if OS.get_name()!="Windows" and FileAccess.set_unix_permissions(temp,384)!=OK:
		file.close();DirAccess.remove_absolute(temp);return {"ok":false,"error":"Cannot protect saved login file."}
	file.store_string(JSON.stringify({"version":1,"entries":entries}));file.flush()
	var ok:=file.get_error()==OK;file.close()
	if ok:ok=DirAccess.rename_absolute(temp,path)==OK
	if not ok:DirAccess.remove_absolute(temp)
	return {"ok":ok,"error":"" if ok else "Cannot save login file."}
