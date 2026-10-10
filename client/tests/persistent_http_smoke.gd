extends SceneTree
func _initialize()->void:call_deferred("run")
func run()->void:
	var args:=OS.get_cmdline_user_args();var tls_cert:=X509Certificate.new()
	if tls_cert.load(args[1])!=OK:quit(2);return
	var transport:=preload("res://scripts/persistent_http.gd").new()
	var headers:=PackedStringArray(["Content-Type: application/json","Authorization: Bearer "+"A".repeat(43)])
	for i in range(3):
		var result:=await transport.exchange(self,args[0],"/jtl/status",HTTPClient.METHOD_POST,headers,'{"character_id":"123"}',TLSOptions.client(tls_cert),3)
		if result[0]!=HTTPRequest.RESULT_SUCCESS or result[1]!=200:print(result);quit(1);return
	transport.client.close()
	print("PERSISTENT_TLS_PASSED");quit()
