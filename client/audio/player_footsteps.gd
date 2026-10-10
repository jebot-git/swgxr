extends Node3D
## Tracking still owns body/head/hands. Footstep cadence follows actual travel.
var emitter:=preload("res://audio/mobile_emitter.gd").new()
var previous:=Vector3.INF
var distance:=0.0
func _ready()->void:
	add_child(emitter);emitter.ambient_allowed=false;emitter.animation_driven=true
func observe(position:Vector3,template:String,grounded:bool,enabled:bool)->void:
	global_position=position
	var traveled:=Vector2(position.x,position.z).distance_to(Vector2(previous.x,previous.z)) if previous.is_finite() else 0.0
	previous=position
	emitter.observe(template,0,enabled and grounded)
	if not enabled or not grounded or traveled>1.5:
		distance=0;emitter.events.clear();return
	distance+=traveled
	if distance>=.8:
		distance=fmod(distance,.8);emitter.queue_event("footstep")
