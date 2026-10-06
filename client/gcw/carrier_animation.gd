extends RefCounted
## Exact original Lambda ASH: root(loop_sky) <-> prone(loop_ground), land/takeoff LINKs.
## No native phase timestamp exists: late observers start at the appropriate loop.
const TEMPLATE:="object/creature/npc/theme_park/lambda_shuttle.iff"
var avatar:Node3D
var posture:=-1
var available:=false
func configure(value:Node3D)->bool:
	avatar=value
	if avatar.race_id!=TEMPLATE:return false
	var library:AnimationLibrary=avatar.animation_player.get_animation_library("")
	for key in ["carrier_land","carrier_takeoff","carrier_ground","carrier_sky"]:
		if not avatar.ensure_animation(key):return false
		var source:Dictionary=avatar.get_model(str(avatar.animation_library[key].path))
		# Shared humanoid clip resources remove root X/Z. Never mutate those caches;
		# only this untracked carrier gets private, exact original root flight tracks.
		var animation:Animation=avatar.animation_player.get_animation(key).duplicate(true)
		for track:Dictionary in source.get("tracks",[]):
			if track.get("name","")!="root":continue
			var index:=animation.find_track(NodePath("Skeleton:root"),Animation.TYPE_POSITION_3D)
			if index<0:continue
			for k in range(animation.track_get_key_count(index)-1,-1,-1):animation.track_remove_key(index,k)
			for keyframe:Array in track.get("positions",[]):animation.position_track_insert_key(index,float(keyframe[0]),Vector3(keyframe[1],keyframe[2],keyframe[3]))
		library.remove_animation(key);library.add_animation(key,animation)
	# Source shuttle origin is authored; humanoid sole-to-ground normalization
	# would shift its original landing clearance and ramp height by several metres.
	avatar.visual_root.position=Vector3.ZERO
	available=true;return true
func apply(next:int)->void:
	if not available or next==posture:return
	var grounded:=next==2
	var loop:="carrier_ground" if grounded else "carrier_sky"
	var transition:="carrier_land" if grounded else "carrier_takeoff"
	avatar.animation_player.clear_queue()
	avatar.animation_player.speed_scale=1
	avatar.animation_player.play(loop if posture<0 else transition)
	if posture>=0:avatar.animation_player.queue(loop)
	avatar.animation_player.advance(0)
	posture=next
