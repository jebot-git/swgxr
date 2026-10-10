extends SceneTree
const VisibilityRules=preload("res://space/asteroid_visibility.gd")
const Stars=preload("res://space/starfield.gd")
var failures:Array=[]
var checks:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	var field:Dictionary={"Type":1,"Radius":100,"CenterLocationX":0,"CenterLocationY":0,"CenterLocationZ":0,"ViewAllDistance":200,"MaxViewableDistance":1000}
	check(VisibilityRules.fraction(field,Vector3.ZERO)==1,"Inside field renders all rocks")
	check(VisibilityRules.fraction(field,Vector3(300,0,0))==1,"ViewAllDistance is measured from field edge")
	check(is_equal_approx(VisibilityRules.fraction(field,Vector3(700,0,0)),.5),"Half of original prefix at midpoint")
	check(VisibilityRules.fraction(field,Vector3(1100,0,0))==0,"Beyond maximum field distance renders no rocks")
	field.Type=2;field.SplineControlPoints="0,0,0:0,0,1000"
	check(VisibilityRules.fraction(field,Vector3(0,0,-500))==1,"Ribbon coordinates mirror original Z")
	check(is_equal_approx(VisibilityRules.fraction(field,Vector3(700,0,-500)),.5),"Ribbon distance uses nearest segment")
	check(VisibilityRules.prefix_count(PackedInt32Array([0,2,5,7]),5)==2,"Mesh grouping preserves original field prefix")
	check(VisibilityRules.prefix_count(PackedInt32Array([0,2,5,7]),0)==0,"Empty prefix hides all instances")
	var generator:=Stars.new();generator.seed_stream(1)
	check(absf(generator.random_real()-.41599935685098144)<.0000001,"Star random stream matches original ran1 seed fixture")
	var directions:Array[Vector3]=[Vector3.FORWARD,Vector3.BACK,Vector3.LEFT,Vector3.RIGHT,Vector3.UP,Vector3.DOWN]
	for i in range(6):check(Stars.projection(directions[i]).is_equal_approx(Vector3(.5,.5,i)),"Source cubemap face "+str(i))
	var cube:=generator.build(40,null)
	check(cube.get_layers()==6 and cube.get_width()==Stars.SIZE,"Star distribution uses a seamless cubemap")
	var data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/assets/jtl/space_tatooine.json"))
	var row:Dictionary=data.nebula[0].duplicate(true);row.density=0
	var nebula:=preload("res://space/nebulae.gd").new();root.add_child(nebula);nebula.build([row])
	check(nebula.get_child_count()==0,"Zero density creates no nebula quads");nebula.free()
	row.density=.1;row.facingPercent=1
	nebula=preload("res://space/nebulae.gd").new();root.add_child(nebula);nebula.build([row])
	check(nebula.get_child_count()==2,"Facing nebula element uses original paired axes")
	var axes:Array=[]
	for child:MeshInstance3D in nebula.get_children():axes.append(child.material_override.get_shader_parameter("facing_axis"))
	check(axes.has(Vector3.UP) and axes.has(Vector3.RIGHT),"Paired quads constrain X and Y independently")
	nebula.free();row.facingPercent=0
	nebula=preload("res://space/nebulae.gd").new();root.add_child(nebula);nebula.build([row])
	check(nebula.get_child_count()==1 and nebula.get_child(0).material_override.get_shader_parameter("facing_axis")==Vector3.ZERO,"Oriented nebula uses one fixed quad");nebula.free()
	var world:=Node3D.new();root.add_child(world);world.position=Vector3(0,10000,0)
	var sector:=preload("res://space/sector_scene.gd").new();world.add_child(sector)
	check(sector.build("res://../runtime/assets/jtl/space_tatooine.json"),"Actual Tatooine sector builds")
	var pose:=Transform3D(Basis(Vector3.UP,.7),Vector3(500,300,800));sector.observe(pose)
	check(sector.sky.get_shader_parameter("view_origin")==world.position,"Sky camera offset excludes stage height")
	check(sector.sky.get_shader_parameter("sky_cube") is Cubemap,"Original faces use cross-face filtering")
	check(sector.sky.get_shader_parameter("light_colors")[1].length()>0,"Second authored parallel light is preserved")
	for entry:Dictionary in sector.asteroid_fields:
		for group:Dictionary in entry.nodes:check(group.node.visibility_range_end==0,"No whole-field origin-based culling")
	world.free()
	var report:Dictionary={"passed":failures.is_empty(),"checks":checks,"failures":failures,"renderer":"dummy","xr":false}
	print(JSON.stringify(report));FileAccess.open("res://../runtime/evidence/sector-audit-20261010/rules.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	quit(0 if failures.is_empty() else 1)
