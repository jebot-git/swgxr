extends SceneTree
const Timeline=preload("res://combat/action_timeline.gd")
var errors:Array=[]
var checks:=0
func check(value:bool,label:String)->void:
	checks+=1
	if not value:errors.append(label);push_error(label)
func event()->Dictionary:
	return {"encounter_id":"10","attack_id":"1","id":"7","target_id":"9","sequence":1,"phase":"windup","role":"melee","cell_id":"0","server_now":10.,"age_ms":0.,"start":10.,"active_at":11.,"end_at":11.25,"recover_at":12.65,"range":3.,"radius":.35,"cosine":.5,"origin":[0,0,0],"direction":[0,0,1]}
func _initialize()->void:
	call_deferred("run")
func run()->void:
	var warning=preload("res://combat/action_combat.gd")
	var timing:=event();timing.delivery_at=11.;timing.active_at=11.333
	for pair:Array in [[9.,0.],[10.,0.],[10.25,.25],[10.5,.5],[10.75,.75],[11.,1.],[11.333,1.]]:
		check(is_equal_approx(warning.preparation_progress(timing,pair[0]),pair[1]),"Fill tracks native delivery time and stays full during delivery")
	var results:Array=[]
	for rtt:float in [.05,.1,.2]:
		for dodge:bool in [false,true]:
			var t:=Timeline.new();var e:=event();t.ingest(e,0,rtt*.5)
			var receipts:Array=[]
			for frame in 140:
				var now:=float(frame)/90.
				var feet:=Vector3(4,0,2) if dodge and now>.5 else Vector3(0,0,2)
				receipts.append_array(t.sample(now,feet,"9"))
			check(receipts.size()==1,"One receipt at RTT %s"%rtt)
			if not receipts.is_empty():check(receipts[0].contact!=dodge,"Visible footprint determines contact")
			check(t.sample(2,Vector3(0,0,2),"9").is_empty(),"No duplicate receipt")
			results.append({"rtt_ms":rtt*1000,"dodge":dodge,"receipts":receipts})
	var shared:=event();shared.eligible_victim_ids=["9","10","11"];shared.hit_policy="cleave"
	for player_id:String in ["9","10","11","12"]:
		var t:=Timeline.new();t.ingest(shared,0);var reports:Array=[]
		for frame in 140:reports.append_array(t.sample(float(frame)/90.,Vector3(0,0,2) if player_id!="11" else Vector3(5,0,2),player_id))
		check(reports.size()==(0 if player_id=="12" else 1),"Only roster members submit own contact: "+player_id)
		if not reports.is_empty():check(reports[0].contact==(player_id!="11"),"Non-target player's own position decides contact")
	var late:=Timeline.new();var e:=event();e.age_ms=1100;late.ingest(e,0)
	check(late.sample(.3,Vector3(4,0,2),"9").is_empty(),"Late warning cannot claim a miss")
	var stalled:=Timeline.new();stalled.ingest(event(),0);stalled.sample(.9,Vector3(4,0,2),"9")
	check(stalled.sample(1.3,Vector3(4,0,2),"9").is_empty(),"Frame stall invalidates coverage")
	var observer:=Timeline.new();observer.ingest(event(),0)
	check(observer.sample(1.3,Vector3.ZERO,"another-player").is_empty(),"Observer cannot submit victim contact")
	var cancelled:=Timeline.new();cancelled.ingest(event(),0);e=event();e.phase="cancelled";e.sequence=2;cancelled.ingest(e,.5)
	check(cancelled.sample(1.3,Vector3(0,0,2),"9").is_empty() and cancelled.attacks.is_empty(),"Interrupt clears pending contact")
	cancelled.ingest(event(),1.4)
	check(cancelled.attacks.is_empty(),"Old stream row cannot resurrect a cancelled attack")
	check(Timeline.contact(event(),Vector3(0,0,2)) and not Timeline.contact(event(),Vector3(0,0,-2)),"Committed aim has no rear hit")
	var tracking:=Timeline.new();e=event();e.merge({"aim_revision":1,"aim_locked":false,"lock_at":10.7,"delivery_at":11.})
	tracking.ingest(e,0)
	var changed:=e.duplicate(true);changed.direction=[.1,0,sqrt(.99)];changed.aim_revision=2;changed.sequence=2
	tracking.ingest(changed,.4)
	check(tracking.attacks["10:1"].event.direction==changed.direction,"Preparation updates shared warning and contact direction")
	changed.aim_locked=true;changed.sequence=3;tracking.ingest(changed,.72)
	tracking.ingest(e,.8)
	var corrupt:=changed.duplicate(true);corrupt.direction=[1,0,0];corrupt.sequence=4;tracking.ingest(corrupt,.9)
	check(tracking.attacks["10:1"].event.direction==changed.direction,"Locked direction rejects stale and inconsistent events")
	var tracked_receipts:Array=[]
	for frame in 140:tracked_receipts.append_array(tracking.sample(float(frame)/90.,Vector3(0,0,2),"9"))
	check(tracked_receipts.size()==1 and tracked_receipts[0].aim_revision==2,"Contact receipt names final locked revision")
	var uncommitted:=Timeline.new();uncommitted.ingest(e,0)
	var uncovered:Array=[]
	for frame in 140:uncovered.append_array(uncommitted.sample(float(frame)/90.,Vector3(4,0,2),"9"))
	check(uncovered.is_empty(),"Missing final lock cannot authorize a miss")
	var late_lock:=Timeline.new();late_lock.ingest(e,0);late_lock.ingest(changed,1.02)
	uncovered=[]
	for frame in 140:uncovered.append_array(late_lock.sample(float(frame)/90.,Vector3(4,0,2),"9"))
	check(uncovered.is_empty() and late_lock.late_locks==1,"Commit arriving after delivery invalidates contact coverage")
	var pose=preload("res://combat/action_pose.gd").new();e=event()
	e.merge({"animation":"action_pistol","delivery_at":11.,"animation_end_at":12.,"active_at":11.+1./3.},true)
	pose.ingest(e,0)
	check(pose.sample(.2).hold and pose.sample(.9).seconds==0,"Warning holds original first pose")
	check(is_equal_approx(pose.sample(1.1).seconds,.1) and not pose.sample(1.1).hold,"Delivery plays at original speed")
	check(not pose.sample(1.2).sound and pose.sample(1.34).sound and not pose.sample(1.35).sound,"One firing sound at authored marker")
	e.phase="recovery";e.sequence=3;pose.ingest(e,1.5)
	check(is_equal_approx(pose.sample(1.8).seconds,.8),"Early native settlement preserves full animation tail")
	check(pose.sample(2.01).is_empty(),"Completed clip releases locomotion")
	e.phase="windup";e.attack_id="2";pose.ingest(e,0);e.phase="cancelled";pose.ingest(e,.4)
	check(pose.sample(.5).is_empty(),"Authoritative cancellation releases held pose")
	print(JSON.stringify({"passed":errors.is_empty(),"checks":checks,"errors":errors,"renderer":"dummy","network":"simulated","cases":results}))
	quit(0 if errors.is_empty() else 1)
