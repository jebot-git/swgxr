extends SceneTree
var failures:Array=[]
var probes:Array=[]
func _initialize()->void:call_deferred("run")
func run()->void:
 var audit:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/evidence/core2/portal-closure-audit.json"))
 var world:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/assets/tatooine_world/world.json"))
 var capsule:=CapsuleShape3D.new();capsule.height=1.7;capsule.radius=.25
 for source:Dictionary in audit.portals:
  if not source.exterior or not source.within_expansion or not source.exceeds_10cm:continue
  var coordinates:Array=[];var center:=Vector3.ZERO
  for v:Array in source.local_vertices:coordinates.append_array(v);center+=Vector3(v[0],v[1],v[2])
  center/=source.local_vertices.size()
  var n:=Vector3(source.normal[0],source.normal[1],source.normal[2])
  var portal:Dictionary={"passable":true,"exterior_shell":true,"vertices":coordinates}
  var extent:Dictionary=world.collisions[source.collision].extent
  var body:=StaticBody3D.new();body.collision_layer=1;root.add_child(body)
  for item:Dictionary in SwgCollisionBuilder.new().build_cell_extent(extent,[portal]):
   var shape:=CollisionShape3D.new();shape.shape=item.shape;shape.transform=item.transform;body.add_child(shape)
  var player:=CharacterBody3D.new();player.collision_layer=0;player.collision_mask=1
  var collider:=CollisionShape3D.new();collider.shape=capsule;player.add_child(collider);root.add_child(player)
  await physics_frame;await physics_frame
  var distance:float=absf(float(source.nearest_center_plane.offset_m))+.55
  var hit:=KinematicCollision3D.new()
  var blocked:bool=player.test_move(Transform3D(Basis.IDENTITY,center-n*distance),n*distance*2.0,hit)
  probes.append({"collision":source.collision,"portal":source.portal_id,"closure_offset":source.nearest_center_plane.offset_m,"capsule_blocked":blocked,"center":str(center),"normal":str(n),"hit":str(hit.get_position()) if blocked else "","hit_normal":str(hit.get_normal()) if blocked else "","travel":str(hit.get_travel()) if blocked else ""})
  if blocked:failures.append(str(source.collision)+" portal "+str(source.portal_id))
  player.queue_free();body.queue_free();await process_frame
 var result:Dictionary={"passed":failures.is_empty() and probes.size()==11,"failures":failures,"probes":probes,"actual_source_extents":true,"xr":false}
 FileAccess.open("res://../runtime/evidence/core2/source-shell-portals.json",FileAccess.WRITE).store_string(JSON.stringify(result,"  "));print(JSON.stringify(result));quit(0 if result.passed else 1)
