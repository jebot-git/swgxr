extends SceneTree
const Gestures=preload("res://combat/bountyhunter_gestures.gd")
var g=Gestures.new()
var checks:=0
var errors:Array=[]
var results:Array=[]
var available:Array=["duelist_stance","underhand_shot"]
var supported:=false
var main_grip:=1.
var support_grip:=0.
var trigger:=0.
var off_trigger:=0.
var permitted:=true
var mirror:=1.
var main:=Transform3D(Basis.IDENTITY,Vector3(.2,-.4,-.4))
var off:=Vector3(0,-.37,-.4)
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:errors.append(label);push_error(label)
func reset()->void:
	g.clear();g.refractory=0;results.clear();supported=false;main_grip=1;support_grip=0;trigger=0;off_trigger=0;permitted=true;available=["duelist_stance","underhand_shot"];main=Transform3D(Basis.IDENTITY,Vector3(.2*mirror,-.4,-.4));off=Vector3(0,-.37,-.4)
func frame(delta:=.02)->void:
	var result:String=g.sample(delta,main,Transform3D(Basis.IDENTITY,off),Vector3(0,1.7,0),trigger,off_trigger,main_grip,support_grip,supported,permitted,available)
	if not result.is_empty():results.append(result)
func move_off(z:float)->void:
	var start:=off.z
	for i in range(1,9):off.z=lerpf(start,z,i/8.);frame()
func taps()->void:
	frame();move_off(-.19);move_off(-.43);move_off(-.19)
func underhand()->void:
	supported=true;support_grip=1;main.origin=Vector3(.2*mirror,-.75,-.35);main.basis=Basis(Vector3.RIGHT,-.4);off=main.origin+Vector3(0,0,-.2)
	for i in range(15):frame()
	for i in range(1,13):main.basis=Basis(Vector3.RIGHT,lerpf(-.4,.5,i/12.));main.origin.y=lerpf(-.75,-.52,i/12.);off=main.origin+Vector3(0,0,-.2);frame()
	for i in range(1,13):main.basis=Basis(Vector3.RIGHT,lerpf(.5,0.,i/12.));frame()
func _initialize()->void:call_deferred("run")
func run()->void:
	for side:float in [1.,-1.]:
		mirror=side;reset();taps();check(results==["duelist_stance"],"Open-palm two taps mirrored "+str(side))
		for i in range(70):frame()
		check(results.size()==1,"Held sternum never retriggers")
		reset();underhand();check(results==["underhand_shot"],"Low carbine arc returns to aim mirrored "+str(side))
	for mode:String in ["clenched","trigger","off_trigger","grip","tracking","unlearned","supported"]:
		reset()
		if mode=="clenched":support_grip=1
		if mode=="trigger":trigger=1
		if mode=="off_trigger":off_trigger=1
		if mode=="grip":main_grip=0
		if mode=="tracking":permitted=false
		if mode=="unlearned":available=[]
		if mode=="supported":supported=true
		taps();check(results.is_empty(),"Duelist gate "+mode)
	reset();frame();move_off(-.19);check(results.is_empty(),"One tap insufficient")
	frame(.2);move_off(-.43);move_off(-.19);check(results.is_empty(),"Tracking gap clears first tap")
	reset();frame()
	for z:float in [-.19,-.43,-.19]:
		var start:=off.z
		for i in range(1,9):
			var next:=lerpf(start,z,i/8.);main.origin.z+=next-off.z;off.z=next;frame()
	check(results.is_empty(),"Shared head/body translation cannot supply chest taps")
	for mode:String in ["trigger","off_trigger","tracking","unlearned"]:
		reset()
		if mode=="trigger":trigger=1
		if mode=="off_trigger":off_trigger=1
		if mode=="tracking":permitted=false
		if mode=="unlearned":available=[]
		underhand();check(results.is_empty(),"Underhand gate "+mode)
	var report:={"checks":checks,"errors":errors,"tracking":"mocked","live_xr":false}
	print(JSON.stringify(report));var f:=FileAccess.open("res://../runtime/evidence/bounty/combat-gestures.json",FileAccess.WRITE);f.store_string(JSON.stringify(report,"  "));quit(0 if errors.is_empty() else 1)
