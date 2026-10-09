extends SceneTree
const Gestures=preload("res://combat/pistoleer_gestures.gd")
var g=Gestures.new()
var checks:=0
var errors:Array=[]
var results:Array=[]
var side:="right"
var available:Array=["fan_shot","run_and_gun"]
var main_trigger:=0.
var off_trigger:=0.
var off_grip:=0.
var permitted:=true
var last_main:=Vector3(.25,-.4,-.35)
var last_off:=Vector3(-.3,-.4,-.35)
var last_basis:=Basis.IDENTITY
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:errors.append(label);push_error(label)
func sample(p:=Vector3(.25,-.4,-.35),off:=Vector3(-.3,-.4,-.35),basis:=Basis.IDENTITY,delta:=.02)->String:
	last_main=p;last_off=off;last_basis=basis
	var mirror:=1. if side=="right" else -1.
	p.x*=mirror;off.x*=mirror
	var result:String=g.sample(delta,Transform3D(basis,p),Transform3D(Basis.IDENTITY,off),side,main_trigger,off_trigger,off_grip,permitted,available)
	if not result.is_empty():results.append(result)
	return result
func move_to(p:Vector3,off:Vector3,basis:=Basis.IDENTITY)->void:
	var a:=last_main;var b:=last_off;var c:=last_basis
	for i in range(1,9):sample(a.lerp(p,i/8.),b.lerp(off,i/8.),c.slerp(basis,i/8.))
func neutral()->void:
	move_to(Vector3(.25,-.4,-.35),Vector3(-.3,-.4,-.35))
	for i in range(12):sample()
func bond()->void:
	move_to(Vector3(.25,-.65,-.25),Vector3(-.6,-.2,0))
	for i in range(45):sample(Vector3(.25,-.65,-.25),Vector3(-.6,-.2,0))
func gangster()->void:
	move_to(Vector3(.25,-.2,-.4),Vector3(-.35,-.5,-.3),Basis(Vector3.FORWARD,PI/2))
	for i in range(45):sample(Vector3(.25,-.2,-.4),Vector3(-.35,-.5,-.3),Basis(Vector3.FORWARD,PI/2))
func fan()->void:
	var p:=Vector3(.25,-.4,-.35)
	move_to(p,p+Vector3(0,.25,.08))
	for y:float in [.25,.21,.17,.13,.09,.13,.17,.21,.25,.21,.17,.13,.09]:sample(p,p+Vector3(0,y,.08))
func reset()->void:
	g.clear();results.clear();main_trigger=0;off_trigger=0;off_grip=0;permitted=true;available=["fan_shot","run_and_gun"]
func _initialize()->void:call_deferred("run")
func run()->void:
	for handedness:String in ["right","left"]:
		side=handedness
		reset();bond();check(results.is_empty(),"Restored Bond pose requires neutral: "+side)
		neutral();bond();check(results==["run_and_gun"],"Bond .8 second hold: "+side)
		bond();gangster();check(results.size()==1,"Held or alternate poses cannot refresh: "+side)
		neutral();gangster();check(results==["run_and_gun","run_and_gun"],"Neutral re-arms alternate pose: "+side)
		reset();neutral();fan();check(results==["fan_shot"],"Two actual cock-fanning strokes: "+side)
		fan();check(results.size()==1,"Fanning requires neutral before another volley: "+side)
		reset();neutral()
		for y:float in [.25,.21,.17,.13,.09]:sample(Vector3(.25,-.4,-.35),Vector3(.25,-.4+y,-.27))
		check(results.is_empty(),"Single stroke is insufficient: "+side)
	side="right"
	for mode:String in ["main_trigger","off_trigger","off_grip","tracking","invalid_delta","unlearned"]:
		reset();neutral()
		if mode=="main_trigger":main_trigger=1
		if mode=="off_trigger":off_trigger=1
		if mode=="off_grip":off_grip=1
		if mode=="tracking":permitted=false
		if mode=="invalid_delta":sample(Vector3(.25,-.4,-.35),Vector3(-.3,-.4,-.35),Basis.IDENTITY,.2)
		if mode=="unlearned":available=[]
		fan();bond();check(results.is_empty(),"Gesture gate: "+mode)
	reset();neutral()
	for dy:float in [0,.04,.08,.12,.16,.12,.08,.04,0,.04,.08,.12,.16]:sample(Vector3(.25,-.4+dy,-.35),Vector3(.25,-.15,-.27))
	check(results.is_empty(),"Moving gun below a stationary offhand never fans")
	reset();neutral()
	for dy:float in [0,.04,.08,.12,.16,.12,.08,.04,0,.04,.08,.12,.16]:sample(Vector3(.25,-.4+dy,-.35),Vector3(.25,-.15+dy,-.27))
	check(results.is_empty(),"Shared hand/head translation never fans")
	reset();neutral();sample(Vector3(.25,-.4,-.35),Vector3(.25,-.15,-.27));sample(Vector3(.25,-.4,-.35),Vector3(.25,-.31,-.27),Basis.IDENTITY,.5);fan()
	check(results.is_empty(),"Tracking gap resets stroke and requires neutral")
	reset();neutral()
	for i in range(25):sample(Vector3(.25,-.65,-.25),Vector3(-.6,-.2,0))
	neutral();check(results.is_empty(),"Short stance never activates")
	reset();neutral()
	for i in range(45):sample(Vector3(.25,-.65,-.25),Vector3(-.6,-.2,0),Basis(Vector3.UP,PI))
	check(results.is_empty(),"Backward muzzle cannot enter firing stance")
	var report:Dictionary={"checks":checks,"errors":errors,"tracking":"synthetic","renderer":"dummy","live_xr":false}
	FileAccess.open("res://../runtime/evidence/pistoleer-gestures.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "));print(JSON.stringify(report));quit(0 if errors.is_empty() else 1)
