extends SceneTree
var checks:=0
var failures:Array=[]
func check(ok:bool,label:String)->void:
 checks+=1
 if not ok:failures.append(label);push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
 var scene_type=preload("res://space/scene.gd")
 var probe=scene_type.new();check(probe.ready_assets(),"Original player ship catalog loads")
 var catalog:Dictionary=probe.catalog;probe.free()
 for template:String in catalog.templates:
  if not "/player/" in template:continue
  var scene=scene_type.new();root.add_child(scene)
  check(scene.build("123",template,"space_heavy1"),"Original hull builds "+template)
  if is_instance_valid(scene.stage):
   if catalog.templates[template].kind=="pob":check(not scene.stage.definitions.is_empty(),"Original cabin cells "+template)
   else:
    var eye:=Vector3(2,1.6,3);scene.align_cockpit(eye)
    check(scene.cockpit.global_position.is_finite(),"Finite cockpit alignment "+template)
    if "tiefighter" in template or "tie_light_duty" in template:
     var grip:Vector3=scene.control_node.to_global(scene.control_grips()[0])
     check(eye.z-grip.z>.5 and eye.y-grip.y>.4,"TIE pilot has comfortable forward/down grip clearance")
    if "z95" in template or "xwing" in template:
     var source:Array=scene.template_entry.cockpit_position
     check(scene.cockpit.to_global(Vector3(source[0],source[1],source[2])).is_equal_approx(eye),"Approved central-stick cockpit placement preserved")
  scene.free();await process_frame
 print(JSON.stringify({"passed":failures.is_empty(),"checks":checks,"failures":failures,"renderer":"dummy","live_xr":false}));quit(0 if failures.is_empty() else 1)
