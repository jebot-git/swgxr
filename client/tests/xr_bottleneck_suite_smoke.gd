extends SceneTree
const Suite = preload("res://diagnostics/xr_bottleneck_suite.gd")
class Player extends Node3D:
	var active := true
	var camera: Camera3D
	func get_camera() -> Camera3D: return camera
class Allowed extends Node:
	var allowed := true
	func set_allowed(value: bool) -> void: allowed=value
class Mirror extends CanvasLayer:
	var enabled := true
	var viewport: SubViewport
class NPCs extends Node:
	var records := {}
class Actor extends Node3D:
	var animation_player: AnimationPlayer
	var face_player: AnimationPlayer
class Main extends Node3D:
	var world_ready := false
	var xr_focused := true
	var player: Player
	var xr_viewport: SubViewport
	var xr_spectator: Mirror
	var ambient_npcs: NPCs
	var combat_rig: Allowed
	var datapad: Allowed
	var world_stream: Node
	var portal_visibility: Node
	var sync_calls := 0
	func sync_xr_activity() -> void:
		sync_calls+=1
		if is_instance_valid(player): player.active=world_ready and xr_focused
var checks := 0
var errors: Array[String] = []
func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok: errors.append(message); push_error(message)
func _initialize() -> void: call_deferred("run")
func make_main() -> Main:
	var main:=Main.new(); root.add_child(main)
	main.xr_viewport=SubViewport.new(); main.xr_viewport.size=Vector2i(200,160); main.add_child(main.xr_viewport)
	main.xr_viewport.scaling_3d_scale=1.2
	main.player=Player.new(); main.xr_viewport.add_child(main.player)
	main.player.camera=Camera3D.new(); main.player.add_child(main.player.camera)
	main.player.camera.cull_mask=37; main.player.position=Vector3(2,1,3)
	main.xr_spectator=Mirror.new(); main.add_child(main.xr_spectator)
	main.xr_spectator.viewport=SubViewport.new(); main.xr_spectator.add_child(main.xr_spectator.viewport)
	main.xr_spectator.set_process(true); main.xr_spectator.set_physics_process(false)
	main.xr_spectator.viewport.render_target_update_mode=SubViewport.UPDATE_ONCE
	main.ambient_npcs=NPCs.new(); main.add_child(main.ambient_npcs); main.ambient_npcs.set_process(true)
	var actor:=Actor.new(); main.ambient_npcs.add_child(actor)
	actor.animation_player=AnimationPlayer.new(); actor.add_child(actor.animation_player)
	actor.face_player=AnimationPlayer.new(); actor.add_child(actor.face_player); actor.face_player.active=false
	main.ambient_npcs.records.test={"avatar":actor}
	main.combat_rig=Allowed.new(); main.add_child(main.combat_rig)
	main.datapad=Allowed.new(); main.add_child(main.datapad)
	return main
