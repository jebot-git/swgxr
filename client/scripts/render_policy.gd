extends Node
## The current product supports desktop Forward+ / Vulkan only.
## Headless tests use Godot's dummy renderer and make no GPU-performance claim.
static func assess(method: String, driver: String, headless: bool) -> Dictionary:
	if headless:
		return {"supported":true,"mode":"headless_validation","gpu_backend_active":false}
	var supported := method == "forward_plus" and driver == "vulkan"
	return {"supported":supported,"mode":"desktop_forward_plus_vulkan","gpu_backend_active":supported,"method":method,"driver":driver,
		"error":"This prototype requires Forward+ on Vulkan. Renderer fallback and standalone VR are not supported." if not supported else ""}

static func current() -> Dictionary:
	return assess(RenderingServer.get_current_rendering_method(),RenderingServer.get_current_rendering_driver_name(),DisplayServer.get_name()=="headless")

func _enter_tree() -> void:
	var result := current()
	if not result.supported:
		push_error(result.error + " Actual: " + str(result.method) + "/" + str(result.driver))
		get_tree().quit(2)
