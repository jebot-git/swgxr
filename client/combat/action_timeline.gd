extends RefCounted
## Shared-footprint action contacts. No RPG values are predicted here.
var attacks:Dictionary={}
var server_offset:=0.0
var clock_ready:=false
var retired:Dictionary={}
var rejected_late:=0
var receipts:=0
var aim_updates:=0
var aim_locks:=0
var late_locks:=0
func clear()->void:
	attacks.clear();retired.clear()
func key(event:Dictionary)->String:
	return str(event.encounter_id)+":"+str(event.attack_id)
func ingest(event:Dictionary,local_now:float,transit:float=0.0)->void:
	var id:=key(event)
	if retired.has(id):return
	if attacks.has(id):
		if int(event.get("state_revision",event.sequence))<=int(attacks[id].event.get("state_revision",attacks[id].event.sequence)):return
		var entry:Dictionary=attacks[id];var old:Dictionary=entry.event
		if event.has("aim_revision"):
			if int(event.aim_revision)<int(old.get("aim_revision",0)):return
			if old.get("aim_locked",false) and (not event.aim_locked or event.aim_revision!=old.aim_revision or event.direction!=old.direction):return
			if event.aim_revision!=old.get("aim_revision",0):aim_updates+=1
			if event.aim_locked and not old.get("aim_locked",false):
				aim_locks+=1
				if server_time(entry,local_now)>float(event.get("delivery_at",event.active_at)):
					entry.covered=false;late_locks+=1
		attacks[id].event=event.duplicate(true)
		return
	if event.phase in ["recovery","cancelled"]:
		retire(id);return
	if attacks.size()>=64:return
	var server_now:=local_now+server_offset if event.get("protocol",1)==2 and clock_ready else float(event.server_now)+float(event.age_ms)/1000.0+clampf(transit,0,.5)
	attacks[id]={"event":event.duplicate(true),"local_anchor":local_now,"server_anchor":server_now,"last_sample":server_now,"covered":server_now<=float(event.active_at),"hit":false,"sent":false,"coverage_start":server_now,"sample_position":[0,0,0]}
	if event.get("aim_locked",false):
		aim_locks+=1
		if server_now>float(event.get("delivery_at",event.active_at)):
			attacks[id].covered=false;late_locks+=1
	if server_now>float(event.active_at):rejected_late+=1
func retire(id:String)->void:
	retired[id]=true
	if retired.size()>256:retired.erase(retired.keys()[0])
func server_time(entry:Dictionary,local_now:float)->float:
	return float(entry.server_anchor)+local_now-float(entry.local_anchor)
static func contact(event:Dictionary,feet:Vector3)->bool:
	var o:Vector3=Vector3(event.origin[0],event.origin[1],event.origin[2])
	var d:Vector3=Vector3(event.direction[0],event.direction[1],event.direction[2])
	var p:=feet-o
	if not feet.is_finite() or (event.get("protocol",1)!=2 and absf(p.y)>2.5):return false
	var distance:=Vector2(p.x,p.z).length()
	if distance>float(event.range)+.35:return false
	var along:=p.x*d.x+p.z*d.z
	if event.role=="ranged":return along>=-.35 and absf(p.x*d.z-p.z*d.x)<=float(event.radius)+.35
	return distance<=.35 or along>=float(event.cosine)*maxf(0,distance-.35)
func sample(local_now:float,feet:Vector3,owner:String,valid:bool=true)->Array:
	var result:Array=[]
	for id:String in attacks.keys():
		var entry:Dictionary=attacks[id];var event:Dictionary=entry.event;var stamp:=server_time(entry,local_now)
		if event.phase=="cancelled" or stamp>float(event.recover_at)+1:
			attacks.erase(id);retire(id);continue
		if event.role=="support" or not eligible(event,owner) or entry.sent:continue
		if stamp>=float(event.active_at) and float(entry.last_sample)<=float(event.end_at):
			if not valid or stamp-float(entry.last_sample)>.075:entry.covered=false
			if event.has("aim_revision") and not event.aim_locked:entry.covered=false
			if stamp<=float(event.end_at):
				if not entry.hit:entry.sample_position=[feet.x,feet.y,feet.z]
				entry.hit=entry.hit or contact(event,feet)
		entry.last_sample=stamp
		if stamp>=float(event.end_at)+.025:
			entry.sent=true
			if not entry.covered or event.phase in ["recovery","cancelled"]:continue
			result.append({"action":"contact","encounter_id":str(event.encounter_id),"actor_id":str(event.id),"attack_id":str(event.attack_id),"aim_revision":int(event.get("aim_revision",1)),"contact":bool(entry.hit),"coverage_start":float(entry.coverage_start),"coverage_end":stamp})
			if event.get("protocol",1)==2:result[-1]["protocol"]=2;result[-1]["sample_position"]=entry.sample_position
			receipts+=1
	return result

func eligible(event:Dictionary,owner:String)->bool:
	return owner in event.eligible_victim_ids if event.has("eligible_victim_ids") else str(event.target_id)==owner
