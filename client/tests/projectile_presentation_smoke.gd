extends SceneTree
# Presentation must not silently stop when collision data is unavailable.
class Effects extends Node3D:
	var assets := {"catalog":{"weapons":{"test":{"effects":{"fire":"original_fire"}}}}}
	var calls: Array = []
	func play(effect: String, pose: Transform3D) -> void: calls.append([effect,pose])
class Projectiles extends "res://combat/projectiles.gd":
	var response := {"complete":false,"reason":"unloaded_world_or_terrain_coverage"}
	func trace_query(_from: Vector3, _to: Vector3, _cell: String) -> Dictionary: return response
var errors: Array = []
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var bolts := Projectiles.new()
	root.add_child(bolts)
	var effects := Effects.new()
	bolts.add_child(effects)
	bolts.effects = effects
	var impacts: Array = []
	bolts.impact.connect(func(event):impacts.append(event))
	for i in range(12):
		bolts.spawn({"weapon_id":"test","sequence":i},Transform3D.IDENTITY,Vector3(0,0,0.2),"")
	if effects.calls.size()!=12: errors.append("Every accepted shot sounds exactly once across incomplete traces")
	if not bolts.bolts.is_empty() or not impacts.is_empty(): errors.append("Unknown geometry must still fail closed")
	if bolts.incomplete_queries!=12 or bolts.last_incomplete_reason!="unloaded_world_or_terrain_coverage": errors.append("Missing collision reports diagnostic reason")
	bolts.response={"complete":true,"hit":true,"position":Vector3.ZERO,"normal":Vector3.UP}
	# Live world obstruction creates presentation but cannot invent target damage.
	bolts.spawn({"weapon_id":"test","sequence":12,"live_session":"mock"},Transform3D.IDENTITY,Vector3(0,0,0.2),"")
	if effects.calls.size()!=14 or effects.calls[12][0]!="original_fire": errors.append("Obstructed muzzle still discharges once before impact effect")
	if impacts.size()!=1 or impacts[0].damage!=0: errors.append("Obstruction cannot fabricate authoritative damage")
	bolts.free()
	print(JSON.stringify({"test":"projectile_presentation","passed":errors.is_empty(),"errors":errors,"gpu_validation":false,"live_core3":false}))
	quit(0 if errors.is_empty() else 1)
