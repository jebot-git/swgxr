extends SceneTree
const Gesture=preload("res://combat/tka_gestures.gd")
const IDS=["tka_sweep","tka_half_spin","tka_volley","indomitable_focus"]
var checks:=0
var errors:Array=[]
var seen:Array=[]
var detector=Gesture.new()
var hands:Dictionary={}
func check(value:bool,label:String)->void:
	checks+=1
	if not value:errors.append(label);push_error(label)
func reset()->void:
	detector.clear();seen.clear()
	hands={"left":{"position":Vector3(-.25,-.3,-.3),"grip":1.,"trigger":0.,"tracked":true,"free":true},"right":{"position":Vector3(.25,-.3,-.3),"grip":1.,"trigger":0.,"tracked":true,"free":true}}
func tick(dt:=.02,permitted:=true,available:Array=IDS,selected:=true)->void:
	var result:String=detector.sample(dt,hands,permitted,available,selected)
	if not result.is_empty():seen.append(result)
func sweep(side:String,available:Array=IDS)->void:
	var sign_value:=1. if side=="left" else -1.
	hands[side].position.x=-.55*sign_value;tick(.02,true,available)
	for i in range(16):hands[side].position.x+=.04*sign_value;tick(.02,true,available)
func half_spin(sign_value:float)->void:
	hands.left.position.x=-.65*sign_value;hands.right.position.x=-.4*sign_value;tick()
	for i in range(17):
		hands.left.position.x+=.04*sign_value;hands.right.position.x+=.04*sign_value;tick()
func volley(first:="left")->void:
	tick()
	for side:String in [first,"right" if first=="left" else "left",first]:
		for i in range(6):hands[side].position.z-=.04;tick()
		for i in range(6):hands[side].position.z+=.04;tick()
func _initialize()->void:
	for side:String in ["left","right"]:
		reset();sweep(side);check(seen==["tka_sweep"],side+" sweeping punch once")
		for i in range(50):tick()
		check(seen.size()==1,"Held sweep pose does not repeat")
	for sign_value:float in [-1.,1.]:
		reset();half_spin(sign_value);check(seen==["tka_half_spin"],"Both hands select half-spin without also firing sweep")
	for side:String in ["left","right"]:
		reset();volley(side);check(seen==["tka_volley"],side+" leading alternating volley once")
	reset()
	for i in range(100):tick()
	check(seen.is_empty(),"Stationary fists do not activate")
	reset();hands.left.trigger=1.;hands.right.trigger=1.;volley();check(seen.is_empty(),"Trigger-held normal punches are not area gestures")
	reset();hands.left.grip=0.;sweep("right");check(seen.is_empty(),"Open hand prevents area gesture")
	reset();hands.left.tracked=false;sweep("right");check(seen.is_empty(),"Both controllers must be tracked")
	reset();hands.left.free=false;sweep("right");check(seen.is_empty(),"Occupied offhand prevents gesture")
	reset();sweep("right",[]);check(seen.is_empty(),"Unlearned or unavailable ability cannot activate")
	reset();tick();hands.left.position.x=-.8;tick();check(seen.is_empty() and detector.start.is_empty(),"Tracking jump clears recognition")
	reset();tick();hands.left.position.x-=.1;tick(.2);check(detector.start.is_empty(),"Frame gap clears partial gesture")
	reset();tick();tick(.02,false);check(detector.previous.is_empty(),"Focus or UI capture clears gesture")
	reset();hands.left.position=Vector3(-.05,-.3,-.3);hands.right.position=Vector3(.05,-.3,-.3)
	tick();hands.right.trigger=1.;tick();hands.left.trigger=1.;tick()
	check(seen==["indomitable_focus"],"Fists together with staggered trigger chord activates ultimate")
	for i in range(40):tick()
	check(seen.size()==1 and detector.capturing,"Held ultimate chord is captured and cannot repeat")
	hands.left.trigger=0.;hands.right.trigger=0.;tick();hands.left.trigger=1.;hands.right.trigger=1.;tick()
	check(seen.size()==2,"Releasing both triggers rearms ultimate")
	reset();hands.left.position.x=-.05;hands.right.position.x=.05;hands.left.trigger=1.;hands.right.trigger=1.;tick()
	check(seen.is_empty(),"Arriving with both triggers held cannot activate")
	reset();hands.left.position.x=-.05;hands.right.position.x=.05;tick(.02,true,IDS,false);hands.left.trigger=1.;hands.right.trigger=1.;tick(.02,true,IDS,false)
	check(seen.is_empty(),"Unequipped ultimate cannot activate")
	reset();hands.left.position.x=-.05;hands.right.position.x=.05;tick(.02,true,[],true);hands.left.trigger=1.;hands.right.trigger=1.;tick(.02,true,[],true)
	check(seen.is_empty(),"Cooldown or failed conditions suppress ultimate")
	var report:Dictionary={"checks":checks,"errors":errors,"tracking":"mocked","headset_tested":false}
	FileAccess.open("res://../runtime/evidence/tka-gestures.json",FileAccess.WRITE).store_string(JSON.stringify(report));print(JSON.stringify(report));quit(0 if errors.is_empty() else 1)
