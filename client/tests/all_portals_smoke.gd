extends SceneTree
## Global source-data regression; no rendered scene or live XR session required.
var report := {"test":"all_source_building_portals_and_floors", "passed":false,
	"buildings":0,"cells":0,"exterior_floor_regions":0,"directed_portals":0,
	"portal_crossings":0,"wide_edge_crossings":0,"split_endpoint_crossings":0,"short_crossings":0,
	"disabled_portals":0,"floor_triangles":0,"fallthrough_triangles":0,
	"upward_solid_triangles":0,"downward_solid_triangles":0,"vertical_solid_triangles":0,
	"floor_support_probes":0,"metadata_errors":0,"failure_count":0,"failures":[]}

func _initialize() -> void:
	call_deferred("run")

func fail(kind: String, cell: String, detail: Dictionary = {}) -> void:
	report.failure_count += 1
	if kind.begins_with("metadata"):
		report.metadata_errors += 1
	if report.failures.size() < 200:
		report.failures.append({"kind":kind,"cell":cell,"detail":detail})

func point(values: Array, index: int) -> Vector3:
	return Vector3(values[index*3],values[index*3+1],values[index*3+2])

func state(cell: Dictionary, id: String) -> String:
	return "" if cell.get("is_exterior",false) else id

func check_crossing(classifier: SwgCellClassifier, from: Vector3, to: Vector3,
		initial: String, expected: String, source: String, portal: Dictionary, label: String) -> void:
	var actual: Dictionary = classifier.advance(from,to,initial)
	report.portal_crossings += 1
	if str(actual.get("cell_id","")) != expected:
		fail("portal_"+label,source,{"portal":portal.id,"target":portal.leads_to,
			"initial":initial,"expected":expected,"actual":actual,
			"from":[from.x,from.y,from.z],"to":[to.x,to.y,to.z]})

func check_cell(id: String, cell: Dictionary, ground: SwgGroundSupport) -> void:
	report.cells += 1
	if cell.get("is_exterior",false):
		report.exterior_floor_regions += 1
	var vertices: Array = cell.get("floor_vertices",[])
	var triangles: Array = cell.get("floor_triangles",[])
	if vertices.size()%3 != 0 or (not triangles.is_empty() and not cell.get("floor_normals_corrected",false)):
		fail("metadata_floor_schema",id)
		return
	var ids := {}
	for triangle: Dictionary in triangles:
		ids[int(triangle.id)] = true
	var probed := false
	for triangle: Dictionary in triangles:
		report.floor_triangles += 1
		var valid := true
		for key: String in ["indices","neighbors","normal","source_normal_raw","edge_flags","portal_ids"]:
			if not triangle.get(key,[]) is Array or triangle.get(key,[]).size()!=3:
				valid=false
		if not valid:
			fail("metadata_triangle_schema",id,{"triangle":triangle.get("id",-1)})
			continue
		for index in triangle.indices:
			if int(index)<0 or int(index)>=vertices.size()/3:valid=false
		for neighbor in triangle.neighbors:
			if int(neighbor)!=-1 and not ids.has(int(neighbor)):valid=false
		for flag in triangle.edge_flags:
			if int(flag)<0 or int(flag)>3:valid=false
		for portal_index in triangle.portal_ids:
			if cell.has("source_pob") and (int(portal_index)<-1 or int(portal_index)>=cell.portals.size()):valid=false
		var normal := point(triangle.normal,0)
		if not normal.is_finite() or not point(triangle.source_normal_raw,0).is_finite():valid=false
		if not valid:
			fail("metadata_triangle_values",id,{"triangle":triangle.id})
			continue
		if triangle.get("fallthrough",false):
			report.fallthrough_triangles += 1
			continue
		if normal.y > 0.00001:report.upward_solid_triangles += 1
		elif normal.y < -0.00001:report.downward_solid_triangles += 1
		else:report.vertical_solid_triangles += 1
		if probed or normal.y<0.05:continue
		var a := point(vertices,int(triangle.indices[0]))
		var b := point(vertices,int(triangle.indices[1]))
		var c := point(vertices,int(triangle.indices[2]))
		if absf((b-a).cross(c-a).y)<0.00001:continue
		var center := (a+b+c)/3.0
		var hit: Dictionary = ground.sample_support(center+Vector3.UP*0.01,[id],0.02,0.02)
		report.floor_support_probes += 1
		probed=true
		if not hit.get("valid",false) or absf(float(hit.get("height",1e20))-center.y)>0.021:
			fail("native_floor_support",id,{"triangle":triangle.id,"expected_height":center.y,"actual":hit})

