extends SceneTree
var errors:Array=[]
var checks:=0
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
 checks+=1
 if not ok:errors.append(label)
func build(exterior:bool,disabled:bool=false)->StaticBody3D:
 # Near closure, separate deeper wall, side jambs, lintel, and floor.
 var vertices:Array=[];var indices:Array=[]
 for x in [.842,1.6]:
  var offset:int=vertices.size()/3
  vertices.append_array([x,0,-4,x,0,4,x,5,4,x,5,-4]);indices.append_array([offset,offset+1,offset+2,offset,offset+2,offset+3])
 var floor_start:int=vertices.size()/3
 vertices.append_array([-2,0,-4,-2,0,4,2,0,4,2,0,-4]);indices.append_array([floor_start,floor_start+1,floor_start+2,floor_start,floor_start+2,floor_start+3])
 var portal:Dictionary={"passable":true,"source_disabled":disabled,"exterior_shell":exterior,"vertices":[0,.2,-3,0,4.6,-3,0,4.6,3,0,.2,3]}
 var body:=StaticBody3D.new();body.collision_layer=1
 for part:Dictionary in SwgCollisionBuilder.new().build_cell_extent({"type":"mesh","vertices":vertices,"indices":indices},[portal]):
  var shape:=CollisionShape3D.new();shape.shape=part.shape;shape.transform=part.transform;body.add_child(shape)
 root.add_child(body);return body
func run()->void:
 # Props sharing exterior cell membership must retain their exact collision.
 var loader=preload("res://scripts/stage_loader.gd").new()
 var definition:Dictionary={"status":"authored","extent":{"type":"mesh","vertices":[0,0,-2,0,0,2,0,4,2,0,4,-2],"indices":[0,1,2,0,2,3]}}
 var cell:Dictionary={"collision_id":"shell","is_exterior":true,"portals":[{"passable":true,"vertices":[0,0,-1,0,3,-1,0,3,1,0,0,1]}]}
 var prop:StaticBody3D=loader.make_collision_body({"collision_id":"prop","cell_id":"1:0"},{"prop":definition},null,{"1:0":cell})
 root.add_child(prop);await physics_frame;await physics_frame
 check(not prop.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(-1,1.5,0),Vector3(1,1.5,0),1)).is_empty(),"Exterior-cell prop is not mistaken for a portal shell")
 prop.queue_free();await process_frame
 for config in [[true,false],[false,false],[true,true]]:
  var body:=build(config[0],config[1]);await physics_frame;await physics_frame
  var space=body.get_world_3d().direct_space_state
  var center:=space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(-.2,2,0),Vector3(1.1,2,0),1))
  check(center.is_empty()==(config[0] and not config[1]),"Only an enabled exterior portal opens its nearby offset closure: "+str(config))
  for sample in [Vector3(0,2,3.3),Vector3(0,4.8,0)]:
   check(not space.intersect_ray(PhysicsRayQueryParameters3D.create(sample+Vector3.LEFT,sample+Vector3.RIGHT*1.1,1)).is_empty(),"Retained jamb or lintel "+str(config))
  check(not space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(1.1,2,0),Vector3(1.9,2,0),1)).is_empty(),"Deeper unrelated wall remains "+str(config))
  check(not space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(.4,1,0),Vector3(.4,-1,0),1)).is_empty(),"Floor remains "+str(config))
  body.queue_free();await process_frame
 var result:Dictionary={"passed":errors.is_empty(),"checks":checks,"errors":errors,"xr":false}
 FileAccess.open("res://../runtime/evidence/core2/portal-shell-depth.json",FileAccess.WRITE).store_string(JSON.stringify(result,"  "));print(JSON.stringify(result));quit(0 if errors.is_empty() else 1)
