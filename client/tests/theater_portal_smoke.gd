extends SceneTree
var failures:Array=[]
var checks:Array=[]
func check(ok:bool,label:String,detail:Variant=null)->void:
 checks.append({"passed":ok,"label":label,"detail":detail})
 if not ok:failures.append(label)
func _initialize()->void:call_deferred("run")
func run()->void:
 var loader=preload("res://scripts/stage_loader.gd").new()
 var stage=loader.load_stage(ProjectSettings.globalize_path("res://../runtime/assets/mos_eisley/scene.json"))
 root.add_child(stage)
 var stream=preload("res://scripts/world_stream.gd").new();stream.render_distance=96;stream.collision_distance=192;root.add_child(stream)
 check(stream.configure(ProjectSettings.globalize_path("res://../runtime/assets/tatooine_world/world.json"),stage),"Original Tatooine stream configures")
 var player=preload("res://scripts/player.gd").new();root.add_child(player);player.testing=true;player.active=false;player.ground_provider=stage
 stage.set_observer(player)
 # Original theatre entrance from core2: cell0 CMSH is 0.842m in front of POB portal.
 var center:=Vector3(-317.9968,.56,-34.7945)
 var outward:=Vector3(.8265,0,.5627).normalized()
 player.position=center+outward*2.5
 stream.update_observer(player.position)
 var deadline:=Time.get_ticks_msec()+60000
 while not stream.report.get("ready",false) and Time.get_ticks_msec()<deadline:await process_frame
 check(stream.report.get("ready",false),"Actual theatre chunk collision publishes")
 for i in range(3):await physics_frame
 for sign_value in [1.0,-1.0]:
  var start:Vector3=center+outward*2.5*sign_value
  player.spawn_point=start;player.reset_spawn();player.active=true;player.test_input=Vector2.ZERO
  stage.seed_membership_at(start,"" if sign_value>0 else "1105845:1")
  for i in range(30):await physics_frame
  var direction:Vector3=-outward*sign_value
  player.test_input=Vector2(direction.x,direction.z)
  for i in range(45):await physics_frame
  player.test_input=Vector2.ZERO
  var crossed:bool=(player.position-center).dot(outward)*sign_value<-.5
  check(crossed,"Full native locomotion crosses theatre doorway "+("inward" if sign_value>0 else "outward"),{"position":str(player.position),"cell":stage.current_cell.get("cell_id","")})
  check(player.is_on_floor(),"Theatre crossing retains grounded feet",str(player.position))
  player.active=false
 var result:Dictionary={"passed":failures.is_empty(),"failures":failures,"checks":checks,"actual_stage":true,"xr":false,"renderer":"dummy"}
 FileAccess.open("res://../runtime/evidence/core2/theater-portal.json",FileAccess.WRITE).store_string(JSON.stringify(result,"  "));print(JSON.stringify(result))
 player.queue_free();stream.queue_free();stage.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
