extends "res://scripts/deployed_resource_tools.gd"
## Public native visual rows only; never expose another player's inventory,
## pretend unknown stored quantities are zero, or make their tool locally owned.
func count_text(state: Dictionary, _now: float = -1.0) -> String:
	return str(state.get("resource_name", "Resource tool")).left(40) + "\n" + str(state.get("state", "Sampling")).replace("_", " ").capitalize()

func create_visual(id: String, state: Dictionary, pose: Transform3D) -> bool:
	if not super.create_visual(id, state, pose): return false
	visuals[id].node.collision_layer = 0
	visuals[id].node.remove_meta("deployment_id")
	visuals[id].node.set_meta("remote_owner_id", str(state.get("owner_id", "")))
	return true

func nearest(_position: Vector3, _radius: float = 0.22) -> Dictionary:
	return {}
