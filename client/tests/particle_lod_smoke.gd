extends SceneTree
## Native presentation policy tests. Headless results do not validate GPU appearance.
var failures: Array[String] = []
var checks := 0
var results: Dictionary = {}
var output := ProjectSettings.globalize_path("res://../runtime/evidence/particle-lod-smoke.json")

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func fixture() -> Node3D:
	var batch: Node3D = ClassDB.instantiate("SwgParticleBatch")
	root.add_child(batch)
	batch.set_view(Transform3D.IDENTITY, 90.0, 1.0)
	return batch

func style(batch: Node3D, extra := {}) -> int:
	var definition := {"kind":"impact", "color":Color.WHITE, "color_end":Color.WHITE,
		"width":0.1, "length":0.1, "life":1.0, "speed":0.0, "max_distance":100.0}
	definition.merge(extra, true)
	return batch.register_style(definition)

func pose(point: Vector3) -> Transform3D:
	return Transform3D(Basis.IDENTITY, point)

func run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output = argument.trim_prefix("--output=")
	if not ClassDB.class_exists("SwgParticleBatch"):
		check(false, "Native SwgParticleBatch is not available")
		finish()
		return
	var batch := fixture()
	var source := style(batch)
	var density: Array[int] = []
	for distance in [19.0, 21.0, 49.0, 51.0, 99.0]:
		batch.clear()
		check(batch.emit_burst(source, pose(Vector3(0, 0, -distance)), 24), "Visible primary burst admitted at %s m" % distance)
		batch.advance(0.0)
		density.append(batch.statistics().render_visible)
	check(density[0] == 24, "Full tier retains the requested bounded density")
	check(density[1] < density[0] and density[1] > 0, "Crossing 20 m reduces density without removing every primary particle")
	check(density[1] == density[2], "The 20–50 m density tier is consistent")
	check(density[3] < density[2] and density[3] > 0, "Crossing 50 m preserves one recognizable primary particle")
	check(density[3] == density[4], "The 50–100 m density tier is consistent")
	results.density_at_19_21_49_51_99m = density
	batch.clear()
	check(not batch.emit_burst(source, pose(Vector3(0, 0, -100.01)), 24), "Bursts beyond 100 m are rejected")
	batch.advance(0.0)
	check(batch.statistics().render_visible == 0, "Nothing renders beyond the hard cutoff")
	batch.emit_burst(source, pose(Vector3(0, 0, -19)), 24)
	batch.advance(0.0)
	batch.set_view(pose(Vector3(0, 0, 101)), 90, 1)
	batch.advance(0.0)
	check(batch.statistics().render_visible == 0 and batch.statistics().particles == 0, "Active particles are removed when the viewer moves beyond range")
	batch.set_view(Transform3D.IDENTITY, 90, 1)
	batch.advance(0.0)
	check(batch.statistics().particles == 0, "Culled effects never catch up when the viewer returns")
	batch.clear()
	check(not batch.emit_burst(source, pose(Vector3(0, 0, 20)), 24), "Offscreen bursts are dropped before allocation")
	batch.set_view(Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO), 90, 1)
	batch.advance(0.05)
	check(batch.statistics().render_visible == 0, "Turning toward a rejected burst does not replay it")
	batch.set_view(Transform3D.IDENTITY, 90, 1)
	check(batch.emit_burst(source, pose(Vector3(0, 0, 1.5)), 1), "The near 2 m safety radius retains controller effects")
	batch.clear()
	check(not batch.emit_burst(source, pose(Vector3(0, 0, 3.0)), 1), "Behind-view effects outside the near 2 m radius are culled")
	batch.clear()
	batch.emit_burst(source, pose(Vector3(0, 0, -20)), 24)
	batch.advance(0.0)
	batch.set_view(Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO), 90, 1)
	batch.advance(0.0)
	check(batch.statistics().particles == 0 and batch.statistics().render_visible == 0, "Existing particles are culled when the view turns away")
	batch.set_view(Transform3D.IDENTITY, 90, 1)
	var secondary := style(batch, {"secondary":true})
	check(not batch.emit_burst(secondary, pose(Vector3(0, 0, -51)), 12), "Secondary layers are absent beyond 50 m")
	var smoke := style(batch, {"max_distance":20.0})
	check(not batch.emit_burst(smoke, pose(Vector3(0, 0, -21)), 12), "Smoke respects its shorter 20 m cutoff")
	batch.clear()
	check(batch.emit_burst(source, pose(Vector3(17.0, 0, -10)), 1), "The conservative angular guard retains effects just outside the nominal view")
	batch.clear()
	batch.emit_burst(source, pose(Vector3(0, 0, -10)), 24)
	batch.advance(1.1)
	check(batch.statistics().particles == 0, "Long frame stalls expire old effects instead of prolonging playback")
	batch.clear()
	for i in range(1000): batch.emit_burst(source, pose(Vector3(0, 0, -150)), 24)
	check(batch.emit_burst(source, pose(Vector3(0, 0, -1)), 1), "Rejected distant storms cannot consume the visible near-effect admission budget")
	results.culling = batch.statistics()
	batch.free()

	batch = fixture()
	var tracer_style := style(batch, {"kind":"tracer"})
	var old: int = batch.create_tracer(tracer_style, pose(Vector3(0, 0, -10)))
	check(old >= 0, "A visible tracer obtains a handle")
	batch.release_tracer(old)
	var replacement: int = batch.create_tracer(tracer_style, pose(Vector3(0, 0, -10)))
	check(replacement >= 0 and replacement != old, "Reused slots have a new generation")
	batch.update_tracer(old, pose(Vector3(0, 0, -200)))
	batch.release_tracer(old)
	batch.advance(0.0)
	check(batch.statistics().tracers == 1 and batch.statistics().render_visible == 1, "Stale updates/releases cannot alter the replacement tracer")
	batch.update_tracer(replacement, pose(Vector3(0, 0, -101)))
	batch.advance(0.0)
	check(batch.statistics().render_visible == 0, "An active tracer moving beyond 100 m is hidden immediately")
	batch.update_tracer(replacement, pose(Vector3(0, 0, -10)))
	batch.advance(0.0)
	check(batch.statistics().render_visible == 1, "A tracked tracer can reenter range without catch-up particles")
	batch.clear()
	for i in range(700):
		if i % 64 == 0: batch.advance(0.0)
		batch.create_tracer(tracer_style, pose(Vector3(0, 0, -10)))
	batch.advance(0.0)
	var stats: Dictionary = batch.statistics()
	check(stats.tracers == stats.max_tracers, "A tracer storm saturates but never exceeds the fixed pool")
	check(stats.render_visible <= stats.max_instances_per_style, "Per-style instance limits apply to tracer rendering")
	results.tracer_storm = stats
	batch.clear()
	for i in range(200): batch.create_tracer(tracer_style, pose(Vector3(0, 0, 150)))
	check(batch.statistics().tracers <= batch.statistics().max_tracer_events_per_frame, "Logical offscreen tracer admission has its own per-frame cap")
	var flash_style := style(batch)
	check(batch.emit_burst(flash_style, pose(Vector3(0, 0, -1)), 1), "Offscreen logical tracer admission cannot starve a visible muzzle flash")
	batch.free()

	batch = fixture()
	source = style(batch)
	for i in range(1000): batch.emit_burst(source, pose(Vector3(0, 0, -10)), 64)
	stats = batch.statistics()
	check(stats.particles == stats.max_particles, "An emission storm fills but never exceeds the global particle cap")
	check(stats.events_admitted <= stats.max_events_per_frame, "Frame admission has a hard event limit")
	check(stats.dropped_budget > 0, "Storm budget drops are measurable")
	batch.advance(0.0)
	stats = batch.statistics()
	check(stats.render_visible <= stats.max_instances_per_style, "Per-material draw instances remain bounded during storms")
	for i in range(100): style(batch)
	stats = batch.statistics()
	check(stats.styles == stats.max_styles, "Style registrations stop at a hard cap")
	check(batch.get_child_count() <= stats.max_styles, "Rejected styles cannot allocate extra rendering nodes")
	results.budget_storm = stats
	batch.clear()
	check(batch.statistics().particles == 0 and batch.statistics().tracers == 0 and batch.statistics().render_visible == 0, "Clear removes all live allocations and visible instances")
	batch.free()
	finish()

func finish() -> void:
	results.merge({"passed":failures.is_empty(), "checks":checks, "failures":failures,
		"headless":DisplayServer.get_name() == "headless", "gpu_validated":false, "headset_validated":false})
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	var file := FileAccess.open(output, FileAccess.WRITE)
	file.store_string(JSON.stringify(results, "\t"))
	print("PARTICLE_LOD_SMOKE %s: %s checks" % ["PASS" if failures.is_empty() else "FAIL", checks])
	quit(0 if failures.is_empty() else 1)
