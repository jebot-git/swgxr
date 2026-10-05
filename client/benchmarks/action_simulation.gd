extends SceneTree
# CPU-only synthetic action authority benchmark. No sockets, Core3, XR or renderer.
func _initialize() -> void:
	call_deferred("run")

func option(name: String, fallback: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--" + name + "="):
			return arg.substr(name.length() + 3)
	return fallback

func run() -> void:
	var output := option("output", "res://../runtime/evidence/action-simulation.json")
	if not ClassDB.class_exists("SwgActionSimulation"):
		push_error("SwgActionSimulation unavailable: rebuild native extension")
		quit(2)
		return
	var simulation = ClassDB.instantiate("SwgActionSimulation")
	var checks := verify_contract(simulation)
	var config := {
		"players": int(option("players", "16")), "npcs": int(option("npcs", "16")),
		"instances": int(option("instances", "1")), "sample_ticks": int(float(option("duration", "15")) * 60),
		"warmup_ticks": int(float(option("warmup", "3")) * 60), "seed": int(option("seed", "42")),
		"latency_ms": float(option("latency-ms", "50")), "jitter_ms": float(option("jitter-ms", "25")),
		"loss": float(option("loss", "0.01")), "tick_hz": 60, "snapshot_hz": 20,
		"projectile_capacity": 4096, "max_snapshot_actors": 192,
	}
	var result: Dictionary = simulation.benchmark(config)
	result["configuration"] = config
	result["contract_checks"] = checks
	result["passed"] = result.correctness_pass and checks.values().all(func(v): return v == true)
	result["limitations"] = ["Synthetic arena boundary and spherical actor collision; no terrain or authored buildings.", "In-process serialized packet queue; no real network, socket, encryption or transport overhead.", "No Core3 persistence, inventory, economy or combat integration.", "Simple moving/shooting NPC workload; no pathfinding or production behavior trees.", "CPU time measured unpaced after warmup; no wall-clock scheduler or supported player capacity is established.", "dropped_ticks counts fixed-step catchup discards; deadline overruns are separately reported by ticks_over_16_67_ms.", "Snapshot head/hand payload reserves 36 bytes per actor using fixture zero values.", "Dropped snapshots and reordering are modeled per message, not per MTU fragment."]
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write simulation benchmark " + output)
		quit(2)
		return
	file.store_string(JSON.stringify(result, "\t") + "\n")
	print("ACTION_SIMULATION ", JSON.stringify({"players": result.players, "npcs": result.npcs, "passed": result.passed, "p99_ms": result.tick_p99_ms, "output": output}))
	quit(0 if result.passed else 1)

func verify_contract(simulation) -> Dictionary:
	var checks := {}
	simulation.configure({"projectile_capacity": 32})
	var shooter: int = simulation.add_actor(Vector3.ZERO, 0, false)
	simulation.add_actor(Vector3(0, 0, -2), 1, false) # Co-located other instance must never intercept.
	simulation.add_actor(Vector3(0, 0, -4), 0, false)
	checks["accept_fresh_input"] = simulation.submit_command(shooter, 2, Vector3.ZERO, Vector3.FORWARD, true)
	checks["reject_stale_input"] = not simulation.submit_command(shooter, 1, Vector3.ZERO, Vector3.FORWARD, false)
	checks["reject_nonfinite_input"] = not simulation.submit_command(shooter, 3, Vector3(NAN, 0, 0), Vector3.FORWARD, false)
	for _i in range(12):
		simulation.advance(1.0 / 60.0)
	var state: Dictionary = simulation.state()
	checks["swept_actor_hit"] = state.actor_hits >= 1
	checks["cross_instance_isolation"] = state.instance_isolation_errors == 0
	checks["pool_conservation"] = state.projectiles_emitted == state.actor_hits + state.arena_wall_hits + state.expired_projectiles + state.active_projectiles
	checks["reject_invalid_delta"] = simulation.advance(-1.0).get("valid", true) == false
	simulation.configure({})
	simulation.add_actor(Vector3.ZERO, 0, false)
	simulation.submit_command(0, 1, Vector3(1000, 0, 0), Vector3.FORWARD, false)
	simulation.advance(1.0 / 60.0)
	checks["movement_speed_limit"] = simulation.state().actors[0].position.x <= 7.5 / 60.0 + 0.00001
	simulation.advance(1.0)
	checks["catchup_bounded_and_reported"] = simulation.state().dropped_ticks > 0
	var deterministic := {"players": 16, "npcs": 8, "instances": 2, "sample_ticks": 120, "warmup_ticks": 0, "seed": 901, "latency_ms": 25, "jitter_ms": 100, "loss": 0.05}
	var first: Dictionary = simulation.benchmark(deterministic)
	var second: Dictionary = simulation.benchmark(deterministic)
	checks["seeded_reproducibility"] = first.state_checksum == second.state_checksum and first.snapshot_bytes == second.snapshot_bytes and first.actor_hits == second.actor_hits
	checks["reordered_snapshots_rejected"] = first.stale_snapshots_rejected > 0
	checks["latency_loss_exercised"] = first.snapshots_lost > 0 and first.input_commands_lost > 0 and first.peak_packet_queue > 0
	return checks
