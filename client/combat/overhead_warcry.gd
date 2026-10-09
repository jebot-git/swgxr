extends RefCounted
## Raise, lower and pump a held weapon. Head bobbing and static overhead poses do not qualify.
var phase:=0
var elapsed:=0.0
var peak:=0.0
var trough:=0.0
var head_start:=0.0
var weapon_id:=""
var previous:=Vector3.INF
var capturing:=false
func clear()->void:
	phase=0;elapsed=0;weapon_id="";previous=Vector3.INF;capturing=false
func sample(delta:float,hand:Dictionary,permitted:bool)->bool:
	var p:Vector3=hand.get("position",Vector3.INF)
	var relative:Vector3=hand.get("relative",Vector3.INF)
	var head_y:float=hand.get("head_y",INF)
	var item:=str(hand.get("item_id",""))
	if not permitted or not is_finite(delta) or delta<=0 or delta>.1 or not hand.get("tracked",false) or not p.is_finite() or not relative.is_finite() or not is_finite(head_y) or item.is_empty() or float(hand.get("grip",0))<.55 or float(hand.get("trigger",0))>=.5 or float(hand.get("support_trigger",0))>=.5:
		clear();return false
	for key:String in ["grip","trigger","support_trigger"]:
		if not is_finite(float(hand.get(key,0))):clear();return false
	if item!=weapon_id:clear();weapon_id=item
	if previous.is_finite() and p.distance_to(previous)>.30:clear();return false
	previous=p
	if absf(relative.x)>.8 or absf(relative.z)>.7:clear();return false
	capturing=relative.y>.15
	if relative.y<=.1:
		phase=1;elapsed=0;head_start=head_y;return false
	if phase==0:return false
	elapsed+=delta
	if elapsed>1.8 or absf(head_y-head_start)>.15:clear();return false
	if phase==1 and relative.y>=.35:phase=2;peak=p.y
	elif phase==2:
		peak=maxf(peak,p.y)
		if peak-p.y>=.16 and relative.y>=.15:phase=3;trough=p.y
	elif phase==3:
		trough=minf(trough,p.y)
		if p.y-trough>=.18 and relative.y>=.35:
			phase=0;elapsed=0;return true
	return false
