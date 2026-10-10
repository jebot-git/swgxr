extends SceneTree
const Fixture=preload("res://tests/talus_shuttle_ground_smoke.gd")
const Policy=preload("res://combat/movement_reconciliation.gd")
func _initialize():call_deferred("run")
func run():
 var host=Fixture.Host.new();root.add_child(host);host.stage=Fixture.Stage.new();host.add_child(host.stage);host.player=Fixture.Player.new();host.add_child(host.player)
 var report:Array=[];var tested:=0;var vulnerable:=0;var seq:=0
 for planet in ["tatooine","corellia","talus","naboo","rori","lok","dantooine","dathomir","endor","yavin4"]:
  var directory="res://../runtime/assets/tatooine_world" if planet=="tatooine" else "res://../runtime/assets/planets/"+planet+"/world"
  var terrain_path="res://../runtime/assets/terrain/tatooine.json" if planet=="tatooine" else "res://../runtime/assets/planets/"+planet+"/terrain/"+planet+".json"
  var manifest=JSON.parse_string(FileAccess.get_file_as_string(directory+"/world.json"))
  var evaluator:=SwgTerrainEvaluator.new();assert(evaluator.configure(JSON.parse_string(FileAccess.get_file_as_string(terrain_path))))
  var origin:=Vector3(manifest.origin[0],manifest.origin[1],manifest.origin[2])
  host.stage.set_meta("manifest",manifest);host.active_planet=planet
  var seen:Dictionary={}
  for chunk:Dictionary in manifest.chunks.values():
   var data=JSON.parse_string(FileAccess.get_file_as_string(directory.path_join(chunk.path)))
   for id:String in data.get("cells",{}):
    var cell:Dictionary=data.cells[id];var source:String=cell.get("source_pob","")
    if seen.has(id) or not cell.get("is_exterior",false) or not ("starport" in source or "landing_pad" in source or "shuttleport" in source):continue
    seen[id]=true
    var native:=SwgGroundSupport.new();assert(native.configure([{"cells":{id:cell}}]));host.player.floors=native;host.player.allowed=[id]
    var count:=0;var lifts:=0;var max_lift:=0.0
    for triangle:Dictionary in cell.get("floor_triangles",[]):
     if triangle.get("fallthrough",false):continue
     var point:=Vector3.ZERO
     for index in triangle.indices:
      var offset:int=int(index)*3;point+=Vector3(cell.floor_vertices[offset],cell.floor_vertices[offset+1],cell.floor_vertices[offset+2])/3
     point.y=evaluator.sample_height(point.x+origin.x,origin.z-point.z)-origin.y
     host.player.terrain_height=point.y
     var legacy=host.player._source_support(point,8,8)
     host.player.global_position=point;seq+=1
     var snapshot={"zone":planet,"position":[point.x+origin.x,point.y+origin.y,origin.z-point.z],"building_id":"0","cell_index":0,"movement_rejected":{"reason":"native_movement_speed_rejected","sequence":seq,"session_id":"audit","character_id":"fixture"}}
     assert(Policy.apply(host,snapshot))
     assert(host.player.global_position.y<=point.y+.351,planet+" "+id+" lifted onto overhead floor")
     if float(legacy.get("height",point.y))>point.y+.5:lifts+=1;max_lift=maxf(max_lift,float(legacy.height)-point.y)
     count+=1
    tested+=count;vulnerable+=lifts
    report.append({"planet":planet,"building":id,"source":source,"samples":count,"old_overhead_lifts":lifts,"maximum_old_lift":max_lift,"passed":true})
  print(JSON.stringify({"planet":planet,"starport_exteriors":seen.size()}))
 assert(tested>0 and vulnerable>0)
 var result={"passed":true,"planets_checked":10,"placements":report,"samples":tested,"old_overhead_lifts":vulnerable,"xr":false,"scope":"Original exterior floor triangles and original terrain; synthetic rejected movement, no headset"}
 FileAccess.open("res://../runtime/evidence/terminal-shuttle-20261010/all-starports.json",FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
 print(JSON.stringify({"passed":true,"placements":report.size(),"samples":tested,"old_overhead_lifts":vulnerable}));host.queue_free();await process_frame;quit()
