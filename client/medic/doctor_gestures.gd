extends RefCounted
## Supply gestures in a patient-relative frame; never moves a tracked hand.
var key := ""
var phase := "clear"
var elapsed := 0.0
var hold := 0.0
var previous := Vector3.ZERO
var previous_other := Vector3.ZERO
var start := Vector3.ZERO
var extreme := Vector3.ZERO
var direction := Vector3.ZERO
var initialized := false

func reset() -> void:
	key="";phase="clear";elapsed=0;hold=0;initialized=false

func sample(delta:float,identity:String,ability:String,held:Vector3,other:Vector3,other_grip:float,permitted:bool)->bool:
	if not permitted or not is_finite(delta) or delta<=0 or delta>.15 or not held.is_finite() or not other.is_finite() or not is_finite(other_grip) or identity.is_empty() or ability not in ["reviveplayer","extinguishfire"]:
		reset();return false
	if identity!=key:
		reset();key=identity
	if initialized and (held.distance_to(previous)>maxf(.12,delta*3) or other.distance_to(previous_other)>maxf(.12,delta*3)):
		reset();return false
	var movement:=held.distance_to(previous) if initialized else INF
	previous=held;previous_other=other;initialized=true
	var contact:bool=held.length()<.38 and other.length()<.38 and held.distance_to(other)>=.12 and held.distance_to(other)<=.55
	# Every attempt starts with the held supply away from the patient. A
	# completed/aborted gesture cannot rearm by continuing ordinary contact.
	if phase=="clear":
		if held.length()>.44 and other_grip<.25:phase="approach";elapsed=0
		return false
	if phase=="latched":
		if held.length()>.44 and other_grip<.25:phase="approach";elapsed=0
		return false
	elapsed+=delta
	if elapsed>5:phase="clear";hold=0;return false
	if ability=="reviveplayer":
		if not contact:
			if phase in ["press","release"]:phase="clear";hold=0
			return false
		if phase=="approach" and other_grip>.65:phase="press";hold=0
		if phase=="press":
			if other_grip<.65:phase="clear";hold=0;return false
			hold+=delta
			if hold>=.65:phase="release"
		elif phase=="release" and other_grip<.25:
			phase="latched";return true
		return false
	# Blanket motion is a broad pass and return across the patient's torso,
	# followed by a short settled pat. It is neither a limb wrap nor a rub.
	if held.length()>.48:
		if phase!="approach":phase="clear"
		return false
	if phase=="approach":
		hold=hold+delta if held.length()<.35 and movement<maxf(.004,delta*.15) else 0.
		if hold>=.15:start=held;phase="sweep";hold=0
	elif phase=="sweep":
		var travel:=held-start
		if travel.length()>=.30:
			direction=travel.normalized();extreme=held;phase="return"
	elif phase=="return":
		if (held-extreme).dot(direction)>0:extreme=held
		if (extreme-held).dot(direction)>=.22 and (held-start).slide(direction).length()<.12:phase="settle";hold=0
	elif phase=="settle":
		if held.distance_to(start)>.20:hold=0;return false
		if held.distance_to(extreme)>maxf(.012,delta*.12):hold=0
		else:hold+=delta
		extreme=held
		if hold>=.20:phase="latched";return true
	return false
