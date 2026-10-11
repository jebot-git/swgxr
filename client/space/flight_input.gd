extends RefCounted
## Pose gestures in the cockpit frame; never alter tracked hands, head or body.
const ARM_SECONDS:=.2
const STICK_ENTER:=.966 # Upright within 15 degrees; tilt freely after engagement.
const STICK_EXIT:=.5 # Release beyond 60 degrees.
const THROTTLE_ENTER:=.342 # Grip handle sideways within 20 degrees of horizontal.
const THROTTLE_EXIT:=.643
var stick_dwell:=0.0
var throttle_dwell:=0.0
var last_mode:=""
var last_dominant:=""
var stick_held:=false
var throttle_held:=false
var stick_origin:=Basis.IDENTITY
var throttle_origin:=Vector3.ZERO
var captured_throttle:=0.0
var throttle:=0.0
func reset()->void:
	stick_held=false;throttle_held=false;throttle=0;stick_dwell=0;throttle_dwell=0
func neutral()->Dictionary:return {"pitch":0.0,"yaw":0.0,"roll":0.0,"throttle":0.0}
func sample(settings:RefCounted,tracked:bool,left:Transform3D,right:Transform3D,_left_grip:float,_right_grip:float,left_stick:Vector2,right_stick:Vector2,seat:Transform3D,delta:float,hardware:Dictionary={},dominant:String="right")->Dictionary:
	if last_mode!=settings.mode or last_dominant!=dominant:
		reset();last_mode=settings.mode;last_dominant=dominant
	var output:=neutral()
	if settings.mode=="physical_hotas":
		stick_held=false;throttle_held=false
		if not hardware.get("available",false):throttle=0;return output
		for name in ["pitch","yaw","roll"]:output[name]=settings.axis(float(hardware.get(name,0))*(-1 if name in ["pitch","roll"] else 1),name)
		var axis:=float(hardware.get("throttle",-1))
		if not is_finite(axis):return neutral()
		output.throttle=clampf((axis*(-1 if settings.inverted.get("throttle",false) else 1)+1)*.5,0,1)
		return output
	if not tracked or not left.is_finite() or not right.is_finite() or not seat.is_finite() or absf(seat.basis.determinant())<.001:
		reset();return output
	if settings.mode=="motion_sticks":
		stick_held=false;throttle_held=false
		output.pitch=settings.axis(-right_stick.y,"pitch");output.roll=settings.axis(-right_stick.x,"roll");output.yaw=settings.axis(left_stick.x,"yaw")
		throttle=clampf(throttle+settings.axis(left_stick.y,"throttle")*clampf(delta,0,.1)*.5,0,1)
		output.throttle=throttle;return output
	var frame:=seat.affine_inverse()
	var main:Transform3D=frame*(right if dominant=="right" else left)
	var off:Transform3D=frame*(left if dominant=="right" else right)
	# OpenXR grip -Z runs along the handle toward the index finger; +Y
	# is not the handle axis (https://registry.khronos.org/OpenXR/specs/1.1/html/xrspec.html#semantic-path-standard-pose-identifiers).
	var upright:=(-main.basis.z).normalized().dot(Vector3.UP)
	var sideways:=absf((-off.basis.z).normalized().dot(Vector3.UP))
	var step:=clampf(delta,0,.05) if is_finite(delta) else 0.0
	if stick_held and upright<STICK_EXIT:stick_held=false;stick_dwell=0
	if throttle_held and sideways>THROTTLE_EXIT:throttle_held=false;throttle_dwell=0
	if not stick_held:
		stick_dwell=stick_dwell+step if upright>=STICK_ENTER else 0.0
		if stick_dwell>=ARM_SECONDS:stick_held=true;stick_origin=main.basis.orthonormalized()
	if not throttle_held:
		throttle_dwell=throttle_dwell+step if sideways<=THROTTLE_ENTER else 0.0
		if throttle_dwell>=ARM_SECONDS:
			throttle_held=true;throttle_origin=off.origin;captured_throttle=throttle
	if stick_held:
		# Cockpit axes stay consistent even with a comfortable wrist heading.
		var euler:Vector3=(main.basis.orthonormalized()*stick_origin.inverse()).get_euler()
		output.pitch=settings.axis(-euler.x/deg_to_rad(25),"pitch")
		output.yaw=settings.axis(euler.y/deg_to_rad(35),"yaw")
		output.roll=settings.axis(euler.z/deg_to_rad(25),"roll")
	if throttle_held:
		var travel:float=(throttle_origin.z-off.origin.z)/.28
		if settings.inverted.get("throttle",false):travel=-travel
		# Small positional deadband suppresses hand tremor without changing the full travel.
		travel=signf(travel)*maxf(0,absf(travel)-.015)/(1-.015)
		throttle=clampf(captured_throttle+travel,0,1)
	output.throttle=throttle
	return output
