extends SceneTree
const Detector=preload("res://combat/pikeman_gestures.gd")
var detector=Detector.new()
var checks:=0
var errors:Array=[]
var outputs:Array=[]
var available:Array=["driving_jabs","overhead_whirl","sweeping_trip","whirlwind"]
var neutral:=Vector3(.15,-.3,-.3)
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:errors.append(label);push_error(label)
func sample(p:Vector3,t:=0.,s:=0.,permitted:=true,selected:=false,dt:=.02,head:=Vector3(0,1.7,0))->void:
	var id:String=detector.sample(dt,p,head,t,s,permitted,selected,available)
	if not id.is_empty():outputs.append(id)
func reset()->void:detector.clear();outputs.clear()
func ready()->void:
	for i in range(24):sample(neutral)
func jab()->void:
	for i in range(6):sample(neutral+Vector3(0,0,-.05*i))
	for i in range(6):sample(neutral+Vector3(0,0,-.25+.05*i))
func circle(side:=1.,limit:=25)->void:
	for i in range(8):sample(neutral.lerp(Vector3(.2,.25,-.35),i/7.))
	for i in range(limit):sample(Vector3(.2*cos(i*TAU/24),.25,-.35+.2*sin(side*i*TAU/24)))
func sweep(side:=1.)->void:
	for i in range(8):sample(neutral.lerp(Vector3(.4*side,-.65,-.3),i/7.))
	for i in range(12):sample(Vector3(.4*side-.065*side*i,-.65,-.3))
func _initialize()->void:
	ready();jab();check(outputs.is_empty(),"One jab does not trigger")
	jab();check(outputs==["driving_jabs"],"Two jabs with retraction trigger once")
	ready();jab();jab();check(outputs.size()==2,"Neutral guard rearms")
	reset();ready()
	for i in range(30):sample(neutral+Vector3(0,0,-.25))
	check(outputs.is_empty(),"Held extension is not a volley")
	for side:float in [-1.,1.]:
		reset();ready();circle(side);check(outputs==["overhead_whirl"],"Overhead circle works in both directions")
		reset();ready();sweep(side);check(outputs==["sweeping_trip"],"Low sweep works in both directions")
	reset();ready();circle(1.,10);check(outputs.is_empty(),"Partial overhead arc does not trigger")
	reset();ready()
	for i in range(13):sample(Vector3(.15,-.3+.065*i,-.3))
	for i in range(6):sample(Vector3(.15,.48-.04*i,-.3))
	check(outputs.is_empty(),"Warcry overhead pump is not a whirl")
	reset();ready()
	for i in range(15):sample(Vector3(.15,-.3-.045*i,-.3))
	check(outputs.is_empty(),"Swordsman downward strike is not a sweep")
	for mode:String in ["tracking","jump","gap","head_motion","trigger","unavailable"]:
		reset();ready();jab()
		if mode=="tracking":sample(neutral,0,0,false)
		if mode=="jump":sample(neutral+Vector3(1,0,0))
		if mode=="gap":sample(neutral,0,0,true,false,.2)
		if mode=="head_motion":sample(neutral,0,0,true,false,.02,Vector3(0,1.2,0))
		if mode=="trigger":sample(neutral,1)
		if mode=="unavailable":available=[]
		jab();check(outputs.is_empty(),"Interrupted gesture rejected: "+mode)
		available=["driving_jabs","overhead_whirl","sweeping_trip","whirlwind"]
	for off_first:bool in [false,true]:
		reset();sample(neutral,0,0,true,true);sample(neutral,0 if off_first else 1,1 if off_first else 0,true,true);sample(neutral,1,1,true,true)
		check(outputs==["whirlwind"] and detector.capturing,"Ultimate chord accepts either trigger order")
		for i in range(30):sample(neutral,1,1,true,true)
		check(outputs.size()==1,"Held chord cannot repeat")
		reset();sample(neutral,0,0,true,true)
		for i in range(15):sample(neutral,0 if off_first else 1,1 if off_first else 0,true,true)
		if not off_first:check(not detector.capturing,"Ordinary main-trigger attacks resume")
		sample(neutral,1,1,true,true);check(outputs.is_empty(),"Late second trigger cannot activate ultimate")
	for mode:String in ["unselected","unavailable","already_held"]:
		reset()
		if mode=="unavailable":available=[]
		if mode!="already_held":sample(neutral,0,0,true,mode!="unselected")
		sample(neutral,1,1,true,mode!="unselected");check(outputs.is_empty(),"Ultimate rejects "+mode)
		available=["driving_jabs","overhead_whirl","sweeping_trip","whirlwind"]
	var report:Dictionary={"checks":checks,"errors":errors,"tracking":"mocked","headset_tested":false}
	var file:=FileAccess.open("res://../runtime/evidence/pikeman-gestures.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));print(JSON.stringify(report));quit(0 if errors.is_empty() else 1)
