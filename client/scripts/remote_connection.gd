extends RefCounted
## Private remote transport configuration. Credentials never become CLI arguments.
## A configured CA and HTTPS hostname/IP SAN validation are mandatory.
var configured := false
var authenticated := false
var legacy_profile := false
var expires_at := 0.0
var ca_certificate_path := ""
var error := ""
var base_url := ""
var account := ""
var profile_path := ""
var _token := ""
var _certificate: X509Certificate
const MAX_BODY_BYTES := 16384
const PUBLIC_AUTH := ["/auth/login","/auth/register","/auth/resume","/auth/forget"]

func reset() -> void:
	configured=false;authenticated=false;legacy_profile=false;expires_at=0;ca_certificate_path="";error="";base_url="";account="";profile_path="";_token="";_certificate=null

func fail(message: String) -> bool:
	error=message
	return false

func load_profile(path: String) -> bool:
	reset()
	var parsed: Variant=JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	if not parsed is Dictionary: return fail("Cannot read the private remote connection profile.")
	return configure(parsed,path)

func configure(value: Dictionary, path: String="") -> bool:
	reset()
	var origin: Variant=value.get("base_url")
	if not origin is String: return fail("Remote base_url must use HTTPS.")
	var expression:=RegEx.new()
	expression.compile("^https://(?:\\[[0-9A-Fa-f:]+\\]|[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?)(?::([0-9]{1,5}))?/?$")
	var match_result:=expression.search(origin)
	if match_result==null or match_result.get_string(0)!=origin: return fail("Remote base_url must be an HTTPS origin without credentials, path, query, or fragment.")
	var port:=match_result.get_string(1)
	if not port.is_empty() and (int(port)<1 or int(port)>65535): return fail("Remote HTTPS port is invalid.")
	var name: Variant=value.get("account", "")
	expression.compile("^[A-Za-z0-9_]{1,24}$")
	if not name is String or (not name.is_empty() and (name.strip_edges()!=name or expression.search(name)==null)): return fail("Remote account must contain 1–24 letters, digits, or underscores.")
	var token: Variant=value.get("token", "")
	expression.compile("^[A-Za-z0-9._~+/\\-]+=*$")
	if not token is String or (not token.is_empty() and (token.strip_edges()!=token or token.length()>4096 or expression.search(token)==null)): return fail("Remote bearer token is missing or invalid.")
	if name.is_empty()!=token.is_empty(): return fail("Legacy account and token must be supplied together.")
	var certificate_path: Variant=value.get("ca_certificate")
	if not certificate_path is String or not certificate_path.is_absolute_path(): return fail("Remote ca_certificate must name an absolute PEM certificate path.")
	var certificate:=X509Certificate.new()
	if not FileAccess.file_exists(certificate_path) or certificate.load(certificate_path)!=OK: return fail("Remote CA certificate is unavailable or invalid.")
	base_url=origin.trim_suffix("/");account=name;_token=token;_certificate=certificate
	profile_path=path;configured=true;ca_certificate_path=certificate_path
	authenticated=not token.is_empty();legacy_profile=authenticated
	if value.has("launcher_session"):
		if legacy_profile or not value.launcher_session is Dictionary: return fail("Invalid launcher session profile.")
		return accept_session(value.launcher_session)
	return true

func validate_request(endpoint: String, path: String, body: Dictionary={}) -> String:
	if not configured: return "Remote connection is not configured."
	if endpoint!=base_url: return "Remote request origin differs from the authenticated profile."
	if not path.begins_with("/") or path.begins_with("//") or path.contains("\\") or path.contains("#"): return "Remote request must use a relative service path."
	for character in path:
		if character.unicode_at(0)<32 or character.unicode_at(0)==127: return "Remote request must use a relative service path."
	var public_auth:=path in PUBLIC_AUTH
	if not public_auth and (not authenticated or (expires_at>0 and Time.get_unix_time_from_system()>=expires_at)): return "Sign in to the connected server."
	var query:=path.get_slice("?",1)
	var accounts:=0
	for pair in query.split("&"):
		if pair.get_slice("=",0).uri_decode()=="account":
			accounts+=1
			if accounts>1 or pair.get_slice("=",1).uri_decode()!=account: return "Remote request account differs from the authenticated profile."
	if not public_auth and body.has("account") and body.account!=account: return "Remote request account differs from the authenticated profile."
	if JSON.stringify(body).to_utf8_buffer().size()>MAX_BODY_BYTES: return "Remote request exceeds the gateway JSON body limit."
	return ""

func apply_to(request: HTTPRequest, endpoint: String, path: String, body: Dictionary={}) -> Dictionary:
	var problem:=validate_request(endpoint,path,body)
	if not problem.is_empty(): return {"ok":false,"error":problem}
	# Zero redirects ensures credentials can never be forwarded to another origin.
	request.max_redirects=0
	request.set_tls_options(TLSOptions.client(_certificate))
	var headers:=PackedStringArray(["Content-Type: application/json"])
	if path not in PUBLIC_AUTH: headers.append("Authorization: Bearer "+_token)
	return {"ok":true,"headers":headers}

func clear_session() -> void:
	authenticated=false;legacy_profile=false;expires_at=0;account="";_token=""

func accept_session(value: Dictionary) -> bool:
	var name: Variant=value.get("account")
	var token: Variant=value.get("token")
	var expiry: Variant=value.get("expires_at")
	var expression:=RegEx.new();expression.compile("^[a-z][a-z0-9_]{2,23}$")
	if not name is String or name.strip_edges()!=name or expression.search(name)==null: return fail("Server returned an invalid account session.")
	expression.compile("^[A-Za-z0-9._~+/\\-]+=*$")
	if not token is String or token.is_empty() or token.strip_edges()!=token or token.length()>4096 or expression.search(token)==null: return fail("Server returned an invalid account session.")
	if not (expiry is float or expiry is int) or not is_finite(float(expiry)) or float(expiry)<=Time.get_unix_time_from_system(): return fail("Server returned an expired account session.")
	account=name;_token=token;expires_at=float(expiry);authenticated=true;legacy_profile=false
	return true

func remove_legacy_profile_credentials() -> bool:
	# Session tokens and passwords are never written. Replace the private profile
	# only after a complete endpoint-only file has been flushed in the same directory.
	if profile_path.is_empty(): return true
	var temporary:=profile_path+".cleanup-"+str(OS.get_process_id())+"-"+str(Time.get_ticks_usec())
	var output:=FileAccess.open(temporary,FileAccess.WRITE)
	if output==null: return false
	if OS.get_name()!="Windows" and FileAccess.set_unix_permissions(temporary,384)!=OK:
		output.close();DirAccess.remove_absolute(temporary);return false
	output.store_string(JSON.stringify({"base_url":base_url,"ca_certificate":ca_certificate_path},"\t")+"\n")
	output.flush()
	var succeeded:=output.get_error()==OK
	output.close()
	if succeeded:succeeded=DirAccess.rename_absolute(temporary,profile_path)==OK
	if not succeeded:DirAccess.remove_absolute(temporary)
	return succeeded
