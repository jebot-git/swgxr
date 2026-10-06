extends SceneTree
const Target=preload("res://pets/creature_targeting.gd")
const PetFixture=preload("res://tests/pet_commands_smoke.gd")
class VisualActor extends Node3D:
	var visual:Node3D
const Handler=preload("res://pets/creature_handler.gd")
var checks:=0
var failures:Array=[]
func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures.append(label);push_error(label)
func pose(x:float,y:float,z:float)->Transform3D:return Transform3D(Basis.IDENTITY,Vector3(x,y,z))
func simulate(g:RefCounted,kind:String,seconds:float,motion:bool=true,id:String="42",allowed:=true,tracked:=true)->Array:
	var actions:Array=[]
	for i in range(roundi(seconds*90)):
		var t:float=i/90.0;var left:=pose(-.25,1.25,-.4);var right:=pose(.25,1.25,-.4);var fists:=0.0
		if kind=="clap":
			var half:float=.18+.13*cos(t*TAU*1.7) if motion else .08;left.origin.x=-half;right.origin.x=half
		elif kind=="beckon":left=pose(-.2,.9,0);right.origin.z=-.45+(.2*sin(t*TAU*1.5) if motion else 0)
		elif kind=="mount":left=pose(-.2,.8,0);right=pose(.3+(.11*sin(t*TAU*2) if motion else 0),1.25,-.4)
		else:
			fists=1
			if kind=="up":left.origin.y=1.95;right.origin.y=1.95
		var sample:Dictionary=g.sample(1.0/90,id,"mount" if kind=="mount" else "tame" if kind in ["clap","beckon"] else "buff",pose(0,1.7,0),left,right,Vector3(.3,1.25,-.4),tracked,allowed,fists,fists)
		if not str(sample.action).is_empty():actions.append(sample.action)
	return actions
