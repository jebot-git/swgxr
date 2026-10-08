extends RefCounted
const Forearm=preload("res://scout/mask_scent_gesture.gd")
const Hands=preload("res://scripts/tracked_hand_input.gd")
var motion=preload("res://medic/bandage_gesture.gd").new()
func reset()->void:motion.reset()
func frame(medic:Node,delta:float)->void:
	var app:Node=medic.app
	var services:Variant=app.get("services")
	var permitted:bool=medic.body.active and not medic.body.feedback.combat_blocked() and medic.bag.allowed and medic.age<3 and is_instance_valid(services) and services.party_hand_free("left") and services.party_hand_free("right")
	permitted=permitted and bool(app.get("xr_focused")) and not bool(app.get("loading_stage")) and not bool(app.get("session_leaving"))
	var tracker=XRServer.get_tracker("head")
	var pose:XRPose=tracker.get_pose("default") if tracker!=null else null
	permitted=permitted and pose!=null and pose.has_tracking_data
	var ability:Dictionary={}
	for entry:Dictionary in medic.state.get("abilities",[]):
		if entry.id=="firstaid":ability=entry
	permitted=permitted and not ability.is_empty()
	var chosen:Dictionary={};var nearest:=INF
	if permitted:
		for hand_side in ["left","right"]:
			var hand:XRController3D=medic.rig.get_node(hand_side.capitalize()+"Hand")
			if not Hands.controller_tracked(hand):permitted=false;break
			if hand.get_float("grip")>=.65 or hand.get_float("trigger")>=.65:continue
			for person:Dictionary in medic.state.get("players",[])+[medic.state.get("self",{})]:
				if not person.get("healable",false) or not person.get("needs",{}).get("firstaid",false):continue
				var own:bool=str(person.id)==str(app.datapad_character_id)
				var avatar:Node3D=app.avatar if own else medic.people.get(str(person.id))
				if not is_instance_valid(avatar):continue
				for arm_side in ["left","right"]:
					if own and hand_side==arm_side:continue
					var arm:Dictionary=Forearm.forearm(avatar.skeleton,arm_side)
					if arm.is_empty():continue
					var distance:float=hand.global_position.distance_to(Vector3(arm.wrist).lerp(arm.elbow,.5))
					if distance>.36 or distance>=nearest:continue
					nearest=distance;chosen={"key":str(person.id)+":"+arm_side+":"+hand_side,"id":str(person.id),"hand":hand.global_position,"wrist":arm.wrist,"elbow":arm.elbow}
	if chosen.is_empty():
		motion.sample(delta,"",Vector3.ZERO,Vector3.ZERO,Vector3.ZERO,permitted);return
	if motion.sample(delta,chosen.key,chosen.hand,chosen.wrist,chosen.elbow,permitted) and not medic.busy and float(ability.get("cooldown_seconds",0))<=0:
		medic.request("bandage",{"target_id":chosen.id})
