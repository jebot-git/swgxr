extends SceneTree
const Gesture=preload("res://combat/overhead_warcry.gd")
var failures:Array=[]
var checks:=0
func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures.append(label);push_error(label)
func hand(y:float,changes:Dictionary={})->Dictionary:
	var h:Dictionary={"position":Vector3(.2,1.7+y,-.2),"relative":Vector3(.2,y,-.2),"head_y":1.7,"item_id":"42","tracked":true,"grip":1.,"trigger":0.,"support_trigger":0.}
	h.merge(changes,true);return h
func pump(g:RefCounted,changes:Dictionary={})->int:
	var count:=0
	for y:float in [0.,.1,.2,.3,.4,.5,.4,.3,.2,.3,.4,.5]:
		if g.sample(.05,hand(y,changes),true):count+=1
	return count
func _initialize()->void:
	var g=Gesture.new()
	check(pump(g)==1,"Raise plus overhead pump fires once")
	for i in range(40):check(not g.sample(.05,hand(.5),true),"Held overhead cannot repeat")
	for y:float in [.4,.3,.2,.1,0.]:g.sample(.05,hand(y),true)
	check(pump(g)==1,"Lowering below head rearms next complete gesture")
	for changes:Dictionary in [{"tracked":false},{"grip":0.},{"trigger":1.},{"support_trigger":1.},{"item_id":""},{"position":Vector3.INF}]:
		check(pump(Gesture.new(),changes)==0,"Invalid input rejected: "+str(changes))
	g=Gesture.new()
	for y:float in [0.,.1,.2,.3,.4,.5]:check(not g.sample(.05,hand(y),true),"Raise alone never fires")
	g=Gesture.new()
	for y:float in [.5,.4,.3,.2,.3,.4,.5]:check(not g.sample(.05,hand(y),true),"Starting above head requires lowering to arm")
	for cancel:String in ["focus","gap","tracking","weapon","head","teleport"]:
		g=Gesture.new()
		for y:float in [0.,.1,.2,.3,.4,.5,.4,.3,.2]:g.sample(.05,hand(y),true)
		var h:=hand(.2)
		if cancel=="tracking":h.tracked=false
		if cancel=="weapon":h.item_id="99"
		if cancel=="head":h.head_y=1.4
		if cancel=="teleport":h.position=Vector3(10,10,10)
		g.sample(.2 if cancel=="gap" else .05,h,cancel!="focus")
		for y:float in [.3,.4,.5]:check(not g.sample(.05,hand(y),true),"Partial gesture reset: "+cancel)
	g=Gesture.new()
	for y:float in [0.,.1,.2,.3,.4,.5,.4,.3,.2,.3,.4,.5]:
		check(not g.sample(.05,hand(y,{"position":Vector3(.2,1.9,-.2),"head_y":1.9-y}),true),"Head bob without hand travel never fires")
	var report:Dictionary={"test":"warcry_gesture","checks":checks,"failures":failures,"mocked_tracking":true,"headset_tested":false}
	FileAccess.open("res://../runtime/evidence/warcry-client.json",FileAccess.WRITE).store_string(JSON.stringify(report))
	print(JSON.stringify(report));quit(0 if failures.is_empty() else 1)
