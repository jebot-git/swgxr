extends SceneTree
var failures:Array[String]=[]
func check(ok:bool,label:String)->void:
	if not ok:failures.append(label);push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	var fx=preload("res://space/combat_effects.gd").new();root.add_child(fx)
	var shot={"id":"1","kind":"projectile","projectile_type":2,"position":[10,20,30],"direction":[0,0,1],"speed":100,"range":200,"age_seconds":.1}
	fx.receive([shot,shot]);check(fx.effects.size()==1,"Repeated native receipt produces one tracer")
	fx.advance(.1,Transform3D(Basis.IDENTITY,Vector3(5,0,0)))
	check(fx.effects[0].node.global_position.is_equal_approx(Vector3(5,20,-50)),"Native flight and ship-relative presentation preserve axes and age")
	fx.receive([{"id":"2","kind":"hit","hit_type":0,"position":[0,0,0],"age_seconds":2}]);check(fx.effects.size()==1,"Delayed expired hit is omitted")
	fx.advance(2,Transform3D.IDENTITY);check(fx.effects.is_empty(),"Expired native effects are removed")
	fx.queue_free();await process_frame
	print(JSON.stringify({"passed":failures.is_empty(),"failures":failures,"renderer":"dummy","xr":false}));quit(0 if failures.is_empty() else 1)
