extends SceneTree
## Actual streamed Bestine landing ramps, native capsule solver, mocked tracking.
var errors:Array=[]
var profiles:Array=[]
func _initialize()->void:call_deferred("run")
func frames(n:int)->void:
 for i in range(n):await physics_frame
func tracker(id:StringName,hand:XRPositionalTracker.TrackerHand)->XRControllerTracker:
 var t:=XRControllerTracker.new();t.name=id;t.hand=hand;t.type=XRServer.TRACKER_CONTROLLER
 t.set_pose("grip",Transform3D(Basis.IDENTITY,Vector3(.2,1.2,-.3)),Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH)
 t.set_input("primary",Vector2.ZERO);XRServer.add_tracker(t);return t
func run()->void:
 var loader=load("res://scripts/stage_loader.gd").new()
 var stage=loader.empty_stream_stage({"planet":"tatooine","origin":[3618.98388671875,5,-4801.0859375]},Vector3.ZERO)
 root.add_child(stage)
 var world=load("res://scripts/world_stream.gd").new();world.render_distance=128;world.collision_distance=160;root.add_child(world)
 assert(world.configure(ProjectSettings.globalize_path("res://../runtime/assets/tatooine_world/world.json"),stage))
 var terrain=load("res://scripts/terrain_stream.gd").new();root.add_child(terrain)
 assert(terrain.configure(ProjectSettings.globalize_path("res://../runtime/assets/terrain/tatooine.json"),Vector3(3618.98388671875,5,-4801.0859375)))
 var chunk:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/assets/tatooine_world/chunks/-20_-5.json"))
 var entry:Dictionary=chunk.instances.filter(func(i):return i.get("cell_id")=="1026824:0")[0]
 var q:Array=entry.quaternion
 var transform:=Transform3D(Basis(Quaternion(q[0],q[1],q[2],q[3]).normalized()),Vector3(entry.position[0],entry.position[1],entry.position[2]))
 var rows:Array=[{"name":"arrivals","low":Vector3(50.249126,0,-9.930662),"high":Vector3(51.818435,.974694,-10.251678)}, {"name":"departures","low":Vector3(-44.430270,0,-4.147419),"high":Vector3(-44.227169,.974633,-5.659181)}]
 world.update_observer(transform.origin);terrain.update_observer(transform.origin)
 var end:=Time.get_ticks_msec()+90000
 while not world.report.get("ready",false) or not terrain.ready_near(transform.origin):
  assert(Time.get_ticks_msec()<end,"Bestine streaming timeout");await process_frame
 var left:=tracker(&"left_hand",XRPositionalTracker.TRACKER_HAND_LEFT);var right:=tracker(&"right_hand",XRPositionalTracker.TRACKER_HAND_RIGHT)
 for row:Dictionary in rows:
  var low:Vector3=transform*row.low;var high:Vector3=transform*row.high
  var uphill:Vector3=(high-low);uphill.y=0;uphill=uphill.normalized()
  for direction:String in ["up","down"]:
   for mode:String in ["controller","roomscale"]:
    var forward:=uphill if direction=="up" else -uphill
    var spawn:Vector3=(low-uphill*1.1 if direction=="up" else high+uphill*1.1)+Vector3.UP*.06
    var rig:XROrigin3D=load("res://xr/player_rig.tscn").instantiate();root.add_child(rig)
    var body=rig.get_node("PlayerBody");body.ground_provider=stage;body.active=true;body.spawn_point=spawn;body.spawn_yaw=atan2(-forward.x,-forward.z)
    rig.get_node("LeftHand/MovementDirect").max_speed=1.2
    body.prepare_tracked_body();body.reset_spawn();stage.set_observer(body);stage.seed_membership_at(body.global_position,"")
    left.set_input("primary",Vector2.ZERO);await frames(30)
    var head:XRCamera3D=body.get_camera();var tracked:=head.transform;var start:Vector3=body.global_position
    var trace:Array=[]
    if mode=="controller":left.set_input("primary",Vector2(0,1))
    for frame in range(240):
     if mode=="roomscale":head.position.z=tracked.origin.z-4.8*float(frame+1)/240.0
     await physics_frame
     if frame%20==0:
      var contact:=KinematicCollision3D.new();var hit:bool=body.test_move(body.global_transform,forward*.1,contact)
      var ctx:Dictionary=stage.collision_context(body.global_position+forward*.1)
      var floor_guard:Dictionary=stage.ground_support.constrain_motion(body.global_position,forward*.1,ctx.allowed_cell_ids,body.player_radius,body.support_snap_distance)
      trace.append({"position":str(transform.affine_inverse()*body.global_position),"cell":stage.current_cell.get("cell_id",""),"hit":str(contact.get_normal()) if hit else "","collider":str(contact.get_collider().get_meta("collision_source",contact.get_collider().name)) if hit else "","floor_guard":floor_guard})
    left.set_input("primary",Vector2.ZERO);await frames(8)
    var travel:float=(body.global_position-start).dot(forward)
    var expected_pose:=tracked
    if mode=="roomscale":expected_pose.origin.z-=4.8
    var tracking_preserved:=head.transform.is_equal_approx(expected_pose)
    var expected_cell:String=("1026824:16" if row.name=="arrivals" else "1026824:15") if direction=="up" else ""
    var membership_preserved:bool=str(stage.current_cell.get("cell_id",""))==expected_cell
    var ok:bool=travel>3.5 and body.on_ground and tracking_preserved and membership_preserved
    if not ok:errors.append(row.name+" "+direction+" "+mode)
    profiles.append({"ramp":row.name,"direction":direction,"mode":mode,"travel":travel,"end":str(transform.affine_inverse()*body.global_position),"tracking_preserved":tracking_preserved,"membership_preserved":membership_preserved,"passed":ok,"trace":trace})
    print(JSON.stringify(profiles.back()))
    rig.queue_free();await process_frame
 var report:Dictionary={"passed":errors.is_empty(),"errors":errors,"profiles":profiles,"source_building":"1026824","actual_streamed_terrain_and_geometry":true,"hardware_tested":false}
 FileAccess.open("res://../runtime/evidence/xr-bestine-landings.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
 world.queue_free();terrain.queue_free();stage.queue_free();await process_frame;XRServer.remove_tracker(left);XRServer.remove_tracker(right)
 quit(0 if errors.is_empty() else 1)
