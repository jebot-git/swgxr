extends SceneTree
const Timing=preload("res://combat/latency_policy.gd")
var errors:Array=[]
var checks:=0
func check(value:bool,label:String)->void:
	checks+=1
	if not value:errors.append(label);push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	var launched:=10000000
	var shot:Dictionary={"launched_usec":launched}
	for rtt in [0.0,.05,.15,.25,.5,1.0]:
		var mutation:Dictionary={"latency_compensated":true,"interval_seconds":1.0,"cooldown_remaining_seconds":.75}
		var remaining:=Timing.recovery(shot,mutation,rtt,launched+int(rtt*1000000))
		check(remaining>=maxf(0,1.0-rtt),"Local cadence respected at RTT "+str(rtt))
		check(is_equal_approx(remaining,maxf(maxf(0,1-rtt),.75-minf(.25,rtt))),"Receipt transit reconciled at RTT "+str(rtt))
		check(Timing.recovery(shot,{"interval_seconds":1.0},rtt,launched+int(rtt*1000000))==1.0,"Legacy server remains conservative at RTT "+str(rtt))
	check(Timing.launch_age(launched,launched+900000)==.25 and Timing.launch_age(launched,launched-10000)==0,"Unsent launch age is bounded and nonnegative")
	for change in [{"ability_id":"showdown"},{"ability_id":"flurry_shot"},{"delivery":"guided_bolt"},{"delivery":"scatter"},{"delivery":"rocket"},{"kind":"melee"},{"volley_mark_id":"1"}]:
		var special:=shot.duplicate();special.merge(change)
		check(not Timing.ordinary(special) and Timing.recovery(special,{"latency_compensated":true,"interval_seconds":1.0,"cooldown_remaining_seconds":.75},.25,launched+250000)==1.0,"Special timing unchanged "+str(change))
	var live:=preload("res://combat/live_world.gd").new()
	var state:=preload("res://combat/weapon_state.gd").new();state.clock=2.;state.next_shot=2.8
	var now:=Time.get_ticks_usec()
	live.shots["latency"]={"shot":{"launched_usec":now-200000},"ammo_state":state,"accepted":false}
	live.combat_receipt({"kind":"fire","shot_id":"latency"},{"_request_elapsed_seconds":.2,"mutation":{"success":true,"shot_id":"latency","latency_compensated":true,"interval_seconds":1.0,"cooldown_remaining_seconds":.75}})
	check(live.shots.latency.accepted,"Latency-compensated native receipt still required for acceptance")
	check(state.next_shot<=2.801 and live.next_launch_usec<=now+801000,"Native receipt does not restart full cooldown after RTT")
	# Known unsent commands may refund; uncertain transmitted commands may not.
	state.rounds=1;state.profile={"capacity":5}
	live.shots["stale"]={"shot":{"launched_usec":Time.get_ticks_usec()-1000000},"ammo_state":state,"ammo_spent":1,"accepted":false}
	var request:Dictionary={"kind":"fire","shot_id":"stale","payload":{}}
	check(not live.prepare_combat_request(request) and not live.shots.has("stale") and state.rounds==2,"Unsent backlog is cancelled and refunded before transport")
	live.prepare_combat_request(request)
	check(state.rounds==2,"Unsent cancellation cannot refund twice")
	live.shots["fresh"]={"shot":{"launched_usec":Time.get_ticks_usec()},"accepted":false}
	request={"kind":"fire","shot_id":"fresh","payload":{}}
	check(live.prepare_combat_request(request) and request.payload.has("_client_launch_usec"),"Fresh ordinary launch carries dispatch-time metadata")
	live.free()
	var report:Dictionary={"passed":errors.is_empty(),"checks":checks,"errors":errors,"transport":"synthetic delayed receipts","renderer":"dummy","xr":false}
	print(JSON.stringify(report));FileAccess.open("res://../runtime/evidence/combat-latency-client.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	quit(0 if errors.is_empty() else 1)
