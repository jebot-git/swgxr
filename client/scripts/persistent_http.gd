extends RefCounted
## One serialized native request per TLS connection. Never redirects or retries
## a transmitted mutation; an uncertain receipt remains uncertain.
var client:=HTTPClient.new()
var origin:=""
var busy:=false
var last_used:=0
var opened_at:=0
func exchange(tree:SceneTree,endpoint:String,path:String,method:int,headers:PackedStringArray,body:String,tls:TLSOptions,timeout:float)->Array:
	if busy:return [HTTPRequest.RESULT_REQUEST_FAILED,0,[],PackedByteArray()]
	busy=true
	var deadline:=Time.get_ticks_msec()+int(timeout*1000)
	if origin!=endpoint or Time.get_ticks_msec()-last_used>6000 or Time.get_ticks_msec()-opened_at>45000:
		client.close();origin=endpoint;opened_at=Time.get_ticks_msec()
	client.poll()
	if client.get_status()!=HTTPClient.STATUS_CONNECTED:
		client.close()
		var secure:=endpoint.begins_with("https://")
		var host:=endpoint.trim_prefix("https://").trim_prefix("http://")
		var port:=int(host.get_slice(":",1)) if host.contains(":") else (443 if secure else 80)
		host=host.get_slice(":",0)
		if client.connect_to_host(host,port,tls if secure else null)!=OK:return finish(HTTPRequest.RESULT_CANT_CONNECT)
		while client.get_status() in [HTTPClient.STATUS_RESOLVING,HTTPClient.STATUS_CONNECTING]:
			if Time.get_ticks_msec()>=deadline:return finish(HTTPRequest.RESULT_TIMEOUT)
			await tree.process_frame
			if client.poll()!=OK:return finish(HTTPRequest.RESULT_CONNECTION_ERROR)
	if client.get_status()!=HTTPClient.STATUS_CONNECTED:return finish(HTTPRequest.RESULT_CANT_CONNECT)
	if client.request(method,path,headers,body)!=OK:return finish(HTTPRequest.RESULT_REQUEST_FAILED)
	while client.get_status()==HTTPClient.STATUS_REQUESTING:
		if Time.get_ticks_msec()>=deadline:return finish(HTTPRequest.RESULT_TIMEOUT)
		await tree.process_frame
		if client.poll()!=OK:return finish(HTTPRequest.RESULT_CONNECTION_ERROR)
	if not client.has_response():return finish(HTTPRequest.RESULT_NO_RESPONSE)
	var status:=client.get_response_code();var response_headers:=client.get_response_headers();var bytes:=PackedByteArray()
	while client.get_status()==HTTPClient.STATUS_BODY:
		if Time.get_ticks_msec()>=deadline:return finish(HTTPRequest.RESULT_TIMEOUT)
		if client.poll()!=OK:return finish(HTTPRequest.RESULT_CONNECTION_ERROR)
		var chunk:=client.read_response_body_chunk();bytes.append_array(chunk)
		if bytes.size()>67108864:return finish(HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED)
		if chunk.is_empty():await tree.process_frame
	busy=false;last_used=Time.get_ticks_msec()
	return [HTTPRequest.RESULT_SUCCESS,status,response_headers,bytes]
func finish(result:int)->Array:
	client.close();busy=false
	return [result,0,[],PackedByteArray()]
