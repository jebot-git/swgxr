extends SceneTree
const Gesture=preload("res://medic/bandage_gesture.gd")
var checks:=0
var errors:Array[String]=[]
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:errors.append(label);push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	for hz:float in [45.0,72.0,90.0,120.0]:
		for sign_value:float in [-1.0,1.0]:
			var gesture=Gesture.new();var count:=0
			for frame in range(int(hz*3)):
				var t:float=frame/hz;var offset:=Vector3(t,1.2,0)
				var angle:float=sign_value*minf(t,1.5)*TAU
				if gesture.sample(1/hz,"self:left",offset+Vector3(cos(angle)*.14,sin(angle)*.14,.15),offset,offset+Vector3(0,0,.30),true):count+=1
			check(count==1,"One wrapping request either direction at %d Hz"%hz)
	for mode in ["rub","jitter","stationary","far","untracked"]:
		var gesture=Gesture.new();var count:=0
		for frame in range(270):
			var t:float=frame/90.0;var angle:=sin(t*TAU)*.15 if mode=="jitter" else 0.0 if mode=="stationary" else t*TAU
			var hand:=Vector3(cos(angle)*(.5 if mode=="far" else .14),sin(angle)*.14,.15)
			if mode=="rub":hand=Vector3(.1,0,.15+.09*sin(t*TAU*2))
			if gesture.sample(1.0/90,"target:left",hand,Vector3.ZERO,Vector3(0,0,.3),mode!="untracked"):count+=1
		check(count==0,"Reject "+mode)
	var script=load("res://medic/controller.gd")
	check(script!=null,"Medical controller and bandaging orchestration load")
	var report:Dictionary={"passed":errors.is_empty(),"checks":checks,"errors":errors,"mocked_tracking":true,"headset_tested":false}
	print(JSON.stringify(report));FileAccess.open("res://../runtime/evidence/bandage-gesture.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	quit(0 if errors.is_empty() else 1)
