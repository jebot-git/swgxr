extends Node3D
## Shared, bounded native particles are the production path. Legacy source_effect.gd
## is intentionally only instantiated by explicit reference/benchmark fixtures.
const OptimizedParticles = preload("res://combat/optimized_particles.gd")
var assets: RefCounted
var camera: Camera3D
var manager: Node3D

func configure(resources: RefCounted, eye: Camera3D) -> void:
	assets = resources
	camera = eye
	manager = OptimizedParticles.shared(self,assets,camera)

func ensure_manager() -> Node3D:
	if not is_instance_valid(manager): manager = OptimizedParticles.shared(self,assets,camera)
	return manager

func create_tracer(path: String, pose: Transform3D) -> int:
	return ensure_manager().tracer(path,pose)

func update_tracer(handle: int, pose: Transform3D) -> void:
	ensure_manager().move_tracer(handle,pose)

func release_tracer(handle: int) -> void:
	if is_instance_valid(manager): manager.release_tracer(handle)

func emit_particle(path: String, pose: Transform3D, kind := "impact") -> bool:
	return ensure_manager().burst(path,pose,1.0,kind)

func play(path: String, pose: Transform3D) -> void:
	if not assets.catalog.effects.has(path): return
	var shared_effects := ensure_manager()
	var source: Dictionary = assets.catalog.effects[path]
	for appearance in source.appearances:
		shared_effects.burst(appearance.particle,pose,float(appearance.duration))
	# Original particle glows supply flash appearance without transient world lights.
	shared_effects.disabled_lights += source.get("lights",[]).size()
	var audio := get_node_or_null("/root/SWGSpatialAudio")
	if audio != null:
		for sound in source.sounds:
			audio.play_original(assets,sound,pose.origin,2 if path.contains("muzzle") or path.contains("fire") else 1)
