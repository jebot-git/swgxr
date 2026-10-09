extends RefCounted
## Bolt-cycle evidence uses a frozen rifle orientation and current grip origin,
## so shared body/weapon translation cannot supply bolt travel. The support
## hand must leave the fore-end, grasp beside the receiver, pull, push, release,
## and regrip the fore-end. No tracked object is animated by this recognizer.
var capturing:=false
var phase:=""
var neutral_time:=0.
var age:=0.
var phase_age:=0.
var reference:=Transform3D.IDENTITY
var reference_head:=Transform3D.IDENTITY
var foreend:=Vector3.ZERO
var receiver:=Vector3.ZERO
var previous_hand:=Vector3.INF
var previous_main:=Vector3.INF
var previous_axis:=Vector3.ZERO

func clear()->void:
	capturing=false;phase="";neutral_time=0;age=0;phase_age=0;previous_hand=Vector3.INF;previous_main=Vector3.INF;previous_axis=Vector3.ZERO

func sample(delta:float,main:Transform3D,support:Transform3D,head:Transform3D,dominant:String,main_trigger:float,support_trigger:float,main_grip:float,support_grip:float,supported:bool,permitted:bool)->String:
	capturing=false
	if not permitted or not is_finite(delta) or delta<=0 or delta>.1 or not main.is_finite() or not support.is_finite() or not head.is_finite() or not is_finite(main_trigger) or not is_finite(support_trigger) or not is_finite(main_grip) or not is_finite(support_grip) or main_trigger>=.2 or support_trigger>=.2 or main_grip<.65:clear();return ""
	var axis:=-main.basis.z.normalized()
	if previous_hand.is_finite() and (support.origin.distance_to(previous_hand)>.18 or main.origin.distance_to(previous_main)>.15 or axis.dot(previous_axis)<.96):clear();return ""
	previous_hand=support.origin;previous_main=main.origin;previous_axis=axis
	var head_local:Vector3=head.affine_inverse()*main.origin
	if head_local.y<-.8 or head_local.y>-.08 or head_local.z<-.8 or head_local.z>.08 or absf(head_local.x)>.65 or absf(axis.y)>.45:clear();return ""
	if phase.is_empty():
		if supported and support_grip>=.65:
			neutral_time+=delta
			if neutral_time>=.25:reference=main;reference_head=head;foreend=main.affine_inverse()*support.origin
			return ""
		if neutral_time<.25 or support_grip>=.25:clear();return ""
		phase="approach";age=0;phase_age=0
	capturing=true;age+=delta;phase_age+=delta
	# Movement, head turns and body turns cannot substitute for bolt travel.
	if age>3.2 or main.origin.distance_to(reference.origin)>.14 or axis.dot(-reference.basis.z)<.97 or head.basis.z.dot(reference_head.basis.z)<.94 or head.origin.distance_to(reference_head.origin)>.18:clear();return ""
	var hand:Vector3=reference.basis.inverse()*(support.origin-main.origin)
	var mirror:=1. if dominant=="right" else -1.
	var at_receiver:bool=hand.x*mirror>.035 and hand.x*mirror<.20 and hand.y>-.015 and hand.y<.18 and hand.z>-.14 and hand.z<.07
	if phase=="approach":
		if phase_age>1.2:clear();return ""
		if support_grip>=.65:
			if not at_receiver:clear();return ""
			receiver=hand;phase="pull";phase_age=0
	elif phase=="pull":
		if support_grip<.65 or absf(hand.x-receiver.x)>.065 or absf(hand.y-receiver.y)>.065 or hand.z-receiver.z>.24:clear();return ""
		if hand.z-receiver.z>=.11 and phase_age>=.12:phase="push";phase_age=0
	elif phase=="push":
		if support_grip<.65 or absf(hand.x-receiver.x)>.065 or absf(hand.y-receiver.y)>.065 or hand.z-receiver.z>.24 or hand.z-receiver.z<-.05:clear();return ""
		if absf(hand.z-receiver.z)<.025 and phase_age>=.12:phase="release";phase_age=0
	elif phase=="release":
		if hand.distance_to(receiver)>.075:clear();return ""
		if support_grip<.25:phase="regrip";phase_age=0
	elif phase=="regrip":
		if support_grip>=.65:
			if hand.distance_to(foreend)>.10:clear();return ""
			if supported:
				clear();capturing=true;return "rifleman_focus"
	return ""
