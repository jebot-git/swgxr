extends Node3D
## Original entertainer CEFs share the combat renderer's global particle budgets.
const Particles = preload("res://combat/optimized_particles.gd")
const CombatAssets = preload("res://combat/original_assets.gd")
class EffectResources extends RefCounted:
	var catalog: Dictionary = {}
	var directory := ""
	var textures: Dictionary = {}
	var source: RefCounted
	func texture(path: String) -> Texture2D:
		if textures.has(path):
			var found: Texture2D = textures[path]
			textures.erase(path)
			textures[path] = found
			return found
		if path.is_empty() or path.is_absolute_path() or ".." in path.split("/"): return null
		var image := Image.load_from_file(directory.path_join(path))
		if image == null: return null
		if textures.size() >= 16: textures.erase(textures.keys()[0])
		var result := ImageTexture.create_from_image(image)
		textures[path] = result
		return result
	func sound(path: String) -> AudioStream:
		return source.sound(path)

var resources: EffectResources
var manager: Node3D
var camera: Camera3D
var primary: RefCounted

func configure(source: RefCounted, eye: Camera3D) -> void:
	resources = EffectResources.new()
	resources.catalog = source.catalog
	resources.directory = source.directory
	resources.source = source
	camera = eye
	# Keep combat programs pinned even if the first visible event is entertainment.
	primary = CombatAssets.new()
	if not primary.load_catalog(): return
	manager = Particles.shared(self,primary,camera)

func play(path: String, pose: Transform3D) -> bool:
	if resources == null or not resources.catalog.get("effects",{}).has(path): return false
	if not is_instance_valid(manager):
		if primary == null or primary.catalog.is_empty(): return false
		manager = Particles.shared(self,primary,camera)
	var effect: Dictionary = resources.catalog.effects[path]
	var accepted := false
	for appearance: Dictionary in effect.get("appearances",[]):
		accepted = manager.burst(str(appearance.particle),pose,float(appearance.duration),"impact",resources) or accepted
	manager.disabled_lights += effect.get("lights",[]).size()
	var audio := get_node_or_null("/root/SWGSpatialAudio")
	if audio != null:
		for sound: String in effect.get("sounds",[]): audio.play_original(resources,sound,pose.origin,1)
	return accepted

func reset() -> void:
	# Shared particles may belong to combat or other performers; never clear them.
	pass
