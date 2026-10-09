extends RefCounted
## Tracking-only gesture evidence. All poses are in the same head-relative,
## player-facing frame; the rig never moves tracking or assists muzzle aim.
var previous_main:=Vector3.INF
var previous_support:=Vector3.INF
var neutral_time:=0.0
var armed:=false
var latched:=false
var pose_name:=""
var pose_time:=0.0
var fan_phase:=""
var fan_age:=0.0
var fan_strokes:=0
var fan_main:=Transform3D.IDENTITY
var fan_support:=Vector3.ZERO
var capturing:=false

func clear()->void:
	previous_main=Vector3.INF;previous_support=Vector3.INF;neutral_time=0;armed=false;latched=false;pose_name="";pose_time=0;fan_phase="";fan_age=0;fan_strokes=0;capturing=false

func sample(delta:float,main:Transform3D,support:Transform3D,dominant:String,main_trigger:float,support_trigger:float,support_grip:float,permitted:bool,available:Array)->String:
	capturing=false
	if not permitted or not is_finite(delta) or delta<=0 or delta>.1 or not main.is_finite() or not support.is_finite() or not is_finite(main_trigger) or not is_finite(support_trigger) or not is_finite(support_grip):clear();return ""
	if previous_main.is_finite() and (main.origin.distance_to(previous_main)>.35 or support.origin.distance_to(previous_support)>.35):clear();return ""
	previous_main=main.origin;previous_support=support.origin
	var side:=1.0 if dominant=="right" else -1.0
	var p:=main.origin;var off:=support.origin
	var forward:=-main.basis.z.normalized()
	var free:bool=main_trigger<.2 and support_trigger<.2 and support_grip<.25
	var bond:bool=free and p.x*side>.1 and p.x*side<.55 and p.y>-.95 and p.y<-.48 and p.z>-.55 and p.z<.1 and off.x*side<-.5 and absf(off.y+.18)<.3 and absf(off.z)<.4 and forward.dot(Vector3.FORWARD)>.6
	var gangster:bool=free and p.y>-.35 and p.y<.12 and p.z<-.14 and p.z>-.7 and p.x*side>-.15 and p.x*side<.65 and absf(main.basis.y.normalized().dot(Vector3.RIGHT))>.8 and forward.dot(Vector3.FORWARD)>.6 and off.distance_to(p)>.35
	var local:=main.affine_inverse()*off
	var fan_zone:bool=free and absf(local.x)<.16 and local.y>.025 and local.y<.34 and local.z>-.09 and local.z<.23
	var stance:="bond" if bond else "gangster" if gangster else ""
	var neutral:bool=free and stance.is_empty() and not fan_zone
	neutral_time=neutral_time+delta if neutral else 0.0
	if latched:
		if neutral_time>=.2:latched=false;armed=true
		return ""
	if not armed:
		if neutral_time>=.2:armed=true
		return ""
	if not free:armed=false;neutral_time=0;pose_name="";pose_time=0;fan_phase="";fan_strokes=0;return ""
	if not stance.is_empty():
		fan_phase="";fan_strokes=0
		pose_time=pose_time+delta if stance==pose_name else delta;pose_name=stance
		capturing=true
		if pose_time>=.8:
			latched=true;armed=false;pose_time=0
			return "run_and_gun" if "run_and_gun" in available else ""
		return ""
	pose_name="";pose_time=0
	if not fan_zone:fan_phase="";fan_strokes=0;return ""
	if fan_phase.is_empty():
		if local.y>=.2:fan_phase="down";fan_main=main;fan_support=off;fan_age=0;fan_strokes=0
		return ""
	fan_age+=delta;capturing=true
	# Moving the pistol beneath a still offhand, whole-body translation and
	# wrist rotation supply no stroke. Require the free hand's own travel.
	if fan_age>1.4 or main.origin.distance_to(fan_main.origin)>.065 or main.basis.y.normalized().dot(fan_main.basis.y.normalized())<.94 or main.basis.z.normalized().dot(fan_main.basis.z.normalized())<.94:
		fan_phase="";fan_strokes=0;armed=false;neutral_time=0;return ""
	if fan_phase=="down" and local.y<=.11 and (off-fan_support).dot(fan_main.basis.y.normalized())<=-.085:
		fan_strokes+=1;fan_phase="up";fan_support=off
		if fan_strokes==2:
			latched=true;armed=false;fan_phase=""
			return "fan_shot" if "fan_shot" in available else ""
	elif fan_phase=="up" and local.y>=.2 and (off-fan_support).dot(fan_main.basis.y.normalized())>=.085:
		fan_phase="down";fan_support=off
	return ""
