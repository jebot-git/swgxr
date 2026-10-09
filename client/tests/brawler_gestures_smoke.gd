extends SceneTree
const Gesture=preload("res://combat/brawler_gestures.gd")
var checks:=0
var errors:Array=[]
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:errors.append(label);push_error(label)
func hands(kind:String,offhand:="left")->Dictionary:
	var result:Dictionary={"left":{"position":Vector3(-.2,-.65,-.3),"grip":0.,"trigger":0.,"tracked":true,"free":true,"upright":1.},"right":{"position":Vector3(.2,-.65,-.3),"grip":1.,"trigger":0.,"tracked":true,"free":true,"upright":1.}}
	if kind=="center_of_being":result[offhand].position=Vector3(0,-.3,-.4);result[offhand].grip=0.
	if kind=="berserk":
		result.left.position=Vector3(-.65,-.1,0);result.right.position=Vector3(.65,-.1,0);result.left.grip=1.;result.right.grip=1.
	return result
func hold(g:RefCounted,h:Dictionary,offhand:="left",seconds:=1.)->Array:
	var out:Array=[]
	for i in range(int(seconds/.02)):
		var result:String=g.sample(.02,h,offhand,true)
		if not result.is_empty():out.append(result)
	return out
func _initialize()->void:
	for kind:String in ["center_of_being","berserk"]:
		for side:String in ["left","right"]:
			var g=Gesture.new();var h:=hands(kind,side)
			check(hold(g,h,side)==[kind],"Both handednesses recognize held pose: "+kind+side)
			check(hold(g,h,side,2.).is_empty(),"Maintaining gesture never retriggers")
			g.sample(.02,hands("none"),side,true)
			check(hold(g,h,side)==[kind],"Neutral posture rearms")
		for fault:String in ["tracking","trigger","occupied","fist","position"]:
			var h:=hands(kind)
			if fault=="tracking":h.left.tracked=false
			if fault=="trigger":h.right.trigger=1.
			if fault=="occupied":h.left.free=false
			if fault=="fist":h.left.grip=1. if kind=="center_of_being" else 0.
			if fault=="position":h.left.position=Vector3.INF
			check(hold(Gesture.new(),h).is_empty(),"Reject invalid pose: "+kind+fault)
		var g=Gesture.new();var h:=hands(kind)
		check(hold(g,h,"left",.4).is_empty(),"Short hold does not trigger")
		g.sample(.02,h,"left",false)
		check(hold(g,h,"left",.4).is_empty(),"Focus loss resets incomplete hold")
		g.sample(.5,h,"left",true)
		check(hold(g,h,"left",.4).is_empty(),"Tracking gap resets incomplete hold")
	var h:=hands("center_of_being");h.left.upright=0.
	check(hold(Gesture.new(),h).is_empty(),"Horizontal hand is not meditation sign")
	var report:Dictionary={"checks":checks,"errors":errors,"tracking":"mocked","headset_tested":false}
	FileAccess.open("res://../runtime/evidence/brawler-gestures.json",FileAccess.WRITE).store_string(JSON.stringify(report));print(JSON.stringify(report));quit(0 if errors.is_empty() else 1)
