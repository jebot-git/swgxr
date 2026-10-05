extends RefCounted
## Shared, testable transmit/listen gate. No microphone or input side effects.
static func evaluate(state: Dictionary) -> Dictionary:
	for condition in [
		[not bool(state.get("authenticated",false)),"Sign in to use voice"],
		[not bool(state.get("world",false)) or not bool(state.get("character",false)),"Enter the galaxy to use voice"],
		[bool(state.get("loading",false)),"Voice paused while loading"],
		[not bool(state.get("alive",false)),"Voice paused while incapacitated or dead"],
		[not bool(state.get("focused",false)),"Voice paused while unfocused"],
		[not bool(state.get("tracked",false)),"Voice paused while tracking is unavailable"],
		[bool(state.get("menu",false)),"Voice paused while the menu is open"]]:
		if condition[0]:return {"allowed":false,"reason":condition[1]}
	return {"allowed":true,"reason":""}
