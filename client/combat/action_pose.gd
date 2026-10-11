extends RefCounted
## Original NPC pose clock. No player/tracking/physics transforms are written.
var event:Dictionary={}
var local_anchor:=0.0
var server_anchor:=0.0
var sound_sent:=false
func ingest(value:Dictionary,local_now:float,transit:float=0.0)->void:
	if not value.has("animation"):return
	if event.is_empty() or value.attack_id!=event.attack_id or value.encounter_id!=event.encounter_id:
		local_anchor=local_now;server_anchor=float(value.get("_server_time_at_receive",float(value.server_now)+float(value.age_ms)/1000.0+clampf(transit,0,.5)));sound_sent=false
	event=value.duplicate(true)
func sample(local_now:float)->Dictionary:
	if event.is_empty():return {}
	var stamp:=server_anchor+local_now-local_anchor
	if event.phase=="cancelled" or stamp>=float(event.animation_end_at):event.clear();return {}
	var elapsed:=maxf(0,stamp-float(event.delivery_at))
	var hold:=stamp<float(event.delivery_at)
	var sound:=not hold and not sound_sent and stamp>=float(event.active_at)
	if sound:sound_sent=true
	return {"key":event.animation,"seconds":elapsed,"hold":hold,"sound":sound,"role":event.role,"attack_id":event.attack_id,"aim_revision":event.get("aim_revision",1),"aim_locked":event.get("aim_locked",true),"direction":event.get("direction",[0,0,1])}
