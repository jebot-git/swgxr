extends RefCounted
## Grip captures are relative to authored cockpit controls, never avatar poses.
var stick_held:=false
var throttle_held:=false
var stick_origin:=Basis.IDENTITY
var throttle_origin:=Vector3.ZERO
var captured_throttle:=0.0
var throttle:=0.0
var released:Dictionary={"stick":true,"throttle":true}
func reset()->void:
	stick_held=false;throttle_held=false;throttle=0;released={"stick":false,"throttle":false}
func neutral()->Dictionary:return {"pitch":0.0,"yaw":0.0,"roll":0.0,"throttle":0.0}
func sample(settings:RefCounted,tracked:bool,left:Transform3D,right:Transform3D,left_grip:float,right_grip:float,left_stick:Vector2,right_stick:Vector2,seat:Transform3D,delta:float,hardware:Dictionary={})->Dictionary:
	var output:=neutral()
	if settings.mode=="physical_hotas":
		stick_held=false;throttle_held=false
		if not hardware.get("available",false):throttle=0;return output
		for name in ["pitch","yaw","roll"]:output[name]=settings.axis(float(hardware.get(name,0))*(-1 if name in ["pitch","roll"] else 1),name)
		var axis:=float(hardware.get("throttle",-1))
		if not is_finite(axis):return neutral()
		output.throttle=clampf((axis*(-1 if settings.inverted.get("throttle",false) else 1)+1)*.5,0,1)
		return output
	if not tracked or not is_finite(left_grip) or not is_finite(right_grip):
		reset();return output
	if settings.mode=="motion_sticks":
		stick_held=false;throttle_held=false
		output.pitch=settings.axis(-right_stick.y,"pitch");output.roll=settings.axis(-right_stick.x,"roll");output.yaw=settings.axis(left_stick.x,"yaw")
		throttle=clampf(throttle+settings.axis(-left_stick.y,"throttle")*clampf(delta,0,.1)*.5,0,1)
		output.throttle=throttle;return output
	var local_left:Transform3D=seat.affine_inverse()*left
	var local_right:Transform3D=seat.affine_inverse()*right
	var stick_anchor:=Vector3(.28,.60,-.32)
	var throttle_anchor:=Vector3(-.28,.60,-.32)
	if right_grip<.3:stick_held=false;released.stick=true
	if left_grip<.3:throttle_held=false;released.throttle=true
	if not stick_held and released.stick and right_grip>.65 and local_right.origin.distance_to(stick_anchor)<settings.grip_radius:
		stick_held=true;released.stick=false;stick_origin=local_right.basis
	if not throttle_held and released.throttle and left_grip>.65 and local_left.origin.distance_to(throttle_anchor)<settings.grip_radius:
		throttle_held=true;released.throttle=false;throttle_origin=local_left.origin;captured_throttle=throttle
	if stick_held:
		if local_right.origin.distance_to(stick_anchor)>.65:stick_held=false
		else:
			var euler:Vector3=(stick_origin.inverse()*local_right.basis).get_euler()
			output.pitch=settings.axis(-euler.x/deg_to_rad(25),"pitch")
			output.yaw=settings.axis(euler.y/deg_to_rad(35),"yaw")
			output.roll=settings.axis(euler.z/deg_to_rad(25),"roll")
	if throttle_held:
		if local_left.origin.distance_to(throttle_anchor)>.65:throttle_held=false
		else:throttle=clampf(captured_throttle+(throttle_origin.z-local_left.origin.z)/.28,0,1)
	output.throttle=throttle
	return output
