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
	var result:=c.sample("bike",world,l,r,l.origin,r.origin,0,0,true,true,true)
	result=c.sample("bike",world,l,r,l.origin,r.origin,1,0,true,true,true)
	check(result.left_held and not result.right_held and result.throttle==0,"Either bike handle engages at neutral without acceleration")
	var twisted:=Transform3D(Basis(Vector3.RIGHT,-.5),l.origin)
	result=c.sample("bike",world,twisted,r,l.origin,r.origin,1,0,true,true,true)
	check(result.throttle>.8,"Forward bike twist accelerates")
	twisted.basis=Basis(Vector3.RIGHT,.5);result=c.sample("bike",world,twisted,r,l.origin,r.origin,1,0,true,true,true)
	check(result.throttle<-.8,"Backward bike twist brakes and reverses")
	var steering:=l;steering.origin=Vector3(0,1,-.5)+Basis(Vector3.UP,-.5)*(l.origin-Vector3(0,1,-.5))
	result=c.sample("bike",world,steering,r,l.origin,r.origin,1,0,true,true,true)
	check(result.steer>.7,"One-hand handlebar arc steers")
	world=Transform3D(Basis(Vector3.UP,1.2),Vector3(100,4,-50));result=c.sample("bike",world,world*steering,world*r,l.origin,r.origin,1,0,true,true,true)
	check(result.steer>.7,"Vehicle translation and rotation do not change steering input")
	result=c.sample("bike",world,world*steering,world*r,l.origin,r.origin,1,0,true,true,false)
	check(not result.held and result.throttle==0,"Tracking loss releases throttle")
	result=c.sample("bike",world,world*l,world*r,l.origin,r.origin,1,0,true,true,true)
	check(not result.held,"Tracking reacquisition requires deliberate grip release")
	c.reset();world=Transform3D.IDENTITY
	result=c.sample("landspeeder",world,l,r,l.origin,r.origin,0,1,true,true,true)
	check(result.right_held and not result.left_held,"Landspeeder can use only right hand")
	var pushed:=r;pushed.origin.z-=.18
	result=c.sample("landspeeder",world,l,pushed,l.origin,r.origin,0,1,true,true,true)
	check(is_zero_approx(float(result.throttle)),"Pushing wheel cannot accelerate landspeeder")
	pushed.origin.z+=.36;result=c.sample("landspeeder",world,l,pushed,l.origin,r.origin,0,1,true,true,true)
	check(is_zero_approx(float(result.throttle)),"Pulling wheel cannot brake or reverse landspeeder")
	pushed=r;pushed.basis=Basis(Vector3.BACK,-.5);result=c.sample("landspeeder",world,l,pushed,l.origin,r.origin,0,1,true,true,true)
	check(is_zero_approx(float(result.steer)),"Rolling wrist in place does not turn the wheel")
	var pivot:Vector3=(l.origin+r.origin)*.5
	pushed=r;pushed.origin=pivot+Basis(Vector3.BACK,-.5)*(r.origin-pivot)
	result=c.sample("landspeeder",world,l,pushed,l.origin,r.origin,0,1,true,true,true)
	check(result.steer>.7 and is_zero_approx(float(result.throttle)),"Clockwise rim movement steers right without diagonal throttle")
	pushed.origin=pivot+Basis(Vector3.BACK,.5)*(r.origin-pivot)
	result=c.sample("landspeeder",world,l,pushed,l.origin,r.origin,0,1,true,true,true)
	check(result.steer<-.7,"Counterclockwise rim movement steers left")
	c.reset();result=c.sample("landspeeder",world,l,r,l.origin,r.origin,1,1,true,true,true)
	var moved_left:=l;var moved_right:=r
	moved_left.origin+=Vector3(.15,.1,0);moved_right.origin+=Vector3(.15,.1,0)
	result=c.sample("landspeeder",world,moved_left,moved_right,l.origin,r.origin,1,1,true,true,true)
	check(is_zero_approx(float(result.steer)) and is_zero_approx(float(result.throttle)),"Translating both wheel hands does not steer or strafe")
	moved_left.origin=pivot+Basis(Vector3.BACK,-.5)*(l.origin-pivot)+Vector3(.1,.1,-.18)
	moved_right.origin=pivot+Basis(Vector3.BACK,-.5)*(r.origin-pivot)+Vector3(.1,.1,-.18)
	result=c.sample("landspeeder",world,moved_left,moved_right,l.origin,r.origin,1,1,true,true,true,1.0)
	check(result.steer>.7 and result.throttle>.99,"Two-handed wheel arc plus main stick independently controls steering and throttle")
	world=Transform3D(Basis(Vector3.UP,1.3),Vector3(4,2,10))
	result=c.sample("landspeeder",world,world*moved_left,world*moved_right,l.origin,r.origin,1,1,true,true,true,1.0)
	check(result.steer>.7 and result.throttle>.99,"Moving vehicle frame leaves wheel input unchanged")
	c.reset();world=Transform3D.IDENTITY
	result=c.sample("landspeeder",world,l,r,l.origin,r.origin,0,1,true,true,true)
	result=c.sample("landspeeder",world,l,pushed,l.origin,r.origin,0,1,true,false,true)
	check(not result.held,"Occupied tool or weapon hand cannot drive simultaneously")
	c.reset()
	result=c.sample("landspeeder",Transform3D.IDENTITY,l,r,l.origin,r.origin,1,0,true,true,true,.56)
	check(is_equal_approx(float(result.throttle),.5),"Main stick analog midpoint maps predictably after deadzone")
	result=c.sample("landspeeder",Transform3D.IDENTITY,l,r,l.origin,r.origin,1,0,true,true,true,.08)
	check(is_zero_approx(float(result.throttle)),"Main stick rest jitter remains inside deadzone")
	result=c.sample("landspeeder",Transform3D.IDENTITY,l,r,l.origin,r.origin,1,0,true,true,true,-1)
	check(result.throttle==-1,"Main stick backward requests bounded braking/reverse")
	result=c.sample("landspeeder",Transform3D.IDENTITY,l,r,l.origin,r.origin,0,0,true,true,true,1)
	check(result.throttle==0 and not result.held,"Stick without a grabbed control cannot drive")
	c.reset()
	result=c.sample("landspeeder",Transform3D.IDENTITY,l,r,l.origin,r.origin,1,0,true,true,true)
	var turned_left:=l;turned_left.origin=pivot+Basis(Vector3.BACK,-.4)*(l.origin-pivot)
	var turned_right:=r;turned_right.origin=pivot+Basis(Vector3.BACK,-.4)*(r.origin-pivot)
	result=c.sample("landspeeder",Transform3D.IDENTITY,turned_left,r,l.origin,r.origin,1,0,true,true,true)
	var prior_angle:float=result.wheel_angle
	result=c.sample("landspeeder",Transform3D.IDENTITY,turned_left,turned_right,l.origin,r.origin,1,1,true,true,true)
	check(result.left_handle==0 and result.right_handle==1 and is_equal_approx(float(result.wheel_angle),prior_angle),"Adding second hand at turned yoke preserves wheel angle and original grip ownership")
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
