extends SceneTree
const Gesture=preload("res://combat/carbineer_gestures.gd")
var gesture=Gesture.new()
var checks:=0
var errors:Array=[]
var results:Array=[]
var permitted:=true
var main_trigger:=0.
var support_trigger:=0.
var available:Array=["full_auto_sweep","tactical_brace"]
var previous_yaw:=0.
var previous_roll:=0.
func check(value:bool,label:String)->void:
	checks+=1
	if not value:errors.append(label);push_error(label)
func sample(yaw:float,roll:=0.,mirror:=1.,head_yaw:=0.,translation:=Vector3.ZERO,physical:=true)->void:
	var rotation:=Basis(Vector3.UP,deg_to_rad(yaw*mirror))*Basis(Vector3.FORWARD,deg_to_rad(roll*mirror))
	var main:=Transform3D(rotation,Vector3(.12*mirror,-.4,-.25))
	var support:=Transform3D(rotation,main.origin+rotation*Vector3(0,0,-.28))
	var evidence:=main if physical else Transform3D(Basis.IDENTITY,main.origin)
	var off:=support.origin if physical else main.origin+Vector3(0,0,-.28)
	var frame:=Transform3D(Basis(Vector3.UP,deg_to_rad(head_yaw)),translation)
	var result:String=gesture.sample(.02,frame.affine_inverse()*(Transform3D(main.basis,main.origin+translation)),frame.affine_inverse()*(Transform3D(support.basis,support.origin+translation)),evidence,off,main_trigger,support_trigger,permitted,available)
	if not result.is_empty():results.append(result)
	previous_yaw=yaw;previous_roll=roll
func move(yaw:float,roll:=0.,mirror:=1.,physical:=true)->void:
	var a:=previous_yaw;var b:=previous_roll
	for i in range(1,11):sample(lerpf(a,yaw,i/10.),lerpf(b,roll,i/10.),mirror,0,Vector3.ZERO,physical)
func reset()->void:
	gesture.clear();results.clear();permitted=true;main_trigger=0;support_trigger=0;available=["full_auto_sweep","tactical_brace"];previous_yaw=0;previous_roll=0
func neutral(mirror:=1.)->void:
	for i in range(15):sample(0,0,mirror)
func sweep(mirror:=1.,physical:=true)->void:
	move(16,0,mirror,physical);move(-16,0,mirror,physical);move(0,0,mirror,physical)
	for i in range(8):sample(0,0,mirror,0,Vector3.ZERO,physical)
func brace(mirror:=1.)->void:
	move(0,65,mirror)
	for i in range(42):sample(0,65,mirror)
	move(0,0,mirror)
func _initialize()->void:call_deferred("run")
func run()->void:
	for mirror:float in [1.,-1.]:
		reset();neutral(mirror);sweep(mirror);check(results==["full_auto_sweep"],"Mirrored supported sweep returns forward before activation")
		reset();neutral(mirror);brace(mirror);check(results==["tactical_brace"],"Mirrored cant-hold-return activates brace")
	reset();neutral();move(16);move(-16);check(results.is_empty(),"Sweep cannot fire before return and settle")
	reset();neutral();move(0,65)
	for i in range(60):sample(0,65)
	check(results.is_empty(),"Holding canted brace does not activate before level return")
	move(0);check(results==["tactical_brace"],"Brace activates once on return")
	for i in range(100):sample(0)
	check(results.size()==1,"Held neutral cannot repeat either gesture")
	reset();neutral();move(0,65)
	for i in range(25):sample(0,65)
	move(0);check(results.is_empty(),"Short brace is rejected")
	for mode:String in ["main_trigger","support_trigger","tracking","unlearned","stationary_hands"]:
		reset();neutral()
		if mode=="main_trigger":main_trigger=1
		if mode=="support_trigger":support_trigger=1
		if mode=="tracking":permitted=false
		if mode=="unlearned":available=[]
		sweep(1,mode!="stationary_hands");check(results.is_empty(),"Recognition gate: "+mode)
	reset();neutral()
	for i in range(150):sample(sin(i*.2)*3)
	check(results.is_empty(),"Small aiming jitter cannot provide sweep travel")
	reset();neutral()
	for i in range(80):sample(0,0,1,sin(i*.08)*20)
	check(results.is_empty(),"Looking side to side with stationary weapon cannot provide sweep")
	reset();neutral()
	for i in range(100):sample(0,0,1,0,Vector3(i*.01,0,0))
	check(results.is_empty(),"Common player translation cannot provide sweep")
	reset();neutral()
	for i in range(120):
		var yaw:=sin(i*.06)*16
		sample(yaw,0,1,yaw)
	check(results.is_empty(),"Turning head and held weapon together cannot provide a relative sweep")
	reset();neutral();move(16);permitted=false;sample(16);permitted=true;move(-16);move(0)
	check(results.is_empty(),"Tracking loss discards unfinished sweep")
	reset();sweep();check(results.is_empty(),"Gesture requires deliberate neutral arming")
	reset();neutral();move(16);for i in range(120):sample(16)
	move(-16);move(0);check(results.is_empty(),"Slow abandoned sweep expires")
	reset();neutral();sweep();neutral();sweep();check(results==["full_auto_sweep","full_auto_sweep"],"Neutral rearm permits another deliberate sweep")
	var report:={"checks":checks,"errors":errors,"tracking":"synthetic","renderer":"dummy","live_xr":false}
	FileAccess.open("res://../runtime/evidence/carbineer-gestures.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "));print(JSON.stringify(report));quit(0 if errors.is_empty() else 1)
