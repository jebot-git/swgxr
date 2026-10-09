extends SceneTree
const Detector=preload("res://combat/fencer_gestures.gd")
var detector=Detector.new()
var checks:=0
var errors:Array=[]
var outputs:Array=[]
var available:Array=["probing_jabs","raking_slash","guard_bash","flawless_assault"]
var neutral:=Vector3(.15,-.3,-.3)
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:errors.append(label);push_error(label)
func sample(p:Vector3,axis:=Vector3.FORWARD,t:=0.,s:=0.,permitted:=true,supported:=false,selected:=false,dt:=.02,head:=Vector3(0,1.7,0))->void:
	var id:String=detector.sample(dt,p,head,axis,t,s,permitted,supported,selected,available)
	if not id.is_empty():outputs.append(id)
func reset()->void:detector.clear();outputs.clear()
func ready(axis:=Vector3.FORWARD)->void:
	for i in range(24):sample(neutral,axis)
func jab()->void:
	for i in range(6):sample(neutral+Vector3(0,0,-.05*i))
	for i in range(6):sample(neutral+Vector3(0,0,-.25+.05*i))
func slash(side:=1.)->void:
	for i in range(6):sample(neutral.lerp(Vector3(.4*side,.1,-.3),i/5.))
	for i in range(10):sample(Vector3(.4*side-.08*side*i,.1-.07*i,-.3))
func bash()->void:
	for i in range(6):sample(neutral+Vector3(0,0,-.04*i),Vector3.RIGHT)
func _initialize()->void:
	ready();jab();check(outputs.is_empty(),"A single jab is ordinary motion")
	jab();check(outputs==["probing_jabs"],"Two forward jabs with retraction trigger once")
	for i in range(10):sample(neutral+Vector3(0,0,-.25))
	check(outputs.size()==1,"Held extension cannot repeat")
	ready();jab();jab();check(outputs.size()==2,"Neutral rest rearms the next sequence")
	reset();ready()
	for i in range(20):sample(neutral+Vector3(0,0,-.25))
	check(outputs.is_empty(),"One long extension never counts as two jabs")
	for side:float in [-1.,1.]:
		reset();ready();slash(side);check(outputs==["raking_slash"],"Diagonal slash in either direction: "+str(side))
	reset();ready(Vector3.RIGHT);bash();check(outputs==["guard_bash"],"Established guard plus short hilt thrust triggers bash")
	reset();ready(Vector3.RIGHT);slash();check(outputs==["raking_slash"],"Diagonal movement exits guard into slash")
	reset();ready(Vector3.RIGHT);jab();jab();check(outputs==["probing_jabs"],"Turning blade forward exits guard into jabs")
	reset();ready()
	for i in range(12):sample(Vector3(.15,-.3+i*.07,-.3))
	for i in range(6):sample(Vector3(.15,.47-i*.04,-.3))
	check(outputs.is_empty(),"Warcry raise and pump is not a Fencer strike")
	for mode:String in ["tracking","jump","gap","head_motion","trigger","unavailable"]:
		reset();ready();jab()
		if mode=="tracking":sample(neutral,Vector3.FORWARD,0,0,false)
		if mode=="jump":sample(neutral+Vector3(1,0,0))
		if mode=="gap":sample(neutral,Vector3.FORWARD,0,0,true,false,false,.2)
		if mode=="head_motion":sample(neutral,Vector3.FORWARD,0,0,true,false,false,.02,Vector3(0,1.2,0))
		if mode=="trigger":sample(neutral,Vector3.FORWARD,1)
		if mode=="unavailable":available=[]
		jab();check(outputs.is_empty(),"Incomplete sequence rejected after "+mode)
		available=["probing_jabs","raking_slash","guard_bash","flawless_assault"]
	for off_first:bool in [false,true]:
		reset();sample(neutral,Vector3.FORWARD,0,0,true,true,true)
		sample(neutral,Vector3.FORWARD,0 if off_first else 1,1 if off_first else 0,true,true,true)
		sample(neutral,Vector3.FORWARD,1,1,true,true,true)
		check(outputs==["flawless_assault"] and detector.capturing,"Small trigger stagger works in either order")
		for i in range(30):sample(neutral,Vector3.FORWARD,1,1,true,true,true)
		check(outputs.size()==1,"Held ultimate chord cannot repeat")
		reset();sample(neutral,Vector3.FORWARD,0,0,true,true,true)
		for i in range(15):sample(neutral,Vector3.FORWARD,0 if off_first else 1,1 if off_first else 0,true,true,true)
		if not off_first:check(not detector.capturing,"Lone main trigger returns to ordinary attacks")
		sample(neutral,Vector3.FORWARD,1,1,true,true,true)
		check(outputs.is_empty(),"Widely separated trigger edges cannot activate")
	for mode:String in ["unsupported","unselected","unavailable","already_held"]:
		reset()
		if mode=="unavailable":available=[]
		if mode!="already_held":sample(neutral,Vector3.FORWARD,0,0,true,mode!="unsupported",mode!="unselected")
		sample(neutral,Vector3.FORWARD,1,1,true,mode!="unsupported",mode!="unselected")
		check(outputs.is_empty(),"Ultimate rejects "+mode)
		available=["probing_jabs","raking_slash","guard_bash","flawless_assault"]
	var report:Dictionary={"checks":checks,"errors":errors,"tracking":"mocked","headset_tested":false}
	var file:=FileAccess.open("res://../runtime/evidence/fencer-gestures.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));print(JSON.stringify(report));quit(0 if errors.is_empty() else 1)
