extends SceneTree
const Policy=preload("res://combat/movement_reconciliation.gd")
class Stage extends Node3D:
 func seed_membership_at(_point:Vector3,_cell:String):pass
class Player extends CharacterBody3D:
 var floors:SwgGroundSupport
 var terrain_height:=20.0
 var allowed:Array=["4965638:0"]
 func _source_support(point:Vector3,up:float,down:float)->Dictionary:
  var found=floors.sample_support(point,allowed,up,down)
  if not found.get("valid",false) and point.y+up>=terrain_height and point.y-down<=terrain_height:found={"valid":true,"height":terrain_height,"terrain":true}
  if found.get("valid",false):found.body_height=found.height
  return found
 func apply_world_correction(delta:Vector3):global_position+=delta
class Host extends Node:
 var active_planet:="talus"
 var stage:Node3D
 var player:CharacterBody3D
func _initialize():call_deferred("run")
func run():
 var data=JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/assets/planets/talus/world/chunks/-9_-9.json"))
 var native:=SwgGroundSupport.new();assert(native.configure([{"cells":{"4965638:0":data.cells["4965638:0"]}}]))
 var host:=Host.new();root.add_child(host);host.stage=Stage.new();host.add_child(host.stage);host.player=Player.new();host.player.floors=native;host.add_child(host.player)
 var checked:=0;var first:Dictionary={}
 for x in range(-2234,-2204):
  for z in range(-2325,-2278):
   var point:=Vector3(x+.25,20,z+.25)
   var legacy=host.player._source_support(point,8,8)
   if not legacy.get("valid",false) or float(legacy.height)<21:continue
   host.player.global_position=point
   var snapshot={"zone":"talus","position":[point.x,20,-point.z],"building_id":"0","cell_index":0,"movement_rejected":{"reason":"native_movement_speed_rejected","sequence":checked+1,"session_id":"fixture","character_id":"fixture"}}
   assert(Policy.apply(host,snapshot))
   assert(host.player.global_position.y<=20.35,"Correction lifted player onto Imperial Outpost landing pad")
   if first.is_empty():first={"position":str(point),"old_height":legacy.height,"new_height":host.player.global_position.y}
   checked+=1
 assert(checked>0,"Fixture did not cover actual overhead landing-pad floor")
 host.queue_free();await process_frame
 print(JSON.stringify({"passed":true,"points_under_original_pad":checked,"example":first,"source_building":"4965638","xr":false,"scope":"Actual original Talus Imperial Outpost floor; synthetic rejected movement"}));quit()
