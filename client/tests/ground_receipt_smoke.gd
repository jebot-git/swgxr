extends SceneTree
const Timeline=preload("res://combat/action_timeline.gd")
var failures:Array=[]
func _initialize()->void:
	var traces:Array=[]
	for delay:float in [.025,.075,.125,.2]:
		for dodge:bool in [false,true]:
			var t:=Timeline.new();t.clock_ready=true;t.server_offset=100.
			var event:Dictionary={"protocol":2,"id":"7","encounter_id":"7","attack_id":"1","target_id":"9","eligible_victim_ids":["9"],"sequence":1,"state_revision":1,"phase":"windup","role":"melee","server_now":100.,"age_ms":0.,"start":100.15,"delivery_at":101.55,"active_at":101.75,"end_at":101.95,"recover_at":104.,"aim_locked":false,"aim_revision":1,"origin":[0,0,0],"direction":[0,0,1],"range":3.,"radius":.45,"cosine":.5}
			t.ingest(event,delay)
			var receipts:Array=[]
			for frame in 230:
				var stamp:=delay+float(frame)/90.
				if stamp>=1.05 and not event.aim_locked:
					event.aim_locked=true;event.sequence=2;event.state_revision=2;t.ingest(event,stamp)
				receipts.append_array(t.sample(stamp,Vector3(5,0,2) if dodge else Vector3(0,0,2),"9"))
			if receipts.size()!=1:failures.append("Expected one receipt at delay %s"%delay)
			else:
				var r:Dictionary=receipts[0]
				if r.coverage_start<event.start or r.coverage_start>event.active_at:failures.append("Coverage outside native accepted interval at delay %s"%delay)
				if r.contact==dodge:failures.append("Contact does not match sampled feet")
				traces.append({"delay":delay,"dodge":dodge,"receipt":r})
	var report:Dictionary={"passed":failures.is_empty(),"errors":failures,"cases":traces,"renderer":"dummy","network":"simulated"}
	FileAccess.open("res://../runtime/evidence/ground-receipt-client.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print(JSON.stringify(report));quit(0 if failures.is_empty() else 1)
