extends SceneTree
class Bag extends Node3D:
	func begin_mutation(_message: String) -> void: pass
	func set_busy(_busy: bool, _message := "") -> void: pass
	func set_survey_result(_id: String, _scan: Dictionary) -> void: pass
class Host extends Node3D:
	var player: Node3D
	var datapad: Node3D
	func source_position_at(point: Vector3) -> Vector3: return point
	func update_inventory_presentation() -> void: pass
class Gathering extends "res://scripts/resource_gathering.gd":
	var reply: Dictionary = {}
	func valid_held(_tool: Dictionary) -> bool: return true
	func perform(_action: String, _parameters: Dictionary) -> Dictionary:
		await get_tree().process_frame
		app.player.position = Vector3(9,0,9)
		return reply
var checks := 0
var failures: Array = []
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var host := Host.new(); root.add_child(host)
	host.player = Node3D.new(); host.add_child(host.player)
	var service := Gathering.new(); host.add_child(service); service.app = host
	service.bag = Bag.new(); host.add_child(service.bag); service.set_process(false)
	var pulse := preload("res://multiplayer/survey_pulse.gd").shared(host); pulse.set_process(false)
	service.reply = {}; await service.survey({"id":"123"}, "456")
	check(pulse.accepted == 0, "Unconfirmed survey does not emit acknowledgement")
	host.player.position = Vector3(1,0,2)
	service.reply = {"mutation":{"success":true}, "confirmed_request_id":"confirmed123", "survey":{}}
	await service.survey({"id":"123"}, "456")
	check(pulse.accepted == 1, "Confirmed native survey emits once")
	check(pulse.pulses[0].origin == Vector3(1,0,2), "Pulse stays at request position when player walks during await")
	await service.survey({"id":"123"}, "456")
	check(pulse.accepted == 1, "Repeated request receipt cannot repeat pulse")
	service.reply.mutation.replayed = true; service.reply.confirmed_request_id = "replayed456"
	await service.survey({"id":"123"}, "456")
	check(pulse.accepted == 1, "Native replay response does not broadcast another visual action")
	service.reply.mutation = {"success":false}; service.reply.confirmed_request_id = "failed789"
	await service.survey({"id":"123"}, "456")
	check(pulse.accepted == 1, "Native rejection cannot produce a success pulse")
	var eye := Camera3D.new(); host.add_child(eye); eye.position=Vector3(0,2,5); pulse.camera=eye
	check(not pulse.play_confirmed(Vector3(0,0,-100), "too_far"), "Survey effects enforce distance admission")
	check(not pulse.play_confirmed(Vector3(0,0,50), "behind"), "Offscreen pulse admission uses camera bounds")
	pulse.clear(); pulse.queue_free(); host.queue_free(); await process_frame
	var result := {"checks":checks,"failures":failures,"validation":"Mocked native acknowledgement and dummy renderer; no GPU/XR claim"}
	FileAccess.open(ProjectSettings.globalize_path("res://../runtime/evidence/survey-pulse-smoke.json"),FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	print(JSON.stringify(result)); quit(0 if failures.is_empty() else 1)