func run() -> void:
	var main:=make_main()
	var suite:=Suite.new(); main.add_child(suite)
	var output:=ProjectSettings.globalize_path("res://../runtime/evidence/xr-bottleneck-suite-smoke")
	check(suite.configure(main,output,{"warmup":0.03,"notice":0.03,"settle":0.03,"measure":0.05}),"Diagnostic accepts output and bounded short test durations")
	suite.set_process(false)
	var now:=Time.get_ticks_usec()
	suite.advance(now)
	check(suite.phase=="waiting_world" and not suite.active,"Waits for world without taking control")
	main.world_ready=true; suite.advance(now+1000)
	var start_head:=main.player.camera.global_transform
	var seen: Dictionary={}
	for i in range(180):
		now+=10000
		suite.advance(now)
		if suite.measuring and not seen.has(suite.condition):
			suite.collect_sample(now)
			seen[suite.condition]=true
			check(not main.player.active and not main.combat_rig.allowed and not main.datapad.allowed,"Input gates consistent during "+suite.condition)
			check(main.player.camera.global_transform==start_head,"Camera tracking transform untouched during "+suite.condition)
			match suite.condition:
				"no_spectator": check(not main.xr_spectator.enabled and main.xr_spectator.viewport.render_target_update_mode==SubViewport.UPDATE_DISABLED,"No-spectator phase disables rendering")
				"frozen_npc_animation":
					check(suite.npc_frozen and not main.ambient_npcs.is_processing(),"NPC manager freezes for isolated phase")
					check(not main.ambient_npcs.records.test.avatar.animation_player.active and main.ambient_npcs.records.test.avatar.visible,"NPC poses freeze while meshes stay visible")
				"headset_half_resolution": check(is_equal_approx(main.xr_viewport.scaling_3d_scale,0.6),"Only headset internal scale is halved")
				"scene_hidden": check(main.player.camera.cull_mask==0 and not main.xr_spectator.enabled and main.player.camera.environment.background_color==Color.BLACK,"Scene-hidden clears headset scene and mirror")
				"restore_baseline": check(main.player.camera.cull_mask==37 and main.xr_spectator.enabled and is_equal_approx(main.xr_viewport.scaling_3d_scale,1.2),"Restored baseline uses original rendering settings")
		if suite.phase=="done": break
	check(seen.size()==6 and suite.phase=="done","All six conditions complete without quitting app")
	check(main.player.active and main.sync_calls>0,"Completion resynchronizes locomotion after releasing gate")
	check(main.combat_rig.allowed and main.datapad.allowed,"Combat and UI eligibility restore")
	check(main.ambient_npcs.records.test.avatar.animation_player.active and not main.ambient_npcs.records.test.avatar.face_player.active,"NPC players restore distinct original active flags")
	check(main.ambient_npcs.is_processing() and main.xr_spectator.is_processing() and not main.xr_spectator.is_physics_processing(),"Original process flags restore")
	check(main.player.camera.environment==null and main.player.camera.cull_mask==37,"Camera mask and environment restore exactly")
	var status: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(output.path_join("status.json")))
	var report: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(output.path_join("report.json")))
	check(status.phase=="done" and not status.measuring and report.restored,"Atomic status/report confirm completion and restoration")
	check(report.phases.size()==6 and report.phases.baseline.frame_intervals_usec.size()>0,"Raw frame intervals are grouped by condition")
	check(report.display_server=="headless" and report.samples[0].viewports.headset.timing_available==false,"Dummy tests explicitly lack viewport render timing")
	# Cancellation while rendering is altered must restore without touching poses.
	var abort:=Suite.new(); main.add_child(abort); abort.configure(main,output.path_join("abort")); abort.set_process(false)
	abort.advance(now+1000); abort.condition="scene_hidden"; abort.apply_condition()
	abort.cancel("mock cancellation")
	check(abort.phase=="failed" and not abort.active and main.player.camera.cull_mask==37 and main.xr_spectator.enabled,"Cancellation restores dark-scene state")
	var exit_probe:=Suite.new(); main.add_child(exit_probe); exit_probe.configure(main,output.path_join("exit")); exit_probe.set_process(false)
	exit_probe.advance(now+2000); exit_probe.condition="headset_half_resolution"; exit_probe.apply_condition()
	exit_probe.queue_free(); await process_frame; await process_frame
	check(is_equal_approx(main.xr_viewport.scaling_3d_scale,1.2),"Node removal restores altered render scale")
	main.queue_free(); await process_frame; await process_frame
	var result: Dictionary={"test":"xr_bottleneck_suite_lifecycle","checks":checks,"passed":errors.is_empty(),"errors":errors,"gpu_validated":false,"headset_tested":false}
	FileAccess.open("res://../runtime/evidence/xr-bottleneck-suite-smoke.json",FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	print(JSON.stringify(result)); quit(0 if errors.is_empty() else 1)