func _initialize()->void:call_deferred("run")
func run()->void:
	var g:=SwgCreatureGesture.new()
	check(simulate(g,"clap",12,false).is_empty(),"Static close hands never tame")
	g.reset();check(simulate(g,"clap",9.9).is_empty(),"Clapping cannot finish before ten seconds")
	check(simulate(g,"clap",2)==["ch_tame"],"Continuous rhythmic clapping finishes native request")
	check(simulate(g,"clap",12).is_empty(),"Sustained movement cannot repeat after completion")
	g.sample(.01,"42","tame",pose(0,1.7,0),pose(-.2,.8,0),pose(.2,.8,0),Vector3.ZERO,true,true,0,0)
	check(simulate(g,"beckon",11)==["ch_tame"],"Lowering hands rearms repeated beckoning")
	g.reset();simulate(g,"clap",8);simulate(g,"clap",.1,true,"42",true,false)
	check(simulate(g,"clap",5).is_empty(),"Lost tracking discards partial tame progress")
	g.reset();simulate(g,"clap",8);check(simulate(g,"clap",5,true,"43").is_empty(),"Changing selected creature discards previous progress")
	g.reset();simulate(g,"clap",8);simulate(g,"clap",.1,true,"42",false)
	check(simulate(g,"clap",5).is_empty(),"Blocked UI/mode interrupts the continuous gesture")
	g.reset();check(simulate(g,"mount",8,false).is_empty(),"Static head contact cannot train a mount")
	g.reset();check(simulate(g,"mount",4.9).is_empty() and simulate(g,"mount",1)==["ch_train_mount"],"Five seconds of actual head strokes train once")
	g.reset();check(simulate(g,"front",.9).is_empty() and simulate(g,"front",.1)==["ch_embolden"],"Forward fists require a deliberate one-second hold")
	check(simulate(g,"up",2).is_empty(),"Changing fist pose cannot bypass release latch")
	g.reset();check(simulate(g,"up",1)==["ch_enrage"],"Raised fists trigger enrage")
	var rows:Array=[{"id":"near","pose":pose(0,0,-2),"bounds":AABB(Vector3(-.3,0,-.3),Vector3(.6,2,.6)),"eligible":true},{"id":"far","pose":pose(0,0,-4),"bounds":AABB(Vector3(-.3,0,-.3),Vector3(.6,2,.6)),"eligible":true}]
	check(Target.first(pose(0,1.7,0),Vector3.ZERO,rows).id=="near","Gaze selects the nearest intersected eligible source mesh")
	check(Target.first(pose(0,1.7,0),Vector3.ZERO,rows,1.0).is_empty(),"An actual LOS obstruction rejects creatures behind a wall")
	check(Target.first(pose(1,1.7,0),Vector3.ZERO,rows).is_empty(),"Nearby creatures outside narrow head gaze are not selected")
	rows[0].pose.origin.z=-9;rows[1].eligible=false
	check(Target.first(pose(0,1.7,0),Vector3.ZERO,rows).is_empty(),"Native eligibility and original eight-metre tame limit are enforced")
	check(Target.fist({}, {"grip":1.0,"trigger":.2})<.7 and Target.fist({}, {"grip":1.0,"trigger":1.0})==1,"Controller fallback needs both grip and trigger for a fist")
	var joints:Dictionary={}
	for finger in ["index","ring"]:
		joints[finger+"_proximal"]=Vector3.ZERO;joints[finger+"_intermediate"]=Vector3(0,0,-.03);joints[finger+"_distal"]=Vector3(0,-.025,-.035);joints[finger+"_tip"]=Vector3(0,-.025,-.015)
	check(Target.fist(joints,{"grip":0,"trigger":0})>.7,"Actual XR finger joint curls override controller fallback")
	g.reset();var motion_actions:=0
	for i in range(600):
		var offset:=Vector3(float(i)*.002,0,0);var sample:Dictionary=g.sample(1.0/90,"42","mount",pose(0,1.7,0),pose(-.2,.8,0),pose(.3,1.25,-.4)*Transform3D(Basis.IDENTITY,offset),Vector3(.3,1.25,-.4)+offset,true,true,0,0)
		if not str(sample.action).is_empty():motion_actions+=1
	check(motion_actions==0,"Walking along with a moving pet cannot substitute for head stroking")
	g.reset();var invalid:=pose(0,1.7,0);invalid.basis.x.x=NAN
	var bad:Dictionary=g.sample(.1,"42","buff",invalid,pose(-.25,1.25,-.4),pose(.25,1.25,-.4),Vector3.ZERO,true,true,1,1)
	check(float(bad.progress)==0,"Invalid XR orientation fails closed")
	bad=g.sample(.1,"42","buff",pose(0,1.7,0),pose(-.25,1.25,-.4),pose(.25,1.25,-.4),Vector3.ZERO,true,true,NAN,1)
	check(float(bad.progress)==0,"Invalid curl values cannot begin a fist gesture")
	bad=g.sample(.1,"42","buff",pose(0,1.7,0),pose(-.25,.9,0),pose(.25,.9,0),Vector3.ZERO,true,true,1,1)
	check(str(bad.mode).is_empty() and float(bad.progress)==0,"Fists at hips do not claim the existing both-grip pet recovery")
	var creature:=VisualActor.new();root.add_child(creature)
	var avatar:=preload("res://scripts/avatar.gd").new();creature.add_child(avatar);creature.visual=avatar
	avatar.load_catalog(ProjectSettings.globalize_path("res://../runtime/assets/combat_population/tatooine/catalog.json"))
	var built:Dictionary=avatar.configure("object/mobile/bantha_hue.iff",{"height":.55})
	check(str(built.get("error","")).is_empty() and avatar.skeleton.find_bone("head")>=0,"Real original baby-scale bantha skeleton supplies a head anchor")
	creature.position=Vector3(7,3,-9);creature.rotation.y=.7;avatar.position.y=.27
	var index:=avatar.skeleton.find_bone("head");var original:Vector3=Target.head_anchor(creature)
	check(original.is_equal_approx(avatar.skeleton.global_transform*avatar.skeleton.get_bone_global_pose(index).origin),"Head anchor includes source scale, rotation and presentation floor correction exactly once")
	avatar.skeleton.set_bone_pose_position(index,avatar.skeleton.get_bone_pose_position(index)+Vector3(.1,.2,.3));avatar.skeleton.force_update_all_bone_transforms()
	check(not original.is_equal_approx(Target.head_anchor(creature)),"Head contact follows the animated original skeleton, not actor origin")
	creature.free()
	var report:Dictionary={"passed":failures.is_empty(),"checks":checks,"failures":failures,"gesture_implementation":"native C++","tracking":"mocked","renderer":"dummy","live_xr":false}
	FileAccess.open("res://../runtime/evidence/creature-handler-client.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "));print(JSON.stringify(report));quit(0 if failures.is_empty() else 1)
