extends RefCounted
## Raifslop casting/cranking adapted to SWG's timed up/right/left/reel actions.
## All input is in tracking space, excluding artificial locomotion and head yaw.
const Cast=preload("res://fishing/cast_motion.gd")
const Reel=preload("res://fishing/reel_tracker.gd")
var cast=Cast.new()
var reel=Reel.new()
var seeded:=false
var previous:=Transform3D.IDENTITY
var down:=true
var casting:=false
var stage:=-1
var neutral:=Vector3.ZERO
var pull_basis:=Basis.IDENTITY
var pull_held:=false
var reel_turns:=0.0
var recovery:=0.0
func reset()->void:
	seeded=false;down=true;casting=false;reel.engaged=false;reel_turns=0;pull_held=false;stage=-1;recovery=0
static func tip(pose:Transform3D)->Vector3:return pose*Vector3(0,0,-1.12)
func sample(pose:Transform3D,other:Vector3,trigger:float,grip:bool,dt:float,tracked:bool,current_stage:int,can_cast:bool)->Dictionary:
	if not tracked or not pose.is_finite() or not other.is_finite() or absf(pose.basis.determinant())<.01 or not is_finite(trigger):reset();return {}
	if not seeded:previous=pose;seeded=true;neutral=tip(pose);return {}
	var old:=previous;previous=pose
	if not is_finite(dt) or dt<=0 or dt>.1:reset();return {}
	var angle:=old.basis.orthonormalized().get_rotation_quaternion().angle_to(pose.basis.orthonormalized().get_rotation_quaternion())
	if pose.origin.distance_to(old.origin)>maxf(.15,12*dt) or angle>maxf(deg_to_rad(25),65*dt):reset();return {}
	recovery=maxf(0,recovery-dt)
	var was:=down
	if trigger<.25:down=false
	elif trigger>.65:down=true
	if current_stage!=stage:stage=current_stage;neutral=tip(pose);pull_basis=pose.basis;pull_held=false;reel_turns=0;casting=false
	var movement:=tip(pose)-tip(old)
	if current_stage==0:
		reel.engaged=false
		if down and not was and can_cast:
			cast=Cast.new();cast.begin(pose,Cast.controller_axis(pose));casting=true
		if casting and down:cast.sample_controller(movement,dt,pose,cast.axis,false)
		if casting and was and not down:
			casting=false
			if cast.committed():return {"cast_direction":cast.swing_travel.normalized(),"cast_distance":clampf(2.1+cast.swing_speed*1.5,2.1,10.0)}
		return {}
	casting=false
	var rate:float=reel.sample(other,grip,dt)
	reel_turns+=rate*dt
	if reel_turns>=.18 and recovery<=0:reel_turns=0;recovery=.45;return {"gesture":4}
	var displacement:=pull_basis.inverse()*(tip(pose)-neutral)
	if pull_held:
		if displacement.length()<.09:pull_held=false
		return {}
	if recovery>0:return {}
	var vertical:=tip(pose).y-neutral.y
	if vertical>.12 and movement.y/dt>.7:pull_held=true;recovery=.45;return {"gesture":1}
	if absf(displacement.x)>.24 and absf((pull_basis.inverse()*movement).x)/dt>.7:
		pull_held=true;recovery=.45;return {"gesture":2 if displacement.x>0 else 3}
	return {}
