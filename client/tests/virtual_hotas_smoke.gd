extends SceneTree
const Controls=preload("res://space/flight_input.gd")
const Preferences=preload("res://space/preferences.gd")
var checks:=0
var failures:Array[String]=[]
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failures.append(message);push_error(message)
func run_sample(c:RefCounted,p:RefCounted,main:Transform3D,off:Transform3D,seat:Transform3D=Transform3D.IDENTITY,dominant:String="right",grips:float=0,sticks:Vector2=Vector2.ZERO,dt:float=.016)->Dictionary:
	# Fixtures describe a handle with +Y up; convert to the actual OpenXR grip -Z handle.
	var grip:=Transform3D(Basis(Vector3.RIGHT,PI/2),Vector3.ZERO)
	return c.sample(p,true,seat*(off if dominant=="right" else main)*grip,seat*(main if dominant=="right" else off)*grip,grips,grips,sticks,sticks,seat,dt,{},dominant)
func _initialize()->void:
	var p:=Preferences.new();p.mode="virtual_hotas"
	for dominant in ["left","right"]:
		var c:=Controls.new()
		var main:=Transform3D(Basis.IDENTITY,Vector3(.7,.9,-.8))
		var off:=Transform3D(Basis(Vector3.FORWARD,PI/2),Vector3(-.7,.9,-.8))
		var seat:=Transform3D(Basis.from_euler(Vector3(.25,1.7,-.3)),Vector3(50,15,90))
		run_sample(c,p,main,off,seat,dominant)
		check(not c.stick_held and not c.throttle_held,dominant+": brief pose does not engage")
		for frame in 15:run_sample(c,p,main,off,seat,dominant)
		check(c.stick_held and c.throttle_held,dominant+": gestures engage in a rotated cockpit")
		for axis in ["pitch","roll","yaw"]:
			main.basis=Basis(Vector3.RIGHT if axis=="pitch" else Vector3.BACK if axis=="roll" else Vector3.UP,deg_to_rad(-25 if axis=="pitch" else 25 if axis=="roll" else 35))
			var output:=run_sample(c,p,main,off,seat,dominant)
			check(output[axis]>.99,dominant+": full "+axis)
			var buttons:=run_sample(c,p,main,off,seat,dominant,1,Vector2.ONE)
			check(is_equal_approx(output[axis],buttons[axis]),dominant+": buttons do not change "+axis)
		main.basis=Basis.IDENTITY;off.origin.z-=.14
		var halfway:=run_sample(c,p,main,off,seat,dominant)
		check(halfway.throttle>.48 and halfway.throttle<.51,dominant+": half travel")
		off.basis=Basis.IDENTITY
		check(is_equal_approx(run_sample(c,p,main,off,seat,dominant).throttle,halfway.throttle) and not c.throttle_held,dominant+": released throttle holds")
		off.origin+=Vector3(0,0,.6);off.basis=Basis(Vector3.FORWARD,-PI/2)
		for frame in 15:run_sample(c,p,main,off,seat,dominant)
		check(is_equal_approx(c.throttle,halfway.throttle),dominant+": regrip position has no throttle jump")
		off.origin.z-=.28
		check(run_sample(c,p,main,off,seat,dominant).throttle>.99,dominant+": throttle saturates")
		off.origin.z+=.56
		check(run_sample(c,p,main,off,seat,dominant).throttle<.01,dominant+": pull back stops")
		main.basis=Basis(Vector3.RIGHT,deg_to_rad(70))
		check(run_sample(c,p,main,off,seat,dominant).pitch==0 and not c.stick_held,dominant+": hand outside pose releases steering")
		c.reset();main.basis=Basis.IDENTITY
		for frame in 15:run_sample(c,p,main,off,seat,dominant)
		off.origin.z-=.28
		check(run_sample(c,p,main,off,seat,dominant).throttle>.99,dominant+": resumed gesture works")
		var lost:Dictionary=c.sample(p,false,off,main,0,0,Vector2.ZERO,Vector2.ZERO,seat,.016,{},dominant)
		check(lost.throttle==0 and not c.stick_held and not c.throttle_held,dominant+": tracking loss neutralizes all")
		check(run_sample(c,p,main,off,seat,dominant).throttle==0 and not c.stick_held,dominant+": recovery requires a fresh dwell")
		for frame in 15:run_sample(c,p,main,off,seat,dominant)
		main.origin.x=NAN
		check(run_sample(c,p,main,off,seat,dominant).throttle==0 and not c.stick_held,dominant+": invalid pose neutralizes input")
	print(JSON.stringify({"checks":checks,"failures":failures,"renderer":"dummy","tracking":"mocked"}))
	quit(0 if failures.is_empty() else 1)
