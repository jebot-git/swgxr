extends SceneTree
const Spread=preload("res://combat/movement_spread.gd")
var checks:=0
var errors:Array=[]
func check(ok:bool,label:String)->void:
 checks+=1
 if not ok:errors.append(label);push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
 var spread=Spread.new()
 var pistol:Dictionary={"class":"heavy_pistol","hands":1}
 var carbine:Dictionary={"class":"burst_carbine","hands":2}
 var rifle:Dictionary={"class":"rifle","hands":2}
 var heavy:Dictionary={"class":"repeater","hands":2}
 spread.sample(Vector3.ZERO,Vector3.ZERO,.02,true)
 check(spread.degrees(rifle)==0,"Stationary rifles add no movement spread")
 spread.sample(Vector3(5,0,0),Vector3.ZERO,.02,true)
 check(spread.degrees(pistol)==0 and is_equal_approx(spread.degrees(carbine),1.2) and is_equal_approx(spread.degrees(rifle),4) and is_equal_approx(spread.degrees(heavy),6),"Pistols exempt, carbines light, rifles/heavy strongly penalized")
 spread.sample(Vector3(2.5,0,0),Vector3.ZERO,.02,true);check(spread.degrees(rifle)>0 and spread.degrees(rifle)<4,"Penalty scales with movement speed")
 spread.sample(Vector3(50,0,0),Vector3.ZERO,.02,true);check(spread.degrees(heavy)==6,"Movement penalty is capped")
 spread.sample(Vector3.ZERO,Vector3(0,1,0),.02,true);check(spread.degrees(rifle)==0,"Vertical pose changes cannot add movement spread")
 spread.sample(Vector3.ZERO,Vector3(.04,1,0),.02,true);check(spread.degrees(rifle)>0,"Roomscale translation contributes")
 spread.sample(Vector3.ZERO,Vector3(100,1,0),.02,true);check(spread.degrees(rifle)==0,"Recenter displacement does not create spread")
 spread.sample(Vector3(5,0,0),Vector3.ZERO,.02,false);check(spread.speed==0,"Tracking loss clears movement evidence")
 for angle:float in [0.,1.2,4.,6.]:
  for u in range(11):
   for v in range(12):
    var d:Vector3=Spread.cone(Vector3.FORWARD,angle,u/10.,v/12.)
    check(is_equal_approx(d.length(),1) and rad_to_deg(d.angle_to(Vector3.FORWARD))<=angle+.001,"Every bolt remains inside the declared cone")
 for forward:Vector3 in [Vector3.UP,Vector3.DOWN]:
  check(Spread.cone(forward,6,.5,.2).is_finite(),"Vertical aiming produces a finite spread direction")
 var body:=CharacterBody3D.new();root.add_child(body)
 var head:=Camera3D.new();body.add_child(head);head.position=Vector3(0,1.7,0)
 var catalog:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/assets/combat/catalog.json"))
 var profile:Dictionary=catalog.weapons.rifle_e11.duplicate(true);profile.item_id="55"
 var rig=preload("res://combat/ranged_rig.gd").new();root.add_child(rig);check(rig.configure(head,body,[profile]),"Production rifle rig configures")
 rig.set_process(false);rig.set_physics_process(false)
 rig.movement_spread.speed=5;rig.movement_spread.rng.seed=123
 var captured:Array=[]
 rig.shot_authority=func(shot:Dictionary,pose:Transform3D,_grip:Vector3)->Dictionary:captured.append({"shot":shot.duplicate(true),"pose":pose});return shot
 var pose:=Transform3D(Basis.IDENTITY,Vector3(0,1.7,0))
 var shot:Dictionary={"weapon_id":profile.id,"core3":profile.core3,"range":50.,"range_scale":1.,"speed":100.,"condition_fraction":1.,"aim_point":Vector3(0,1.7,-10)}
 check(rig.dispatch_shot(shot,pose,pose.origin,profile,false),"Moving targeted shot dispatches")
 check(captured.size()==1 and captured[0].shot.movement_spread_degrees==4,"Spread is captured before authority registration")
 check(rig.rounds_sim.bolts.size()==1 and rig.rounds_sim.bolts[0].direction.is_equal_approx(-captured[0].pose.basis.z),"Network launch and local bolt share the same sampled direction")
 check(not (-captured[0].pose.basis.z).is_equal_approx(Vector3.FORWARD),"Target markers cannot bypass movement spread")
 check(head.position==Vector3(0,1.7,0) and pose.basis==Basis.IDENTITY,"Movement spread never changes tracking or caller pose")
 rig.free();body.free()
 var report:Dictionary={"checks":checks,"errors":errors,"passed":errors.is_empty(),"native_transport":"mocked","headset_tested":false}
 FileAccess.open("res://../runtime/evidence/movement-spread-client.json",FileAccess.WRITE).store_string(JSON.stringify(report));print(JSON.stringify(report));quit(0 if errors.is_empty() else 1)
