extends SceneTree
var errors: Array[String] = []
func _initialize() -> void:
	call_deferred("run")
func check(value: bool, text: String) -> void:
	if not value:
		errors.append(text)
		push_error(text)
func run() -> void:
	var asset_root := "res://../runtime/assets_review" if OS.get_cmdline_user_args().has("--review-assets") else "res://../runtime/assets"
	var native := SwgGroundSupport.new()
	var builder := SwgCollisionBuilder.new()
	var cell := {"building_object_id":123,"floor_vertices":[-2,0,-2,2,0,-2,2,1,2,-2,1,2],"floor_triangles":[
		{"id":7,"indices":[0,1,2],"normal":[0,0.9701425,-0.2425356],"neighbors":[-1,-1,8],"edge_flags":[0,0,1],"portal_ids":[-1,-1,-1]},
		{"id":8,"indices":[0,2,3],"normal":[0,0.9701425,-0.2425356],"neighbors":[7,-1,-1],"edge_flags":[1,0,0],"portal_ids":[-1,-1,-1]}]}
	var upper: Dictionary = cell.duplicate(true)
	for i in range(1,upper.floor_vertices.size(),3):
		upper.floor_vertices[i] += 3
	var hole: Dictionary = cell.duplicate(true)
	for triangle: Dictionary in hole.floor_triangles:
		triangle.fallthrough = true
	check(native.configure([{"transform":Transform3D.IDENTITY,"cells":{"123:1":cell,"123:2":upper,"123:3":hole}}]),"Native floor configure failed")
	var support := native.sample_support(Vector3(0,0.6,0),["123:1"],0.1,0.2)
	check(support.valid and absf(support.height-0.5)<0.00001,"Authored ramp plane height incorrect")
	var capsule := native.capsule_support(Vector3(0,0.6,0),0.25,["123:1"],0.1,0.2)
	check(capsule.valid and absf(capsule.body_height-(0.5+0.25*(sqrt(1.0625)-1)))<0.00001,"Capsule tangent support disagrees with exact ramp plane")
	check(support.get("edge_flags",[]).size()==3 and support.get("neighbors",[]).size()==3,"Authored adjacency metadata lost")
	check(not native.sample_support(Vector3(0,0.6,0),["123:2"],0.1,0.2).valid,"Query attached to another storey")
	check(not native.sample_support(Vector3(0,0.6,0),["123:3"],0.1,0.2).valid,"Fallthrough triangle became support")
	check(not native.sample_support(Vector3(0,2,0),["123:1"],0.1,0.35).valid,"Airborne floor query exceeded snap distance")
	var wall := native.constrain_motion(Vector3(0,0.5,0),Vector3(3,0,0),["123:1"],0.25)
	check(wall.blocked and absf(wall.motion.x-1.75)<0.00001,"Original uncrossable floor edge did not constrain walking radius")
	check(not native.constrain_motion(Vector3(0,4,0),Vector3(3,0,0),["123:1"],0.25).blocked,"Ground-only boundary incorrectly blocked airborne movement")
	var portal_cell: Dictionary=cell.duplicate(true)
	portal_cell.floor_triangles[0].portal_ids[1]=0
	var portal_support := SwgGroundSupport.new()
	portal_support.configure([{"transform":Transform3D.IDENTITY,"cells":{"portal":portal_cell}}])
	check(not portal_support.constrain_motion(Vector3(0,0.5,0),Vector3(3,0,0),["portal"],0.25).blocked,"Source portal did not override raw closed edge flag")
	check(builder.build_floor(cell).get_faces().size()==6,"Authored solid collider did not preserve both triangles")
	check(builder.build_floor(hole)==null,"Fallthrough triangles generated physical floor")
	var box := {"type":"box","min":[-1,-2,-3],"max":[1,2,3]}
	var shapes := builder.build_extent(box)
	check(shapes.size()==1 and shapes[0].shape is BoxShape3D and shapes[0].shape.size==Vector3(2,4,6),"Original box extent changed")
	shapes = builder.build_extent({"type":"detail","children":[box,{"type":"sphere","center":[3,4,5],"radius":0.4}]})
	check(shapes.size()==1 and shapes[0].shape is SphereShape3D and shapes[0].transform.origin==Vector3(3,4,5),"Detail narrow phase used coarse extent")
	shapes = builder.build_extent({"type":"transform","matrix":[0,0,1,4,0,1,0,5,-1,0,0,6],"child":box})
	check(shapes.size()==1 and shapes[0].transform.origin==Vector3(4,5,6) and (shapes[0].transform.basis*Vector3.RIGHT).distance_to(Vector3(0,0,-1))<0.00001,"Component extent transform changed")
	var review := asset_root.path_join("mos_eisley/scene.json")
	var imported := JSON.parse_string(FileAccess.get_file_as_string(review)) as Dictionary
	var count := 0
	var floor_count := 0
	for source: Dictionary in imported.get("collisions",{}).values():
		if source.get("status","")=="authored":
			check(not builder.build_extent(source.get("extent",{})).is_empty(),"Authored imported extent rejected: "+str(source.get("source_appearance","")))
			count += 1
	for source: Dictionary in imported.get("cells",{}).values():
		if builder.build_floor(source)!=null:
			floor_count += 1
	check(count>0 and floor_count>=17,"Real source collision fixture unavailable")
	check(native.configure([{"transform":Transform3D.IDENTITY,"cells":imported.get("cells",{})}]),"Real authored floor data failed validation")
	var foyer := native.sample_support(Vector3(-60,2,10.125),["1106368:4"],0.1,8)
	check(foyer.valid and float(foyer.height)>0.4 and float(foyer.height)<0.8 and Vector3(foyer.normal).y>0.99,"Real source foyer floor height/normal unavailable")
	var report := {"test":"authored_floor_support_and_extents","passed":errors.is_empty(),"errors":errors,"authored_extents":count,"solid_floor_regions":floor_count,"hardware_tested":false,"asset_root":asset_root}
	FileAccess.open("res://../runtime/evidence/ground-support-smoke.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print(JSON.stringify(report))
	quit(0 if errors.is_empty() else 1)
