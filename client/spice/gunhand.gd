extends RefCounted
## Virtual held-weapon pose only. Inputs are raw tracking copies, never modified.
var locked_id:=""
var last_time:=-1.0
var previous_relative:=Vector3.ZERO
var filtered:=Transform3D.IDENTITY
var initialized:=false
var was_sticky:=false
var reacquire_after:=0.0
var lowering_distance:=0.0
var episode_id:=""
func reset()->void:
	locked_id="";last_time=-1;initialized=false;was_sticky=false;reacquire_after=0;lowering_distance=0;episode_id=""
func sample(requested:Transform3D,physical:Transform3D,head:Transform3D,now:float,policy:Dictionary,acquire:Callable,target:Callable)->Transform3D:
	var delta:=clampf(now-last_time,0,.1) if last_time>=0 else 0.0
	var relative:=physical.origin-head.origin
	var local:=head.basis.inverse()*relative
	var downward:=-(relative-previous_relative).dot(head.basis.y)/delta if delta>.00001 else 0.0
	if delta>.00001:lowering_distance=lowering_distance+downward*delta if downward>.6 else 0.0
	var below_view:=local.y<-.35 and local.y<minf(-.35,local.z*.75)
	var sticky:bool=policy.sticky_aim
	if not sticky:locked_id=""
	elif not was_sticky or episode_id!=str(policy.get("episode_id","")):locked_id="";reacquire_after=now
	if sticky and not locked_id.is_empty() and below_view and downward>.9 and lowering_distance>=.12:
		locked_id="";reacquire_after=now+.5;lowering_distance=0
	if sticky and locked_id.is_empty() and now>=reacquire_after and not below_view and acquire.is_valid():locked_id=str(acquire.call(requested))
	var result:=requested
	if sticky and not locked_id.is_empty() and target.is_valid():
		var point:Variant=target.call(locked_id)
		if point is Vector3 and point.is_finite() and point.distance_squared_to(result.origin)>.01:
			var direction:Vector3=(point-result.origin).normalized()
			var up:=requested.basis.y if absf(direction.dot(requested.basis.y))<.98 else requested.basis.x
			result.basis=Basis.looking_at(direction,up)
		else:locked_id="";reacquire_after=now+.5
	var lag:=float(policy.lag_seconds)
	if lag>0 and initialized:result=filtered.interpolate_with(result,1-exp(-delta/lag))
	filtered=result;initialized=true
	result=shake(result,head,policy)
	if now>last_time:previous_relative=relative;last_time=now
	episode_id=str(policy.get("episode_id",""));was_sticky=sticky
	return result

static func shake(pose:Transform3D,head:Transform3D,policy:Dictionary,side:="right")->Transform3D:
	var result:=pose;var tremor:=float(policy.tremor)
	if tremor<=0:return result
	var phase:=float(policy.elapsed)+(0.17 if side=="left" else 0.0)
	result.basis=result.basis*Basis.from_euler(Vector3(sin(phase*TAU*6.1),sin(phase*TAU*7.7+.8),sin(phase*TAU*5.3))*tremor)
	result.origin+=head.basis*Vector3(sin(phase*TAU*6.7),sin(phase*TAU*5.9),0)*tremor*.14
	return result

func suspend()->void:
	# Stowing/tracking loss stops virtual pose history, not the active lock.
	# A fresh physical lowering gesture or native target/phase expiry releases it.
	last_time=-1;initialized=false;lowering_distance=0
