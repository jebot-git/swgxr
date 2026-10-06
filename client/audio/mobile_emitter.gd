extends Node3D
## Follows a rendered native entity; never owns movement or gameplay state.
var source_template:=""
var speed:=0.0
var damage:=0.0
var active:=true
var moving:=false
var initialized:=false
var fresh_until:=0
var events:Array[String]=[]
func _ready()->void:add_to_group("swg_mobile_audio")
func observe(template:String,velocity:float,enabled:bool,wear:=0.0)->void:
	source_template=template;speed=absf(velocity);active=enabled;damage=clampf(wear,0,1)
	var next_moving:=speed>(.15 if moving else .35)
	if initialized and active and next_moving!=moving:queue_event("accel" if next_moving else "decel")
	moving=next_moving;initialized=true;fresh_until=Time.get_ticks_msec()+8000
func queue_event(event:String)->void:
	if events.size()<4:events.append(event)
func audible()->bool:
	return active and is_visible_in_tree() and Time.get_ticks_msec()<=fresh_until
