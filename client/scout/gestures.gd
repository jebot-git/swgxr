extends RefCounted
## Gesture input only. Native Core3 decides availability, costs and cooldowns.
const DIG_NEAR := 0.55
var previous_left:=Vector3.ZERO
var previous_right:=Vector3.ZERO
var have_previous:=false
var run_side:=0
var run_count:=0
var run_time:=0.0
var dig_hands: Array[Dictionary]=[{},{}]
var dig_count:=0
var dig_time:=0.0
var dig_latched:=false
var throw_samples: Array=[]
var clock:=0.0
func reset() -> void:
	have_previous=false;run_side=0;run_count=0;run_time=0;dig_count=0;dig_time=0;dig_hands=[{},{}];dig_latched=false;throw_samples.clear()
func sample(delta: float, head: Transform3D, left: Vector3, right: Vector3, ground_left: float, ground_right: float, tracked: bool) -> Dictionary:
	var out: Dictionary={"burst_run":false,"forage":false,"dig_hands":[]}
	if not tracked or not head.is_finite() or not left.is_finite() or not right.is_finite() or not is_finite(delta) or delta<=0 or delta>0.25: reset();return out
	clock+=delta;run_time+=delta;dig_time+=delta
	var l:=head.affine_inverse()*left;var r:=head.affine_inverse()*right
	if not have_previous: previous_left=l;previous_right=r;have_previous=true;return out
	var lv: Vector3=(l-previous_left)/delta;var rv: Vector3=(r-previous_right)/delta
	previous_left=l;previous_right=r
	if run_time>0.85: run_count=0;run_side=0
	# Arms must alternate front/back on opposite sides of the body, below head.
	var separation:=l.z-r.z
	var next:=1 if separation>0.16 else -1 if separation< -0.16 else 0
	var pumping:=lv.z*rv.z< -0.12 and l.y< -0.15 and r.y< -0.15 and l.y> -0.9 and r.y> -0.9
	if next!=0 and next!=run_side and pumping:
		if run_side!=0 and run_time<0.12: run_count=0
		run_side=next;run_time=0;run_count+=1
		if run_count>=6: out.burst_run=true;run_count=0
	var near_left:=ground_near(ground_left)
	var near_right:=ground_near(ground_right)
	if not near_left and not near_right:
		dig_count=0;dig_latched=false;dig_hands=[{},{}]
	elif not dig_latched:
		# Each hand completes its own strokes: alternating scoops must not cancel
		# each other, and the other hand may stay comfortably above the ground.
		if dig_time>4.0: dig_count=0;dig_hands=[{},{}];dig_time=0
		var stroke_left:=dig_stroke(0,left-head.origin,ground_left,near_left)
		var stroke_right:=dig_stroke(1,right-head.origin,ground_right,near_right)
		if stroke_left:out.dig_hands.append(0)
		if stroke_right:out.dig_hands.append(1)
		if stroke_left or stroke_right:
			dig_count+=1;dig_time=0
			if dig_count>=3: out.forage=true;dig_latched=true;dig_count=0
	return out
func ground_near(height: float) -> bool:
	return is_finite(height) and height>=-0.08 and height<DIG_NEAR
func dig_stroke(index: int, point: Vector3, height: float, near: bool) -> bool:
	if not near:
		dig_hands[index]={};return false
	var hand: Dictionary=dig_hands[index]
	if hand.is_empty():
		hand.axes=[]
		for axis in range(3):hand.axes.append({"extreme":point[axis],"direction":0,"armed":false})
	# Complete an out-and-back stroke along any axis. Distance hysteresis,
	# rather than speed or crossing an absolute floor height, admits both a
	# slow scoop and a quick shovel while rejecting tracking jitter/crouching.
	var scoop:=false
	for axis in range(3):
		var travel:Dictionary=hand.axes[axis]
		var value:float=point[axis]
		var threshold:=.08 if axis==1 else .12
		var displacement:float=value-float(travel.extreme)
		if travel.direction==0:
			if absf(displacement)>=.015:
				travel.direction=signf(displacement);travel.extreme=value
		elif displacement*float(travel.direction)>=0:travel.extreme=value
		elif absf(displacement)>=threshold:
			if travel.armed:scoop=true
			travel.direction=-float(travel.direction);travel.extreme=value;travel.armed=not travel.armed
	if scoop:
		# A diagonal shovel counts once, not once for each axis it crosses.
		for axis in range(3):hand.axes[axis]={"extreme":point[axis],"direction":0,"armed":false}
	return scoop
func reset_dig()->void:
	dig_count=0;dig_time=0;dig_latched=false;dig_hands=[{},{}]
func sample_throw(delta: float, head: Transform3D, hand: Vector3, held: bool) -> void:
	if not held or delta<=0 or delta>0.15: throw_samples.clear();return
	var point:=head.affine_inverse()*hand
	throw_samples.append({"time":clock,"point":point})
	while throw_samples.size()>2 and float(throw_samples[0].time)<clock-0.30: throw_samples.pop_front()
func valid_throw() -> bool:
	if throw_samples.size()<3: return false
	var first: Dictionary=throw_samples[0];var last: Dictionary=throw_samples[-1]
	var elapsed: float=last.time-first.time
	return elapsed>0.04 and elapsed<=0.35 and Vector3(last.point).distance_to(first.point)>=0.18 and Vector3(last.point).distance_to(first.point)/elapsed>=0.9
