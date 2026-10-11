extends RefCounted
## Deliberate greeting only; opens an existing service, never confirms an action.
const NPC_KINDS=["trainer","delivery","recruiter","underworld","bounty_informant","pilot_trainer","herald","chassis_dealer","junk_dealer"]
const RANGE:=5.0
const STROKE:=0.12
const WINDOW:=1.8
var lanes:Dictionary={}
var cooldown:=0.0

func reset()->void:
	lanes.clear();cooldown=0

func interrupt()->void:
	for side in lanes:lanes[side]={"latched":lanes[side].get("latched",false)}

static func is_npc(record:Dictionary)->bool:
	return record.get("kind","") in NPC_KINDS or (record.get("kind","")=="vendor" and (str(record.get("template","")).begins_with("object/creature/") or str(record.get("template","")).begins_with("object/mobile/")))

static func raised(head:Transform3D,position:Vector3)->bool:
	if not head.is_finite() or not position.is_finite():return false
	var local:=head.affine_inverse()*position
	return local.y>=-.25 and local.y<=.5 and local.z<=-.08 and local.z>=-.85 and absf(local.x)<.9

static func target(records:Array,body:Vector3,head:Transform3D,visible:Callable)->Dictionary:
	if not visible.is_valid() or not head.is_finite():return {}
	var choices:Array=[];var seen:Dictionary={}
	for row:Dictionary in records:
		var id:=str(row.get("id",""))
		if id.is_empty() or not is_npc(row) or row.get("dead",false) or not row.get("position") is Vector3 or not row.position.is_finite():continue
		if body.distance_to(row.position)>RANGE:continue
		var eye:Vector3=row.position+Vector3.UP*1.4
		var delta:=eye-head.origin
		if delta.length()<.15:continue
		var angle:=rad_to_deg((-head.basis.z).angle_to(delta))
		if angle>30:continue
		# A hand, hat or shoulder can obscure one sample. Greet the visible body
		# from either side without testing its facing or screen normals.
		var clear:=false
		for height in [1.4, 1.0, .65]:
			if visible.call(head.origin,row.position+Vector3.UP*height,row):clear=true;break
		if not clear:continue
		# The same delivery NPC can expose multiple missions; preserve discovery
		# order for that identity, as the existing click interaction does.
		if seen.has(id):continue
		seen[id]=true;choices.append({"angle":angle,"row":row})
	choices.sort_custom(func(a,b):return a.angle<b.angle)
	if choices.is_empty():return {}
	if choices.size()>1 and choices[1].angle-choices[0].angle<3.0:return {}
	return choices[0].row

func sample(delta:float,head:Transform3D,hands:Dictionary,candidate:Dictionary,permitted:bool)->bool:
	if not is_finite(delta) or delta<=0 or delta>.12 or not head.is_finite():interrupt();return false
	cooldown=maxf(0,cooldown-delta)
	var key:=str(candidate.get("id",""))+":"+str(candidate.get("kind",""))+":"+str(candidate.get("mission_id",""))
	for side in ["left","right"]:
		var lane:Dictionary=lanes.get(side,{"latched":false})
		var hand:Dictionary=hands.get(side,{})
		var point:Variant=hand.get("position")
		if not hand.get("tracked",false) or not point is Vector3 or not point.is_finite():
			lanes[side]={"latched":lane.get("latched",false)};continue
		var motion:Variant=hand.get("wave_tip",point)
		if not motion is Vector3 or not motion.is_finite():lanes[side]={"latched":lane.get("latched",false)};continue
		var local:Vector3=head.affine_inverse()*motion
		if not raised(head,point):
			var lowered:=float(lane.get("lowered",0))+delta
			lanes[side]={"latched":lane.get("latched",false) and lowered<.35,"lowered":lowered};continue
		if not permitted or candidate.is_empty() or not hand.get("free",false) or not hand.get("open",false) or cooldown>0 or lane.get("latched",false):
			lanes[side]={"latched":lane.get("latched",false)};continue
		if lane.get("target","")!=key:
			lanes[side]={"latched":false,"target":key,"anchor":local.x,"extreme":local.x,"direction":0,"strokes":0,"time":0.0,"head":head,"last":local};continue
		var start:Transform3D=lane.head
		lane.time+=delta
		if local.distance_to(lane.last)>.14 or lane.time>WINDOW or head.origin.distance_to(start.origin)>.2 or rad_to_deg(head.basis.z.angle_to(start.basis.z))>12:
			lanes[side]={"latched":false};continue
		lane.last=local
		var direction:=int(lane.direction)
		if direction==0:
			if absf(local.x-float(lane.anchor))>=STROKE*.25:lane.direction=1 if local.x>lane.anchor else -1;lane.extreme=local.x
		else:
			if (local.x-float(lane.extreme))*direction>0:lane.extreme=local.x
			elif (float(lane.extreme)-local.x)*direction>=STROKE:lane.direction=-direction;lane.extreme=local.x;lane.strokes+=1
		lanes[side]=lane
		if lane.strokes>=3 and lane.time>=.3:
			for other in ["left","right"]:lanes[other]={"latched":true}
			cooldown=2.0;return true
	return false
