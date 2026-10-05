extends SceneTree
const Avatar = preload("res://scripts/avatar.gd")
const Cache = preload("res://scripts/animation_clip_cache.gd")
const NPCs = preload("res://scripts/ambient_npcs.gd")
class Views extends Node:
	var culling_enabled := true
	var headset := true
	var spectator := false
	var bounds_visible := true
	func is_bounds_visible(_bounds: AABB) -> bool: return bounds_visible
	func is_cell_visible(_cell: String) -> bool: return headset or spectator
var errors: Array[String] = []
var checks := 0
var world: Node3D
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: errors.append(message); push_error(message)
func make_actor(rest_x: float = 0.0) -> Node3D:
	var actor := Avatar.new()
	world.add_child(actor)
	actor.visual_root = Node3D.new()
	actor.add_child(actor.visual_root)
	actor.skeleton = actor.build_skeleton([{"name":"root","parent":-1,"rest_position":[rest_x,0,0],"rest_rotation":[0,0,0,1]}])
	actor.visual_root.add_child(actor.skeleton)
	actor.animation_player = actor.make_animation_player("Body")
	actor.face_player = actor.make_animation_player("Face")
	return actor
func _initialize() -> void: call_deferred("run")
func run() -> void:
	world = Node3D.new(); root.add_child(world)
	Cache.clear()
	var clip := {"source":"animation/test.ans","source_sha256":"source-provenance","length":2.0,"loop":true,"tracks":[{"name":"root","positions":[[0,4,0,5],[2,4,2,5]],"rotations":[]}]}
	var a := make_actor(); var b := make_actor()
	a.add_animation_clip("idle",clip,a.animation_player)
	b.add_animation_clip("idle",clip,b.animation_player)
	var original: Animation = a.animation_player.get_animation("idle")
	check(original==b.animation_player.get_animation("idle"),"Compatible actors share compiled immutable Animation")
	check(a.animation_player.get_animation_library("")!=b.animation_player.get_animation_library(""),"Actors retain independent animation libraries")
	a.animation_player.play("idle"); b.animation_player.play("idle")
	a.animation_player.seek(0.25,true); b.animation_player.seek(1.25,true)
	var face_clip := {"length":2.0,"loop":true,"tracks":[{"name":"root","positions":[],"rotations":[[0,0,0,0,1],[2,0,0.2,0,0.98]]}]}
	a.add_animation_clip("face_idle",face_clip,a.face_player)
	a.face_player.play("face_idle"); a.face_player.seek(0.4,true); a.face_player.speed_scale=2.0
	check(is_equal_approx(a.animation_player.current_animation_position,0.25) and is_equal_approx(b.animation_player.current_animation_position,1.25),"Shared clip does not share playback position")
	var modified: Dictionary = clip.duplicate(true); modified.tracks[0].positions[1][2] = 4.0
	b.add_animation_clip("changed",modified,b.animation_player)
	check(b.animation_player.get_animation("changed")!=original,"Changed source track content invalidates compiled resource")
	var key := Cache.key("idle",clip,a.animation_skeleton_key)
	var provenance := clip.duplicate(true); provenance.source_sha256 = "new-source"
	check(key!=Cache.key("idle",provenance,a.animation_skeleton_key),"Source provenance is part of compatibility key")
	var c := make_actor(3.0); c.add_animation_clip("idle",clip,c.animation_player)
	check(c.animation_player.get_animation("idle")!=original,"Different skeleton rest policy never shares clip")
	check(is_equal_approx(c.animation_player.get_animation("idle").position_track_interpolate(0,0.5).x,3.0),"Compiled root motion honors each skeleton rest position")
	b.animation_cache_enabled = false
	b.add_animation_clip("uncached",clip,b.animation_player)
	check(b.animation_player.get_animation("uncached")!=original,"Opt-out builds a private compiled clip")
	var npcs := NPCs.new(); world.add_child(npcs); npcs.set_process(false)
	var views := Views.new(); world.add_child(views); npcs.set_visibility_provider(views)
	npcs.observer = Vector3.ZERO
	var attachment := BoneAttachment3D.new(); attachment.bone_name="root"; attachment.override_pose=false; a.skeleton.add_child(attachment)
	npcs.records.test = {"avatar":a,"entry":{"cell_id":"test:1"},"animation":"idle","mood_restored":true,"equipment":[{"attachment":attachment,"bone_index":0}],"suspended":false,"hidden_elapsed":0.0,"paused_players":[]}
	views.headset=false
	npcs.update_visibility(0)
	check(not a.visible and not a.animation_player.active and npcs.records.test.suspended,"Hidden NPC rendering and animation stop without removing actor")
	npcs.update_visibility(0.75)
	check(is_equal_approx(a.animation_player.current_animation_position,0.25),"Hidden pose remains unevaluated while elapsed clock advances")
	views.spectator=true
	npcs.update_visibility(0.0)
	check(a.visible and a.animation_player.active and not npcs.records.test.suspended,"Spectator visibility alone resumes actor")
	check(is_equal_approx(a.animation_player.current_animation_position,1.0),"Resume restores elapsed loop phase")
	check(is_equal_approx(a.face_player.current_animation_position,1.9),"Independent face phase resumes with its own playback speed")
	check(is_equal_approx(a.skeleton.get_bone_pose_position(0).y,1.0),"Resumed bone pose evaluated before reveal")
	check(attachment.transform.is_equal_approx(a.skeleton.get_bone_global_pose(0)),"Rigid equipment follows resumed bone before reveal")
	views.spectator=false; npcs.update_visibility(0.21)
	npcs.update_visibility(4.5); views.headset=true; npcs.update_visibility(0)
	check(is_equal_approx(a.animation_player.current_animation_position,1.5),"Long hidden intervals wrap original clip phase")
	npcs.hidden_animation_enabled=false; views.headset=false; npcs.update_visibility(0.21)
	check(a.animation_player.active and not a.visible,"Hidden-animation opt-out preserves rendering cull but keeps animation active")
	a.tracking_mode=true; a.visible=true; npcs.hidden_animation_enabled=true; npcs.update_visibility(0)
	check(a.animation_player.active and a.visible,"Tracked avatar is never suspended or hidden by NPC policy")
	# Cache eviction cannot invalidate Animation references already held by players.
	for i in range(Cache.MAX_CLIPS+2):
		var resource := Animation.new(); resource.length=0.1
		Cache.publish("bounded_%d"%i,resource)
	check(Cache.statistics().resident_clips<=Cache.MAX_CLIPS and Cache.statistics().evictions>0,"Compiled resource cache has a hard LRU bound")
	check(a.animation_player.get_animation("idle")==original,"Eviction preserves resources held by live players")
	var actual := Avatar.new(); world.add_child(actual); actual.load_catalog()
	var model: Dictionary = actual.get_model(actual.catalog.races.human_male.body)
	var first := make_actor(); var second := make_actor()
	for actor in [first,second]:
		actor.visual_root.remove_child(actor.skeleton); actor.skeleton.queue_free()
		actor.skeleton = actor.build_skeleton(model.bones); actor.visual_root.add_child(actor.skeleton)
	Cache.clear()
	var start := Time.get_ticks_usec()
	for name in model.animations: first.add_animation_clip(name,model.animations[name],first.animation_player)
	var cold_usec := Time.get_ticks_usec()-start
	start = Time.get_ticks_usec()
	for name in model.animations: second.add_animation_clip(name,model.animations[name],second.animation_player)
	var warm_usec := Time.get_ticks_usec()-start
	for name in model.animations:
		check(first.animation_player.get_animation(name)==second.animation_player.get_animation(name),"Original imported compatible clip shares compiled resource: "+name)
	check(Cache.statistics().hits==model.animations.size(),"Every original human clip reused compiled tracks")
	a.tracking_mode=false; npcs.hidden_animation_enabled=true; views.headset=true; views.bounds_visible=false
	npcs.records.test.visibility_bounds=AABB(Vector3(-1,0,-1),Vector3(2,2,2))
	npcs.update_visibility(0.3)
	check(not a.visible and not a.animation_player.active,"Offscreen bounds suspend actors in a visible room")
	views.bounds_visible=true; npcs.update_visibility(0)
	check(a.visible and a.animation_player.active,"Bounds becoming visible restores actor without notifier dependency")
	views.bounds_visible=false; npcs.update_visibility(0.1)
	check(a.visible,"Brief offscreen head motion retains actor with 200ms hysteresis")
	views.culling_enabled=false; npcs.hidden_animation_enabled=false; npcs.update_visibility(0.3)
	check(a.visible and a.animation_player.active,"All-disabled baseline preserves NPC rendering and animation")
	npcs.hidden_animation_enabled=true; npcs.update_visibility(0)
	check(a.visible and not a.animation_player.active,"Animation suspension toggle is independent of visual culling")
	var one_shot := clip.duplicate(true); one_shot.loop=false
	a.animation_cache_enabled=false; a.add_animation_clip("one_shot",one_shot,a.animation_player)
	views.bounds_visible=true; npcs.update_visibility(0)
	a.animation_player.play("one_shot"); a.animation_player.seek(1.0,true)
	views.bounds_visible=false; npcs.update_visibility(0.3); npcs.update_visibility(4.0)
	views.bounds_visible=true; npcs.update_visibility(0)
	check(is_equal_approx(a.animation_player.current_animation_position,2.0),"Nonlooping hidden clip resumes at its end without wrapping")
	npcs.records.clear()
	world.queue_free(); await process_frame; await process_frame
	var result := {"test":"animation_cache_visibility","checks":checks,"passed":errors.is_empty(),"errors":errors,"cache":Cache.statistics(),"original_cold_compile_usec":cold_usec,"original_warm_compile_usec":warm_usec,"gpu_validated":false,"hardware_tested":false}
	FileAccess.open("res://../runtime/evidence/animation-cache-visibility-smoke.json",FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	print(JSON.stringify(result)); quit(0 if errors.is_empty() else 1)
