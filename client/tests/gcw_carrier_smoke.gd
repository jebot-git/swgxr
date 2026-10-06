extends SceneTree
var checks:=0
var failures:Array=[]
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	var actor:=preload("res://combat/live_actor.gd").new();root.add_child(actor)
	var row:Dictionary={"id":"42","kind":"creature","template":preload("res://gcw/carrier_animation.gd").TEMPLATE,"dead":false,"name":"Lambda shuttle","health":100,"max_health":100,"scale":1.0,"posture":2}
	check(actor.configure(row,"recorded",RefCounted.new(),RefCounted.new(),ProjectSettings.globalize_path("res://../runtime/assets/ambient_npcs/catalog.json")) and actor.report.get("carrier_animation_ready",false),"Actual11-bone original Lambda appearance and four authored clips load")
	check(actor.rigid_equipment.size()==11 and actor.report.appearance_status=="complete","All11 original CDF bone-mounted hull, wings and landing parts load alongside glass");check(actor.visual_bounds().size.x>20 and actor.visual_bounds().size.y>20,"Complete original shuttle bounds reject glass-only conversion")
	actor.set_process(false);var pose:=Transform3D(Basis.IDENTITY,Vector3(3,5,2));actor.apply_record(row,pose,1,true)
	check(actor.collision_layer==0 and actor.collider.disabled and not actor.is_targetable() and not actor.label.visible,"Flying carrier has no stale ground collider, combat target or floating ground nameplate")
	check(actor.visual.animation_player.current_animation=="carrier_ground","First native PRONE snapshot uses original ground loop without invented approach phase")
	check(actor.visual.visual_root.position==Vector3.ZERO,"Carrier preserves authored origin instead of humanoid feet normalization")
	var index:int=actor.visual.skeleton.find_bone("root");var source:Dictionary=actor.visual.get_model(str(actor.visual.animation_library.carrier_ground.path));var original:Array=source.tracks.filter(func(t):return t.name=="root")[0].positions[0];var expected:=Vector3(original[1],original[2],original[3])
	check(actor.visual.skeleton.get_bone_pose_position(index).distance_to(expected)<.001,"Original carrier ground root XYZ offsets are retained exactly")
	actor.visual.animation_player.advance(.3);var before:float=actor.visual.animation_player.current_animation_position;actor.apply_record(row,pose,1);check(is_equal_approx(actor.visual.animation_player.current_animation_position,before),"Repeated native posture does not restart source playback")
	row.posture=0;actor.apply_record(row,pose,1);check(actor.visual.animation_player.current_animation=="carrier_takeoff","Observed PRONE to UPRIGHT plays original takeoff LINK")
	actor.visual.animation_player.advance(4);check(actor.global_transform.is_equal_approx(pose),"Original visual flight never moves authoritative network node")
	var clip:Animation=actor.visual.animation_player.get_animation("carrier_takeoff");var track:=clip.find_track(NodePath("Skeleton:root"),Animation.TYPE_POSITION_3D);var sample:Vector3=clip.position_track_interpolate(track,4)
	check(actor.visual.skeleton.get_bone_pose_position(index).distance_to(sample)<.01 and absf(sample.z-expected.z)>1,"Original moving flight root retained in all axes only on visual skeleton")
	row.posture=2;actor.apply_record(row,pose,1);check(actor.visual.animation_player.current_animation=="carrier_land","Observed UPRIGHT to PRONE plays original landing LINK")
	check(actor.visual.animation_player.get_queue().size()==1 and str(actor.visual.animation_player.get_queue()[0])=="carrier_ground","Landing queues original ground loop")
	var ordinary:=preload("res://combat/live_actor.gd").new();root.add_child(ordinary);var npc:=row.duplicate();npc.template="object/mobile/dressed_rebel_recruiter_human_female_02.iff";npc.posture=0;ordinary.configure(npc,"recorded",RefCounted.new(),RefCounted.new(),ProjectSettings.globalize_path("res://../runtime/assets/ambient_npcs/catalog.json"));check(ordinary.carrier==null and ordinary.visual.visual_root.position.y!=0,"Ordinary original NPC keeps existing locomotion and ground normalization")
	actor.free();ordinary.free();await process_frame
	var report:Dictionary={"passed":failures.is_empty(),"checks":checks,"failures":failures,"original_assets":true,"native_postures":"mocked","renderer":"dummy","live_xr":false};FileAccess.open("res://../runtime/evidence/gcw-carrier.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "));print(JSON.stringify(report));quit(0 if failures.is_empty() else 1)
