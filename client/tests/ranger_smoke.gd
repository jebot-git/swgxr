extends SceneTree
const InputRules=preload("res://scout/ranger_input.gd")
const Ranger=preload("res://scout/ranger.gd")
var checks:=0
var failures:Array=[]
func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures.append(label);push_error(label)
func pose(yaw:float)->Transform3D:return Transform3D(Basis(Vector3.UP,yaw),Vector3(0,1.7,0))
func sample(g:RefCounted,seconds:float,kind:String="rescue",target:String="42",tracked:=true,allowed:=true,sweep:=false)->Array:
	var actions:Array=[]
	for i in range(roundi(seconds*90)):
		var h:=pose(.62*sin(float(i)/90*2.2) if sweep else 0)
		var result:Dictionary=g.sample(1.0/90,kind,target,h,h*Vector3(-.2,.1,-.15) if kind=="area_track" else Vector3(-.2,1.2,-.4),Vector3(.2,1.2,-.4),kind=="rescue",tracked,allowed)
		if not str(result.action).is_empty():actions.append(result.action)
	return actions
func _initialize()->void:call_deferred("run")
func run()->void:
	var g:=SwgRangerGesture.new()
	check(sample(g,.9).is_empty() and sample(g,.1)==["rescue"],"Rescue requires deliberate one-second continuous pointing")
	check(sample(g,2).is_empty(),"Held pointing cannot repeat Rescue")
	g.sample(.01,"rescue","42",pose(0),Vector3(-.2,.9,0),Vector3(.2,.9,0),false,true,true)
	check(sample(g,1)==["rescue"],"Lowered/relaxed hands rearm the next deliberate Rescue")
	g.reset();sample(g,.8);sample(g,.1,"rescue","42",false)
	check(sample(g,.8).is_empty(),"Lost tracking clears partial Rescue")
	g.reset();sample(g,.8);check(sample(g,.5,"rescue","43").is_empty(),"Changing one or both finger targets clears Rescue progress")
	g.reset();sample(g,.8);sample(g,.1,"rescue","42",true,false)
	check(sample(g,.5).is_empty(),"UI/life/hand-ownership gates interrupt Rescue")
	g.reset();check(sample(g,4,"area_track","",true,true,false).is_empty(),"Static hand above eyes never starts Area Track")
	g.reset();check(sample(g,1.9,"area_track","",true,true,true).is_empty(),"Scouting cannot complete before two seconds")
	g.reset();check(sample(g,3,"area_track","",true,true,true)==["area_track"],"Brow pose with deliberate left-right head sweep requests native search")
	check(sample(g,4,"area_track","",true,true,true).is_empty(),"Maintained scouting pose does not automatically repeat search")
	g.reset();var count:=0
	for i in range(270):
		var h:=pose(float(i)/270*1.4);var r:Dictionary=g.sample(1.0/90,"area_track","",h,h*Vector3(-.2,.1,-.15),Vector3(.2,1.2,-.4),false,true,true)
		if not str(r.action).is_empty():count+=1
	check(count==0,"One-way head rotation is not the required left-right sweep")
	check(InputRules.is_kit({"template":"object/tangible/scout/camokit/shared_camokit_yavin.iff"}) and not InputRules.is_kit({"template":"object/tangible/food/foraged/berries.iff"}),"Exact original kit templates intercept only camouflage items")
	check(InputRules.pointing({}, {"grip":1.0,"trigger":0.0}) and not InputRules.pointing({}, {"grip":1.0,"trigger":1.0}),"Runtime-neutral controller fallback distinguishes index point from fist")
	var joints:Dictionary={}
	for finger in ["index","ring"]:
		joints[finger+"_proximal"]=Vector3.ZERO;joints[finger+"_intermediate"]=Vector3(0,0,-.03);joints[finger+"_distal"]=Vector3(0,-.025,-.035) if finger=="ring" else Vector3(0,0,-.055);joints[finger+"_tip"]=Vector3(0,-.025,-.015) if finger=="ring" else Vector3(0,0,-.075)
	check(InputRules.pointing(joints,{"grip":0,"trigger":1}),"Optical extended index and curled remaining fingers override controller buttons")
	joints.index_distal=joints.ring_distal;joints.index_tip=joints.ring_tip
	check(not InputRules.pointing(joints,{"grip":1,"trigger":0}),"An optically curled index cannot be mistaken for pointing")
	var rows:Array=[{"id":"42","pose":Transform3D(Basis.IDENTITY,Vector3(0,0,-3)),"bounds":AABB(Vector3(-.5,0,-.5),Vector3(1,2,1)),"eligible":true}]
	var ray:Dictionary={"tip":Vector3(0,1,0),"direction":Vector3.FORWARD}
	check(InputRules.target(ray,rows,Vector3.ZERO,32)=="42" and InputRules.target(ray,rows,Vector3.ZERO,32,1).is_empty(),"Finger ray intersects original local bounds and respects LOS obstruction")
	var panel:=preload("res://scout/ranger_panel.gd").new();root.add_child(panel)
	panel.apply({"track_types":["animal"],"tracking":{"state":"ready","results":[{"name":"Bantha"}]}})
	var calls:Array=[];panel.action_requested.connect(func(action,detail):calls.append({"action":action,"detail":detail}))
	panel.click_at(panel.type_rect(1).get_center());check(calls.is_empty(),"Unlearned NPC/player track buttons cannot submit")
	panel.click_at(panel.type_rect(0).get_center());check(calls.size()==1 and calls[0].detail.track_type=="animal","Available source filter requests native tracking")
	panel.apply({"track_types":["animal"],"tracking":{"state":"pending","results":[]}});panel.click_at(panel.type_rect(0).get_center());check(calls.size()==1,"Pending original search cannot rescan prematurely")
	check(panel.notice().contains("stay still") and panel.notice().contains("six seconds"),"Pending source search explains stillness and original duration")
	panel.apply({"track_types":["animal"],"tracking":{"state":"failed","reason":"native_tracking_interrupted","results":[]}})
	check(panel.notice().contains("interrupted") and not panel.notice().contains("No tracks"),"Interrupted tracking is visibly a failure rather than an empty successful search")
	var capped:Array=[];capped.resize(256);capped.fill({"name":"Source result"});panel.apply({"tracking":{"state":"succeeded","results":capped}})
	check(panel.notice().begins_with("Showing up to 256"),"Bounded native track list never implies complete planet coverage")
	panel.apply({"tracking":{"state":"succeeded","results":capped,"truncated":true,"total_results":310}})
	check(panel.notice().begins_with("Showing 256 of 310"),"Native qualified-result total and truncation are shown precisely")
	panel.apply({"tracking":{"state":"succeeded","results":capped.slice(0,12)}})
	check(panel.row_at(Vector2(800,230))==0,"Right side of full-width tracking rows is interactive")
	panel.pointer_begin(Vector2(800,420));panel.pointer_move(Vector2(800,300));panel.pointer_end(Vector2(800,300))
	check(panel.offset==2,"Finger drag across right side scrolls tracking results")
	panel.scroll_rows(100);check(panel.offset==7,"Tracking scroll clamps to last five visible results")
	panel.click_at(panel.TRACK_PREVIOUS.get_center());check(panel.offset==2,"Visible Previous control pages tracking results")
	panel.click_at(panel.TRACK_NEXT.get_center());check(panel.offset==7,"Visible Next control pages tracking results")
	panel.apply({"tracking":{"state":"pending","request_id":"new","duration_seconds":6,"results":[]}});panel._process(7)
	check(panel.pending and panel.tracking.state=="pending","Progress animation cannot invent a completed native search")
	var closed:Array=[];panel.close_requested.connect(func():closed.append(true));panel.click_at(panel.CLOSE_RECT.get_center())
	check(closed.size()==1,"Tracking close remains available while native search is pending")
	var controller:=Ranger.new();controller.observe({"ok":true,"mutation":{"action":"rescue","success":true,"rescued":false}})
	check(controller.message.contains("failed") and not controller.message.contains("succeeded"),"A native accepted but failed Rescue roll is not described as a success")
	controller.free()
	panel.free()
	var report:Dictionary={"passed":failures.is_empty(),"checks":checks,"failures":failures,"native_gestures":true,"tracking":"mocked","renderer":"dummy","live_xr":false};FileAccess.open("res://../runtime/evidence/ranger-client.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "));print(JSON.stringify(report));quit(0 if failures.is_empty() else 1)