func check_building(cells: Dictionary) -> void:
	var classifier := SwgCellClassifier.new()
	classifier.configure(cells)
	var ground := SwgGroundSupport.new()
	if not ground.configure([{"transform":Transform3D.IDENTITY,"cells":cells}]):
		fail("metadata_native_floor_rejected",str(cells.keys()[0]))
	for id: String in cells:
		var cell: Dictionary=cells[id]
		check_cell(id,cell,ground)
		for portal_index in range(cell.get("portals",[]).size()):
			var portal: Dictionary=cell.portals[portal_index]
			report.directed_portals += 1
			if not cells.has(str(portal.leads_to)) or int(portal.get("floor_portal_index",-1))!=portal_index:
				fail("metadata_portal_target",id,{"portal":portal.get("id",-1)})
				continue
			var reciprocal := false
			for candidate: Dictionary in cells[str(portal.leads_to)].get("portals",[]):
				if str(candidate.leads_to)==id and int(candidate.id)==int(portal.id):reciprocal=true
			if not reciprocal:fail("metadata_portal_reciprocal",id,{"portal":portal.id,"target":portal.leads_to})
			var blocked: bool=not portal.get("passable",false) or portal.get("source_disabled",false)
			var vertices: Array=portal.get("vertices",[])
			if vertices.size()<9 or vertices.size()%3!=0:
				fail("metadata_portal_polygon",id,{"portal":portal.id});continue
			var center:=Vector3.ZERO
			for v in range(vertices.size()/3):center+=point(vertices,v)
			center/=vertices.size()/3.0
			var normal: Vector3=(point(vertices,1)-point(vertices,0)).cross(point(vertices,2)-point(vertices,0)).normalized()
			if normal.length_squared()<0.5:
				fail("metadata_degenerate_portal",id,{"portal":portal.id});continue
			var initial:=state(cell,id)
			var expected:=state(cells[str(portal.leads_to)],str(portal.leads_to))
			var from:=center-normal*0.12
			var to:=center+normal*0.12
			if blocked:
				report.disabled_portals += 1
				check_crossing(classifier,from,to,initial,initial,id,portal,"blocked")
				continue
			check_crossing(classifier,from,to,initial,expected,id,portal,"center")
			report.short_crossings+=1
			check_crossing(classifier,center-normal*0.01,center+normal*0.01,initial,expected,id,portal,"short_center")
			# Split exactly at the portal plane, as real physics frames often do.
			var first: Dictionary=classifier.advance(from,center,initial)
			report.split_endpoint_crossings+=1
			check_crossing(classifier,center,to,str(first.get("cell_id","")),expected,id,portal,"split_endpoint")
			# Probe near every authored edge, including broad starport doorways.
			for edge in range(vertices.size()/3):
				var edge_center: Vector3=(point(vertices,edge)+point(vertices,(edge+1)%(vertices.size()/3)))*0.5
				var near_edge: Vector3=center.lerp(edge_center,0.85)
				report.wide_edge_crossings+=1
				check_crossing(classifier,near_edge-normal*0.12,near_edge+normal*0.12,initial,expected,id,portal,"edge")
				report.short_crossings+=1
				check_crossing(classifier,near_edge-normal*0.01,near_edge+normal*0.01,initial,expected,id,portal,"short_edge")

func run() -> void:
	var assets := "res://../runtime/assets_review" if "--review-assets" in OS.get_cmdline_user_args() else "res://../runtime/assets"
	var directory:=ProjectSettings.globalize_path(assets.path_join("tatooine_world"))
	var manifest: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("world.json")))
	report["asset_directory"]=directory
	report["hardware_tested"]=false
	report["limitations"]=["Tests source portal crossing geometry and floor support; does not claim full-scene capsule traversal or headset rendering.","Downward or vertical corrected source floor normals are preserved and excluded from upward-support probes."]
	if int(manifest.get("collision_schema_version",0))!=1:
		fail("metadata_missing_collision_schema","world")
	else:
		var buildings: Dictionary={}
		for descriptor: Dictionary in manifest.chunks.values():
			var chunk: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory.path_join(descriptor.path)))
			for id: String in chunk.cells:
				var cell: Dictionary=chunk.cells[id]
				var key:=str(int(cell.get("building_object_id",0))) if cell.has("source_pob") else id
				if not buildings.has(key):buildings[key]={}
				buildings[key][id]=cell
		for cells: Dictionary in buildings.values():
			if cells.values()[0].has("source_pob"):report.buildings+=1
			check_building(cells)
			if report.cells%200<20:await process_frame
	report.passed=report.failure_count==0
	var output:=ProjectSettings.globalize_path("res://../runtime/evidence/all-portals-smoke.json")
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	var summary:=report.duplicate()
	summary.erase("failures")
	print(JSON.stringify(summary))
	if not report.passed:print(JSON.stringify(report.failures.slice(0,8)))
	quit(0 if report.passed else 1)
