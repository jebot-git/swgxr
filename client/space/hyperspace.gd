extends Node3D
## Original cockpit particles/audio, driven by native task phases. XR tracking
## is never replaced by SWG's third-person cutscene camera or camera shake.
var assets=preload("res://combat/original_assets.gd").new()
var phase:="idle"
var iteration:=-1
var available:=false
func setup(_eye:Camera3D)->void:
	assets.directory=ProjectSettings.globalize_path("res://../runtime/assets/space_effects")
	available=assets.load_catalog()
	if not available:return

func observe(state:Dictionary,eye:Camera3D)->void:
	var next:=str(state.get("phase","idle"));var step:=int(state.get("iteration",-1))
	if next==phase and step==iteration:return
	phase=next;iteration=step
	if next=="idle":
		for child in get_children():child.queue_free()
	if not available:return
	var original:Dictionary=assets.catalog.hyperspace
	var audio:=get_node_or_null("/root/SWGSpatialAudio")
	if next=="countdown" and audio!=null:audio.play_original(assets,original.countdown_sound,eye.global_position,2)
	if next not in ["travel","arrival"]:return
	var stage:Dictionary=original.enter if next=="travel" else original.leave
	var pose:=eye.global_transform;pose.origin-=pose.basis.z*float(stage.offset)
	if not str(stage.particle).is_empty():
		var particles:=preload("res://space/original_particles.gd").new();add_child(particles);particles.global_transform=pose;particles.play(assets.catalog.particles.get(stage.particle,{}),assets)
	# CEF camera shake is intentionally not applied to tracked head/hands.
	if audio!=null:
		for sound:String in assets.catalog.effects.get(stage.effect,{}).get("sounds",[]):audio.play_original(assets,sound,eye.global_position,2)
	if audio!=null and not str(stage.sound).is_empty():audio.play_original(assets,stage.sound,eye.global_position,2)
