extends RefCounted
## Local monotonic timing only. Native receipts still own acceptance and damage.
const MAX_COMPENSATION_SECONDS := 0.250
const MAX_UNSENT_SECONDS := 0.750

static func ordinary(shot:Dictionary)->bool:
	return str(shot.get("kind",""))!="melee" and str(shot.get("ability_id","" )).is_empty() and str(shot.get("delivery","bolt"))=="bolt" and not shot.has("volley_mark_id")

static func launch_age(launched_usec:int,now_usec:int)->float:
	return clampf(float(now_usec-launched_usec)/1000000.0,0,MAX_COMPENSATION_SECONDS)

static func recovery(shot:Dictionary,mutation:Dictionary,request_seconds:float,now_usec:int)->float:
	var interval:=maxf(0,float(mutation.get("interval_seconds",0)))
	if not ordinary(shot) or not mutation.get("latency_compensated",false):return interval
	# Respect our launch cadence AND the server's earliest permitted arrival.
	# Account for reply transit and the following request transit, bounded to
	# 250 ms in total. A stalled reply never banks a burst of catch-up shots.
	var elapsed:=maxf(0,float(now_usec-int(shot.get("launched_usec",now_usec)))/1000000.0)
	var rtt:=clampf(request_seconds,0,MAX_COMPENSATION_SECONDS) if is_finite(request_seconds) else 0.0
	return maxf(maxf(0,interval-elapsed),maxf(0,float(mutation.get("cooldown_remaining_seconds",interval))-rtt))
