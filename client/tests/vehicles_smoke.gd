extends SceneTree
var checks: Array=[]
func check(value: bool,label: String)->void:
	if not value:push_error(label);quit(1);assert(value,label)
	checks.append(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	check(load("res://vehicles/controller.gd").can_instantiate(),"Vehicle controller loads")
	check(load("res://scripts/main.gd").can_instantiate(),"Integrated client scripts load")
	var c:=SwgVehicleControls.new();var l:=Transform3D(Basis.IDENTITY,Vector3(-.26,1,-.5));var r:=Transform3D(Basis.IDENTITY,Vector3(.26,1,-.5));var world:=Transform3D.IDENTITY
	var remote_l:=l;remote_l.origin+=Vector3(3,1,2)
	var remote_r:=r;remote_r.origin+=Vector3(-3,2,1)
	var result:=c.sample("landspeeder",world,remote_l,remote_r,l.origin,r.origin,1,1,true,true,true)
	check(result.left_handle==0 and result.right_handle==1,"Crossed remote controller grabs bind their corresponding original handles")
	check(result.held and result.throttle==0 and result.steer==0,"Initial grip snaps visuals without initial throttle or steering impulse")
	var pivot:Vector3=(l.origin+r.origin)*.5
	var moved_l:=remote_l;var moved_r:=remote_r
	moved_l.origin+=Basis(Vector3.BACK,-.4)*(l.origin-pivot)-(l.origin-pivot)+Vector3(0,0,-.1125)
	moved_r.origin+=Basis(Vector3.BACK,-.4)*(r.origin-pivot)-(r.origin-pivot)+Vector3(0,0,-.1125)
	result=c.sample("landspeeder",world,moved_l,moved_r,l.origin,r.origin,1,1,true,true,true,-1)
	check(absf(float(result.wheel_angle)+.4)<.00001 and absf(float(result.throttle)-.5)<.00001,"Virtual original rim steers while independent physical push accelerates; joystick ignored")
	for i in 120:result=c.sample("landspeeder",world,moved_l,moved_r,l.origin,r.origin,1,1,true,true,true)
	check(absf(float(result.wheel_angle)+.4)<.00001 and absf(float(result.throttle)-.5)<.00001,"Stationary held controllers retain control state without autorecentering")
	result=c.sample("landspeeder",world,moved_l,moved_r,l.origin,r.origin,0,1,true,true,true)
	check(not result.left_held and result.right_held and absf(float(result.throttle)-.5)<.00001 and absf(float(result.wheel_angle)+.4)<.00001,"Releasing one hand preserves steering and throttle")
	moved_l.origin=Vector3(8,4,7)
	result=c.sample("landspeeder",world,moved_l,moved_r,l.origin,r.origin,1,0,true,true,true)
	check(result.left_held and not result.right_held and absf(float(result.throttle)-.5)<.00001 and absf(float(result.wheel_angle)+.4)<.00001,"Continuous transfer to other remote hand preserves control state")
	result=c.sample("landspeeder",world,moved_l,moved_r,l.origin,r.origin,0,0,false,false,false)
	check(result.left_held and result.suspended and not result.held and result.throttle==0 and absf(float(result.wheel_angle)+.4)<.00001,"Tracking suspension keeps latch and yoke pose but stops drive output")
	moved_l.origin+=Vector3(8,-4,3)
	result=c.sample("landspeeder",world,moved_l,moved_r,l.origin,r.origin,1,0,true,true,true)
	check(not result.suspended and absf(float(result.throttle)-.5)<.00001 and absf(float(result.wheel_angle)+.4)<.00001,"Tracking reacquisition rebases physical reference without an input jump")
	result=c.sample("landspeeder",world,moved_l,moved_r,l.origin,r.origin,0,0,true,true,true)
	check(not result.held and result.wheel_angle==0 and result.throttle_offset==0,"Both physical grips released restores neutral controls")
	c.reset();c.sample("landspeeder",world,l,r,l.origin,r.origin,1,1,true,true,true)
	var translated_l:=l;var translated_r:=r
	translated_l.origin+=Vector3(.6,.7,0);translated_r.origin+=Vector3(.6,.7,0)
	result=c.sample("landspeeder",world,translated_l,translated_r,l.origin,r.origin,1,1,true,true,true,1)
	check(result.steer==0 and result.throttle==0,"Common lateral or vertical translation cannot steer or throttle; joystick cannot throttle")
	translated_l.origin.z+=.2;translated_r.origin.z+=.2
	result=c.sample("landspeeder",world,translated_l,translated_r,l.origin,r.origin,1,1,true,true,true)
	check(result.throttle<-.99 and result.steer==0,"Pure model-backward pull brakes or reverses without steering")
	world=Transform3D(Basis(Vector3.UP,1.2),Vector3(100,4,-50))
	result=c.sample("landspeeder",world,world*translated_l,world*translated_r,l.origin,r.origin,1,1,true,true,true)
	check(result.throttle<-.99 and absf(float(result.steer))<.00001,"Vehicle heading and world translation do not change model-frame controls")
	c.reset();world=Transform3D.IDENTITY;c.sample("bike",world,l,r,l.origin,r.origin,1,0,true,true,true)
	var bike_l:=l;bike_l.origin=pivot+Basis(Vector3.UP,-.4)*(l.origin-pivot);bike_l.basis=Basis(Vector3.RIGHT,-.5)
	result=c.sample("bike",world,bike_l,r,l.origin,r.origin,1,0,true,true,true)
	check(result.throttle>.8 and result.steer>.5 and absf(float(result.wheel_angle)+.4)<.00001,"Bike handlebar arc turns yaw while original wrist twist accelerates")
	result=c.sample("bike",world,bike_l,r,l.origin,r.origin,1,0,false,true,true)
	check(result.left_held and result.suspended and result.throttle==0,"Unavailable held hand suspends without dropping the original handle")
	result=c.sample("bike",world,bike_l,r,l.origin,r.origin,0,0,true,true,true)
	check(not result.held and result.wheel_angle==0,"Bike controls neutralize only after physical release")
	c.reset();c.sample("landspeeder",world,l,r,l.origin,r.origin,1,0,true,true,true)
	result=c.sample("landspeeder",world,l,r,l.origin,r.origin,NAN,0,false,true,true)
	check(result.left_held and result.suspended,"Untracked hand with absent grip reading cannot fake a physical release")
	result=c.sample("landspeeder",world,l,r,l.origin,r.origin,0,0,false,false,true)
	check(not result.left_held and result.wheel_angle==0,"Valid physical release works while menu blocks drive availability")
	var motion:=SwgVehicleControls.advance(8,-1,0,15,8,9,1,.1)
	check(motion.speed>0 and motion.speed<8,"Reverse input brakes forward speed first")
	var speed:=8.0
	for i in range(20):speed=SwgVehicleControls.advance(speed,-1,0,15,8,9,1,.1).speed
	check(speed<0 and speed>=-8,"Continued braking enters bounded reverse")
	var jitter:=jitter_test()
	check(jitter.max_view_acceleration<=31,"View smoothing bounds packet correction acceleration")
	check(jitter.filtered_velocity_error<jitter.raw_velocity_error*.35,"View smoothing substantially suppresses network velocity jitter")
	check(jitter.seat_camera_error<.00001,"Vehicle seat and viewpoint use identical render-frame transform")
	check(jitter.head_tracking_error<.00001,"Local head tracking remains unsmoothed")
	var report:={"passed":true,"checks":checks,"jitter":jitter,"renderer":"dummy","scope":"Native controls and synthetic delayed-snapshot view regression; no GPU or live headset validation"}
	var f:=FileAccess.open("res://../runtime/evidence/vehicles-client.json",FileAccess.WRITE);f.store_string(JSON.stringify(report,"\t"));f.close();print(JSON.stringify(report));quit(0)
func jitter_test()->Dictionary:
	var smoother:=SwgVehicleControls.new();var dt:=1.0/90;var target:=Transform3D.IDENTITY
	var previous:=Vector3.ZERO;var raw_previous:=Vector3.ZERO;var previous_velocity:=Vector3.ZERO
	var raw_error:=0.0;var filtered_error:=0.0;var peak:=0.0;var camera_error:=0.0;var tracking_error:=0.0
	var packet_time:=0.0;var packet_position:=0.0;var packet_index:=0;var delay:=0.0
	var seat:=Transform3D(Basis.IDENTITY,Vector3(-.4,.7,.3));var origin_local:=Transform3D(Basis.IDENTITY,Vector3(0,-.5,0))
	for i in range(1080):
		var t:=i*dt
		if t>=packet_time:
			packet_index+=1;delay=[.08,.13,.06,.11][packet_index%4];packet_position=-8*(t-delay);packet_time=t+[.22,.30,.25,.34][packet_index%4]
		# Same bounded trajectory extrapolation used by vehicle presentation.
		target.origin.z=packet_position-8*(t-(packet_time-[.22,.30,.25,.34][packet_index%4]))
		var view:=smoother.smooth_pose(target,dt,i==0)
		var velocity: Vector3=(view.origin-previous)/dt;var raw_velocity: Vector3=(target.origin-raw_previous)/dt
		if i>270:
			filtered_error+=pow(velocity.z+8,2);raw_error+=pow(raw_velocity.z+8,2);peak=maxf(peak,(velocity-previous_velocity).length()/dt)
		var tracked:=Transform3D(Basis(Vector3.UP,sin(t)*.3),Vector3(sin(t)*.04,1.18,cos(t)*.04))
		var camera:=view*seat*origin_local*tracked
		camera_error=maxf(camera_error,(view.affine_inverse()*camera).origin.distance_to((seat*origin_local*tracked).origin))
		tracking_error=maxf(tracking_error,((view*seat*origin_local).affine_inverse()*camera).origin.distance_to(tracked.origin))
		previous=view.origin;raw_previous=target.origin;previous_velocity=velocity
	return {"max_view_acceleration":peak,"raw_velocity_error":sqrt(raw_error/809),"filtered_velocity_error":sqrt(filtered_error/809),"seat_camera_error":camera_error,"head_tracking_error":tracking_error,"simulated_seconds":12,"render_hz":90,"packet_intervals_ms":[220,300,250,340],"network_delays_ms":[80,130,60,110]}
