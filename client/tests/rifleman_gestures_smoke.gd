extends SceneTree
const Gesture=preload("res://combat/rifleman_gestures.gd")
var gesture=Gesture.new()
var checks:=0
var errors:Array=[]
var results:Array=[]
var hand:=Vector3(0,0,-.30)
var main:=Transform3D(Basis.IDENTITY,Vector3(.12,1.3,-.25))
var head:=Transform3D(Basis.IDENTITY,Vector3(0,1.7,0))
var mirror:=1.
var permitted:=true
var main_grip:=1.
var main_trigger:=0.
var support_trigger:=0.
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:errors.append(label);push_error(label)
func reset()->void:
	gesture.clear();results.clear();hand=Vector3(0,0,-.30);main=Transform3D(Basis.IDENTITY,Vector3(.12*mirror,1.3,-.25));head=Transform3D(Basis.IDENTITY,Vector3(0,1.7,0));permitted=true;main_grip=1.;main_trigger=0.;support_trigger=0.
func frame(local:Vector3,grip:float,supported:bool,delta:=.02)->void:
	hand=local
	var id:String=gesture.sample(delta,main,Transform3D(Basis.IDENTITY,main*Vector3(local.x*mirror,local.y,local.z)),head,"right" if mirror>0 else "left",main_trigger,support_trigger,main_grip,grip,supported,permitted)
	if not id.is_empty():results.append(id)
func move(to:Vector3,grip:float,supported:=false)->void:
	var start:=hand
	for i in range(1,11):frame(start.lerp(to,i/10.),grip,supported)
func neutral()->void:
	for i in range(16):frame(Vector3(0,0,-.30),1.,true)
func approach()->void:
	frame(hand,0.,false);move(Vector3(.09,.06,-.04),0.);frame(hand,1.,false)
func cycle()->void:
	move(Vector3(.09,.06,.10),1.);move(Vector3(.09,.06,-.04),1.);frame(hand,0.,false);move(Vector3(0,0,-.30),0.);frame(hand,1.,true)
func _initialize()->void:
	for stance:String in ["right","left","seated","turned"]:
		mirror=-1. if stance=="left" else 1.;reset()
		if stance=="seated":main.origin.y-=.7;head.origin.y-=.7
		if stance=="turned":var turn:=Basis(Vector3.UP,PI/2);main=Transform3D(turn*main.basis,turn*main.origin);head=Transform3D(turn*head.basis,turn*head.origin)
		neutral();approach();cycle();check(results==["rifleman_focus"],"Gradual complete bolting sequence: "+stance)
		for i in range(60):frame(hand,1.,true)
		check(results.size()==1,"Holding fore-end cannot repeat: "+stance)
	mirror=1.
	for mode:String in ["ordinary_regrip","no_pull","no_return","no_release","no_regrip","magazine","short_pull","trigger","off_trigger","main_grip","unpermitted","tracking_jump","head_turn","body_turn","body_translation","small_body_translation","timeout","frame_gap"]:
		reset();neutral();approach()
		match mode:
			"ordinary_regrip":reset();neutral();frame(hand,0.,false);move(Vector3(0,0,-.2),0.);move(Vector3(0,0,-.3),0.);frame(hand,1.,true)
			"no_pull":frame(hand,0.,false);move(Vector3(0,0,-.3),0.);frame(hand,1.,true)
			"no_return":move(Vector3(.09,.06,.10),1.);frame(hand,0.,false);move(Vector3(0,0,-.3),0.);frame(hand,1.,true)
			"no_release":move(Vector3(.09,.06,.10),1.);move(Vector3(.09,.06,-.04),1.);move(Vector3(0,0,-.3),1.,true)
			"no_regrip":move(Vector3(.09,.06,.10),1.);move(Vector3(.09,.06,-.04),1.);frame(hand,0.,false);move(Vector3(0,0,-.3),0.)
			"magazine":reset();neutral();frame(hand,0.,false);move(Vector3(0,-.23,-.05),0.);frame(hand,1.,false);cycle()
			"short_pull":move(Vector3(.09,.06,.03),1.);move(Vector3(.09,.06,-.04),1.);frame(hand,0.,false);move(Vector3(0,0,-.3),0.);frame(hand,1.,true)
			"trigger":main_trigger=1.;cycle()
			"off_trigger":support_trigger=1.;cycle()
			"main_grip":main_grip=0.;cycle()
			"unpermitted":permitted=false;cycle()
			"tracking_jump":frame(Vector3(.09,.06,.30),1.,false);cycle()
			"head_turn":head.basis=Basis(Vector3.UP,PI/3);cycle()
			"body_turn":main.basis=Basis(Vector3.UP,PI/3);head.basis=main.basis;cycle()
			"body_translation":main.origin.x+=.4;head.origin.x+=.4;cycle()
			"small_body_translation":
				for i in range(10):main.origin.z+=.012;head.origin.z+=.012;frame(hand,1.,false)
				for i in range(10):main.origin.z-=.012;head.origin.z-=.012;frame(hand,1.,false)
				frame(hand,0.,false);move(Vector3(0,0,-.3),0.);frame(hand,1.,true)
			"timeout":for i in range(200):frame(hand,1.,false)
			"frame_gap":frame(hand,1.,false,.2);cycle()
		check(results.is_empty(),"Rejects "+mode)
	reset();neutral();approach();check(gesture.capturing,"Released support stays captured during bolt cycle")
	cycle();check(results.size()==1,"Fresh fore-end regrip completes cycle")
	reset();neutral();approach();move(Vector3(.09,.06,.10),1.);move(Vector3(.09,.06,-.04),1.);frame(hand,0.,false);move(Vector3(0,0,-.30),0.);frame(hand,1.,false)
	check(results.is_empty(),"Fore-end grip waits for actual support latch")
	frame(hand,1.,true);check(results==["rifleman_focus"],"Confirmed support latch permits activation next frame")
	var report:Dictionary={"checks":checks,"errors":errors,"tracking":"synthetic","renderer":"dummy","live_xr":false}
	FileAccess.open("res://../runtime/evidence/rifleman-gestures.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "));print(JSON.stringify(report));quit(0 if errors.is_empty() else 1)
