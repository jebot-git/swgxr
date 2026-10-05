extends RefCounted
## Explicit transport identity for native authority; crafting session_id remains
## an unrelated original tool session and must never be overwritten.
static func id(app: Node) -> String:
	for key in ["live_combat","gameplay_session"]:
		var session:Variant=app.get(key)
		if is_instance_valid(session) and bool(session.get("live")):
			return str(session.get("session_id"))
	return ""
