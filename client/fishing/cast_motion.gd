extends RefCounted
# Adapted from jebot-git/raifslop a2912df; see server/FISHING_PROTOCOL.md.
## Measure in tracking space. A reversal identifies a swing regardless of the
## starting rod angle; looking around and walking cannot supply cast power.
var raised := false
var retreat := 0.0
var swing_travel := Vector3.ZERO
var swing_speed := 0.0
var back_travel := Vector3.ZERO
var forward_window:Array[Dictionary]=[]
var peak_forward_speed:=0.0
var stroke_forward:=0.0
var stroke_back:=0.0
var candidate_travel:=Vector3.ZERO
var candidate_speed:=0.0
const WINDOW_SECONDS:=.08
enum Phase { PREPARE, BACKSWING, FORWARD, COMMITTED }
var phase:=Phase.PREPARE
var axis:=Vector3.ZERO
var reverse_seconds:=0.0
func begin(_pose:Transform3D,initial_axis:Vector3,preparation:Dictionary={})->void:
	axis=initial_axis
	if not preparation.is_empty():
		axis=preparation.axis;back_travel=preparation.back
		stroke_back=back_travel.length();raised=true;phase=Phase.BACKSWING
func committed()->bool:return phase==Phase.COMMITTED


static func controller_axis(pose:Transform3D)->Vector3:
	# When the shaft is vertical its projected forward is almost zero and
	# noisy. The shaft-up axis still defines the controller's casting plane.
	var direction:Vector3=-pose.basis.z
	if absf(direction.y)>.75 or pose.basis.y.y<0:
		# Keep the casting plane pointing forward past vertical. Switching back
		# to shaft projection here used to invert the gate during a backswing.
		direction=-pose.basis.y if direction.y>0 else pose.basis.y
	direction.y=0
	return direction.normalized()

func sample_controller(movement: Vector3, delta: float, _rod_pose: Transform3D, initial_axis: Vector3, completed: bool) -> float:
	if not is_finite(delta) or delta<=0 or not movement.is_finite():return 0.0
	if axis.length_squared()<.01:axis=initial_axis
	var travel:=movement.dot(axis)
	if travel<-.001:
		# The end of an overhand arc turns downward and can briefly project
		# backwards. It is follow-through, not a fresh deliberate backswing.
		if phase==Phase.COMMITTED and -travel<movement.length()*.65:
			stroke_back=0;reverse_seconds=0;back_travel=Vector3.ZERO;forward_window.clear();return travel
		stroke_back-=travel;reverse_seconds+=delta
		back_travel+=Vector3(movement.x,0,movement.z)
		forward_window.clear()
		# A preparatory wiggle can already have satisfied the host's gesture.
		# A fresh deliberate backswing must rearm measurement for the real cast.
		if stroke_back>=.06 and (phase!=Phase.COMMITTED or reverse_seconds>=.025):
			raised=true;stroke_forward=0.0
			phase=Phase.BACKSWING;swing_travel=Vector3.ZERO;swing_speed=0.0
			peak_forward_speed=0.0;candidate_travel=Vector3.ZERO;candidate_speed=0.0
	elif travel>.001 and raised:
		if phase==Phase.BACKSWING and back_travel.length()>=.06:
			# Use the measured backswing plane, keeping its established sign.
			var measured:Vector3=-back_travel.normalized()
			if measured.dot(axis)>.5:axis=measured
		stroke_back=0.0;reverse_seconds=0;back_travel=Vector3.ZERO;stroke_forward+=travel
		if phase!=Phase.COMMITTED:phase=Phase.FORWARD
		forward_window.append({"movement":Vector3(movement.x,0,movement.z),"dt":delta})
		var duration:=0.0
		for entry in forward_window:duration+=entry.dt
		# Integrate an exact 80 ms window, including a partial oldest sample.
		while forward_window.size()>1 and duration-forward_window[0].dt>=WINDOW_SECONDS:
			duration-=forward_window[0].dt;forward_window.pop_front()
		var velocities:Array[Vector3]=[]
		var weights:Array[float]=[]
		var measured_seconds:=0.0
		for i in forward_window.size():
			var entry:Dictionary=forward_window[i]
			var seconds:float=entry.dt-minf(maxf(duration-WINDOW_SECONDS,0.0),entry.dt) if i==0 else entry.dt
			measured_seconds+=seconds
			velocities.append(entry.movement/entry.dt);weights.append(seconds)
		# Time-weighted medoid rejects isolated lateral wrist/tracking spikes.
		# Vector distances (rather than component medians) preserve the result
		# when the identical physical cast is rotated around the play space.
		var robust_velocity:=Vector3.ZERO
		var best_cost:=INF;var selected_weight:=0.0
		for i in velocities.size():
			var cost:=0.0
			for j in velocities.size():cost+=velocities[i].distance_to(velocities[j])*weights[j]
			if cost<best_cost-.000001:
				best_cost=cost;robust_velocity=velocities[i]*weights[i];selected_weight=weights[i]
			elif absf(cost-best_cost)<.000001:
				robust_velocity+=velocities[i]*weights[i];selected_weight+=weights[i]
		robust_velocity/=maxf(selected_weight,.000001)
		# Average the accepted arc around the medoid. Selecting one sample as
		# the entire launch direction made smooth curved swings depend on which
		# frame happened to win at 72/90/120 Hz. Bound isolated lateral spikes.
		var centre:=robust_velocity
		var cutoff:=maxf(1.0,centre.length()*.65)
		var total_weight:=0.0
		robust_velocity=Vector3.ZERO
		for i in velocities.size():
			var weight:float=weights[i]*minf(1.0,cutoff/maxf(.000001,velocities[i].distance_to(centre)))
			robust_velocity+=velocities[i]*weight;total_weight+=weight
		robust_velocity/=maxf(total_weight,.000001)
		var displacement:=robust_velocity*measured_seconds
		# The not-yet-filled part is rest at the reversal, not a one-frame peak.
		var forward_speed:=displacement.dot(axis)/WINDOW_SECONDS
		if forward_speed>peak_forward_speed:
			peak_forward_speed=forward_speed;candidate_travel=displacement
			candidate_speed=displacement.length()/WINDOW_SECONDS
		if stroke_forward>=.10:
			swing_travel=candidate_travel;swing_speed=candidate_speed;phase=Phase.COMMITTED
	elif travel<=.001:forward_window.clear()
	if completed:retreat=maxf(0,retreat-travel)
	return travel

func swing_distance() -> float:
	return clampf(5.0 + swing_speed * 1.5, 5.0, 24.0)

func sample(movement: Vector3, _rod_pose: Transform3D, _head_height: float, axis: Vector3, completed := false) -> float:
	var travel := movement.dot(axis)
	if travel < 0: raised = true
	if not raised: return 0.0
	if completed: retreat = maxf(0, retreat-travel)
	return travel

func release_allowed(_rod_pose: Transform3D, _head_height: float, _axis: Vector3) -> bool:
	return raised
