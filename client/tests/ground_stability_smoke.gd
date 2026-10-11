extends SceneTree
const Timeline=preload("res://combat/action_timeline.gd")
func _initialize()->void:
 var rows:Array=[];var failures:Array=[]
 for mode:String in ["baseline", "100ms_gap_before_contact", "100ms_gap_after_contact", "tracking_lost", "incomplete_miss"]:
  var t:=Timeline.new();t.clock_ready=true;t.server_offset=100.;t.contact_evidence=true
  var e:Dictionary={"protocol":2,"id":"7","encounter_id":"7","attack_id":"1","target_id":"9","eligible_victim_ids":["9"],"sequence":1,"state_revision":1,"phase":"windup","role":"melee","server_now":100.,"age_ms":0.,"start":100.15,"delivery_at":101.55,"active_at":101.75,"end_at":101.95,"recover_at":104.,"aim_locked":false,"aim_revision":1,"origin":[0,0,0],"direction":[0,0,1],"range":3.,"radius":.45,"cosine":.5}
  t.ingest(e,.025);var receipts:Array=[]
  for frame in 230:
   var stamp:=.025+float(frame)/90.
   if stamp>=1.05 and not e.aim_locked:e.aim_locked=true;e.sequence=2;e.state_revision=2;t.ingest(e,stamp)
   if mode in ["100ms_gap_before_contact", "incomplete_miss"] and stamp>1.70 and stamp<1.80:continue
   if mode=="100ms_gap_after_contact" and stamp>1.80 and stamp<1.90:continue
   receipts.append_array(t.sample(stamp,Vector3(5,0,2) if mode=="incomplete_miss" else Vector3(0,0,2),"9",mode!="tracking_lost"))
  if receipts.size()!=(0 if mode in ["tracking_lost","incomplete_miss"] else 1):failures.append(mode)
  rows.append({"case":mode,"receipts":receipts.size(),"sampled_hit":t.attacks["7:1"].hit,"covered":t.attacks["7:1"].covered})
 print(JSON.stringify({"renderer":"dummy","native_execution":false,"observations":rows,"failures":failures,"passed":failures.is_empty()}));quit(0 if failures.is_empty() else 1)
