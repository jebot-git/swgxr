extends SceneTree
const Detector=preload("res://combat/swordsman_gestures.gd")
var checks:=0
var errors:Array=[]
var detector=Detector.new()
var available:Array=["overhead_cleave","ground_slam","armour_break"]
var outputs:Array=[]
func check(value:bool,label:String)->void:
	checks+=1
	if not value:errors.append(label);push_error(label)
func sample(p:Vector3,t:=0.0,s:=0.0,permitted:=true,selected:=false,dt:=.02,head:=Vector3(0,1.7,0))->void:
	var id:String=detector.sample(dt,p,head,t,s,permitted,available,selected)
	if not id.is_empty():outputs.append(id)
func ready()->void:
	for i in range(12):sample(Vector3(.15,-.3,-.3))
func overhead()->void:
	for i in range(10):sample(Vector3(.15,-.3+i*.075,-.3))
	for i in range(14):sample(Vector3(.15,.375-i*.065,-.3))
func slam()->void:
	for i in range(12):sample(Vector3(.15,-.3-i*.055,-.3))
func _initialize()->void:
	ready();overhead();check(outputs==["overhead_cleave"],"Ready raise and committed descent trigger one cleave")
	for i in range(30):sample(Vector3(.15,-.5,-.3))
	check(outputs.size()==1,"Held finishing pose cannot repeat")
	ready();slam();check(outputs==["overhead_cleave","ground_slam"],"Neutral guard rearms lower-start ground slam")
	for mode:String in ["tracking","jump","gap","crouch","trigger","unlearned"]:
		detector.clear();outputs.clear();ready()
		if mode=="tracking":sample(Vector3(.15,-.3,-.3),0,0,false)
		if mode=="jump":sample(Vector3(.15,-1.1,-.3))
		if mode=="gap":sample(Vector3(.15,-.3,-.3),0,0,true,false,.2)
		if mode=="crouch":sample(Vector3(.15,-.3,-.3),0,0,true,false,.02,Vector3(0,1.2,0))
		if mode=="trigger":sample(Vector3(.15,-.3,-.3),1)
		if mode=="unlearned":available=[]
		slam();check(outputs.is_empty(),"Reject incomplete gesture after "+mode);available=["overhead_cleave","ground_slam","armour_break"]
	detector.clear();outputs.clear()
	for i in range(30):sample(Vector3(.15,.4,-.3))
	check(outputs.is_empty(),"Starting held overhead is not an attack")
	detector.clear();ready();outputs.clear()
	for i in range(10):sample(Vector3(.15,-.3+i*.075,-.3))
	for i in range(4):sample(Vector3(.15,.375-i*.05,-.3))
	for i in range(5):sample(Vector3(.15,.225+i*.05,-.3))
	check(outputs.is_empty(),"Warcry-size pump is not an overhead strike")
	detector.clear();outputs.clear();sample(Vector3(.15,-.3,-.3),0,0,true,true);sample(Vector3(.15,-.3,-.3),1,1,true,true)
	check(outputs==["armour_break"] and detector.capturing,"Released two-trigger chord captures the ultimate")
	for i in range(30):sample(Vector3(.15,-.3,-.3),1,1,true,true)
	check(outputs.size()==1,"Holding both triggers does not repeat")
	for mode:String in ["not_selected","not_available","already_held"]:
		detector.clear();outputs.clear()
		if mode=="not_available":available=[]
		if mode!="already_held":sample(Vector3(.15,-.3,-.3),0,0,true,mode!="not_selected")
		sample(Vector3(.15,-.3,-.3),1,1,true,mode!="not_selected")
		check(outputs.is_empty(),"Ultimate rejects "+mode);available=["overhead_cleave","ground_slam","armour_break"]
	for off_first:bool in [false,true]:
		detector.clear();outputs.clear();sample(Vector3(.15,-.3,-.3),0,0,true,true)
		for i in range(15):sample(Vector3(.15,-.3,-.3),0 if off_first else 1,1 if off_first else 0,true,true)
		if not off_first:check(not detector.capturing,"Ordinary main-trigger attacks resume after chord window")
		sample(Vector3(.15,-.3,-.3),1,1,true,true)
		check(outputs.is_empty(),"Widely separated trigger edges cannot invoke ultimate, offhand first: "+str(off_first))
	var report:Dictionary={"checks":checks,"errors":errors,"tracking":"mocked","headset_tested":false}
	var f:=FileAccess.open("res://../runtime/evidence/swordsman-gestures.json",FileAccess.WRITE);f.store_string(JSON.stringify(report,"  "));print(JSON.stringify(report));quit(0 if errors.is_empty() else 1)
