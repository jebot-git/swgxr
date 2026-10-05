extends SceneTree
const Coverage=preload("res://scripts/world_combat_coverage.gd")
var errors:Array=[]
var checks:=0
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:errors.append(message);push_error(message)
func _initialize()->void:call_deferred("run")
func run()->void:
	var collision:=SwgCombatCollision.new();collision.configure([])
	var proof:=Coverage.new();proof.configure({"chunk_size":64,"chunks":{"own":{"bounds_min":[10,0,10],"bounds_max":[20,3,20]},"neighbor":{"bounds_min":[60,0,25],"bounds_max":[70,3,35]}}},"test:")
	var chunks:Dictionary={"own":{"published":true},"neighbor":{"published":false}}
	# Geometry-only groups cannot certify empty-space coverage themselves.
	collision.set_geometry("object",[],AABB(Vector3.ZERO,Vector3(64,10,64)),0)
	proof.refresh(collision,chunks,[Vector3(32,0,32)],Transform3D.IDENTITY)
	check(collision.trace_segment(Vector3(-20,1,-20),Vector3(-5,1,-5),"",1).complete,"Source-index tile with no objects is known empty, not unknown geometry")
	check(not collision.trace_segment(Vector3(30,1,30),Vector3(50,1,30),"",1).complete,"Neighboring chunk overhang blocks publication until all overlapping source objects load")
	check(not collision.trace_segment(Vector3(72,1,30),Vector3(85,1,30),"",1).complete,"Pending neighbor keeps opposite side of shared tile edge unknown")
	chunks.neighbor.published=true;proof.refresh(collision,chunks,[Vector3(32,0,32)],Transform3D.IDENTITY)
	check(collision.trace_segment(Vector3(30,1,30),Vector3(50,1,30),"",1).complete,"Empty ground beyond object bounds becomes complete after dependency publication")
	check(collision.trace_segment(Vector3(40,1,30),Vector3(75,1,30),"",1).complete,"Ray crosses adjacent fully published source-index tiles")
	chunks.erase("neighbor");proof.refresh(collision,chunks,[Vector3(32,0,32)],Transform3D.IDENTITY)
	check(not collision.trace_segment(Vector3(30,1,30),Vector3(50,1,30),"",1).complete,"Dependency eviction immediately invalidates overlapping tile proof")
	check(not collision.trace_segment(Vector3(72,1,30),Vector3(85,1,30),"",1).complete,"Eviction invalidates both sides of the source chunk edge")
	chunks.neighbor={"published":true};proof.refresh(collision,chunks,[Vector3(32,0,32)],Transform3D.IDENTITY)
	collision.set_geometry("unsupported",[{"unsupported":true}],AABB(Vector3(40,0,20),Vector3(10,5,20)),0)
	check(not collision.trace_segment(Vector3(30,1,30),Vector3(55,1,30),"",1).complete,"Unsupported authored geometry still fails closed inside an otherwise loaded tile")
	collision.remove_geometry("unsupported");collision.set_require_terrain(true)
	check(not collision.trace_segment(Vector3(30,1,30),Vector3(50,1,30),"",7).complete,"Static source completeness never substitutes for unloaded terrain")
	collision.set_geometry("terrain",[],AABB(Vector3.ZERO,Vector3(128,5,128)),2)
	check(collision.trace_segment(Vector3(30,1,30),Vector3(50,1,30),"",7).complete,"Both explicit world and terrain coverage admit clear known ground")
	check(not collision.trace_segment(Vector3(200,1,200),Vector3(220,1,200),"",1).complete,"Unrequested coverage is not extrapolated outside resident region")
	proof.clear(collision)
	check(not collision.trace_segment(Vector3(30,1,30),Vector3(50,1,30),"",1).complete,"Stopping stream removes source tile proofs")
	var report:Dictionary={"passed":errors.is_empty(),"checks":checks,"errors":errors,"gpu_tested":false,"real_http_requests":0}
	print(JSON.stringify(report));FileAccess.open("res://../runtime/evidence/world-combat-coverage-smoke.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "));quit(0 if errors.is_empty() else 1)
