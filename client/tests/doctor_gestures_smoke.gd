extends SceneTree
const Gesture=preload("res://medic/doctor_gestures.gd")
var checks:=0
var errors:Array=[]
var motion:RefCounted
var hz:=90.
var held:=Vector3(-.12,0,.6)
var other:=Vector3(.12,0,.6)
var count:=0
var sign_value:=1.
var permitted:=true
var identity:="supply:patient"
var ability:="reviveplayer"
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:errors.append(label);push_error(label)
func frame(a:Vector3,b:Vector3,grip:float)->void:
	held=a;other=b
	if motion.sample(1/hz,identity,ability,Vector3(a.x*sign_value,a.y,a.z),Vector3(b.x*sign_value,b.y,b.z),grip,permitted):count+=1
func move(a:Vector3,b:Vector3,grip:float,duration:=.35)->void:
	var from:=held;var off:=other
	for i in range(1,int(hz*duration)+1):frame(from.lerp(a,i/float(int(hz*duration))),off.lerp(b,i/float(int(hz*duration))),grip)
func stay(seconds:float,grip:float)->void:
	for i in range(int(hz*seconds)):frame(held,other,grip)
func reset(action:String)->void:
	motion=Gesture.new();ability=action;held=Vector3(-.12,0,.6);other=Vector3(.12,0,.6);count=0;permitted=true;identity="supply:patient";frame(held,other,0)
func revive()->void:
	move(Vector3(-.12,0,.08),Vector3(.12,0,.08),0);stay(.8,1);frame(held,other,0)
func blanket()->void:
	move(Vector3(-.17,0,.10),Vector3(.14,0,.10),0);stay(.2,0);move(Vector3(.17,0,.10),other,0);move(Vector3(-.17,0,.10),other,0);stay(.4,0)
func _initialize()->void:call_deferred("run")
func run()->void:
	for frequency in [45.,72.,90.,120.]:
		hz=frequency
		for mirror in [-1.,1.]:
			sign_value=mirror
			for action in ["reviveplayer","extinguishfire"]:
				reset(action)
				if action=="reviveplayer":revive()
				else:blanket()
				stay(1,0)
				check(count==1,"One %s gesture at %sHz mirrored%s"%[action,hz,mirror])
				if action=="reviveplayer":stay(.8,1);frame(held,other,0)
				else:move(Vector3(.17,0,.10),other,0);move(Vector3(-.17,0,.10),other,0);stay(.4,0)
				check(count==1,"Contact cannot retrigger %s"%action)
	hz=90;sign_value=1
	for mode in ["no_clear","one_hand","short_press","tracking_loss","target_change","item_change","jump","long_gap","stationary","blocked"]:
		reset("reviveplayer")
		if mode=="no_clear":motion.reset();held=Vector3(-.12,0,.08);other=Vector3(.12,0,.08)
		move(Vector3(-.12,0,.08),Vector3(.12,0,.6) if mode=="one_hand" else Vector3(.12,0,.08),0)
		if mode=="blocked":permitted=false
		stay(.25,1)
		if mode=="tracking_loss":permitted=false;frame(held,other,1);permitted=true
		if mode=="target_change":identity="supply:other"
		if mode=="item_change":identity="replacement:patient"
		if mode=="jump":frame(Vector3(1,0,0),other,1);frame(Vector3(-.12,0,.08),other,1)
		if mode=="long_gap":motion.sample(.5,identity,ability,held,other,1,true)
		if mode not in ["short_press","stationary"]:stay(.55,1)
		frame(held,other,0)
		check(count==0,"Reject revival "+mode)
	for mode in ["stationary","jitter","single_pass","no_clear","tracking_loss","small_rub","circle"]:
		reset("extinguishfire")
		if mode=="no_clear":motion.reset();held=Vector3(-.17,0,.10)
		move(Vector3(-.17,0,.10),Vector3(.14,0,.10),0)
		if mode in ["single_pass","tracking_loss","no_clear"]:
			move(Vector3(.17,0,.10),other,0)
			if mode=="tracking_loss":permitted=false;frame(held,other,0);permitted=true
			if mode!="single_pass":move(Vector3(-.17,0,.10),other,0)
		else:
			for i in range(180):
				var angle:=i/hz*TAU
				frame(Vector3(-.17+(sin(angle)*(.04 if mode=="small_rub" else .005)),0,.10),other,0)
		stay(.5,0);check(count==0,"Reject blanket "+mode)
	var report:Dictionary={"passed":errors.is_empty(),"checks":checks,"errors":errors,"renderer":"dummy","mocked_tracking":true,"headset_tested":false}
	print(JSON.stringify(report));FileAccess.open("res://../runtime/evidence/doctor-gestures.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "));quit(0 if errors.is_empty() else 1)
