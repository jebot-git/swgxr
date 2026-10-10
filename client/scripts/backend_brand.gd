extends RefCounted
## Translate server prose at the presentation boundary; protocol IDs stay intact.
static func messages(value:Variant)->void:
	if value is Array:
		for item in value:messages(item)
	elif value is Dictionary:
		for key in value:
			if value[key] is String and str(key) in ["error","detail","message","reason","description","blocked_reason","deletion_reason","status_text","dialogue"]:
				value[key]=str(value[key]).replace("Core3","CoreCU").replace("CORE3","CORECU")
			elif value[key] is Dictionary or value[key] is Array:messages(value[key])
