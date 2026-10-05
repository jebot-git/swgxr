extends SceneTree
const Assets=preload("res://scripts/inventory_assets.gd")
const Tools=preload("res://scripts/deployed_resource_tools.gd")
const Stage=preload("res://scripts/cell_stage.gd")
const Loader=preload("res://scripts/stage_loader.gd")
var errors: Array[String]=[]
func _initialize() -> void: call_deferred("run")
func check(value: bool,message: String) -> void:
	if not value: errors.append(message); push_error(message)
func point(vertices: Array,index: int) -> Vector3:
	return Vector3(vertices[index*3],vertices[index*3+1],vertices[index*3+2])
func run() -> void:
	var scene: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/assets/mos_eisley/scene.json"))
	var stage:=Stage.new(); stage.set_meta("manifest",scene); stage.classifier.configure(scene.cells)
	root.add_child(stage); stage.set_physics_process(false)
	var floors:=Node3D.new(); root.add_child(floors)
	var loader:=Loader.new(); loader.install_floors(floors,scene.cells)
	var observer:=Node3D.new(); root.add_child(observer)
	var assets:=Assets.new(); assets.configure()
	var tools:=Tools.new(); root.add_child(tools); tools.configure(assets); tools.set_context(stage,observer)
	tools.set_physics_process(false)
	await physics_frame; await physics_frame
	var floor_id:=""; var center:=Vector3.ZERO; var largest:=0.0
	for id: String in scene.cells:
		var cell: Dictionary=scene.cells[id]
		if not bool(cell.get("is_exterior",false)): continue
		var vertices: Array=cell.get("floor_vertices",[])
		for triangle: Dictionary in cell.get("floor_triangles",[]):
			if bool(triangle.get("fallthrough",false)) or float(triangle.normal[1])<0.999: continue
			var a:=point(vertices,int(triangle.indices[0])); var b:=point(vertices,int(triangle.indices[1])); var c:=point(vertices,int(triangle.indices[2]))
			var position: Vector3=(a+b+c)/3.0; observer.position=position
			var placement:=tools.ground_placement(Transform3D(Basis.IDENTITY,position+Vector3.UP*0.4))
			var area:=(b-a).cross(c-a).length()
			if placement.get("valid",false) and area>largest: floor_id=id; center=placement.position; largest=area
	check(not floor_id.is_empty(),"No complete original outdoor FLR footprint accepted")
	var interior_checked:=false
	for id: String in scene.cells:
		var cell: Dictionary=scene.cells[id]
		if bool(cell.get("is_exterior",false)): continue
		var vertices: Array=cell.get("floor_vertices",[])
		for triangle: Dictionary in cell.get("floor_triangles",[]):
			if bool(triangle.get("fallthrough",false)): continue
			var p:=(point(vertices,int(triangle.indices[0]))+point(vertices,int(triangle.indices[1]))+point(vertices,int(triangle.indices[2])))/3.0+Vector3.UP*0.4
			if stage.classify_world(p).is_empty(): continue
			observer.position=p
			check(not tools.ground_placement(Transform3D(Basis.IDENTITY,p)).get("valid",false),"Actual source building interior admitted outdoor sampling")
			interior_checked=true; break
		if interior_checked: break
	check(interior_checked,"No actual interior fixture tested")
	observer.position=center
	var pose:=Transform3D(Basis.IDENTITY,center+Vector3.UP*0.4)
	check(tools.ground_placement(pose).get("valid",false),"Authored outdoor floor rejected")
	check(not tools.ground_placement(Transform3D(Basis.IDENTITY,center+Vector3.UP*2.5)).get("valid",false),"Tool allowed to float beyond hand placement reach")
	check(not tools.ground_placement(Transform3D(Basis.IDENTITY,Vector3(99999,2,99999))).get("valid",false),"Missing ground accepted")
	var bad:=pose; bad.origin.x=NAN
	check(not tools.ground_placement(bad).get("valid",false),"Nonfinite pose accepted")
	var source:=tools.source_position(center)
	check(tools.world_position({"position":[source.x,source.y,source.z]}).distance_to(center)<0.001,"Source array conversion failed")
	check(tools.world_position({"position":source}).distance_to(center)<0.001,"Source dictionary conversion failed")
	check(tools.world_position({"planet":"naboo","world_position":center})==null,"Wrong planet admitted")
	var record:={"id":"fixture:1","tool_id":"fixture","template":"object/tangible/survey_tool/survey_tool_mineral.iff","world_position":center,"resource_name":"Original resource fixture","state":"sampling","buffer":[{"quantity":12}]}
	check(tools.set_states([record]),"Confirmed state rejected")
	tools.sync_visuals()
	check(tools.visuals.size()==1,"Original survey tool model unavailable")
	if tools.visuals.size()==1:
		var visual: Dictionary=tools.visuals[record.id]
		var candidate:=tools.nearest(visual.node.to_global(visual.center))
		check(candidate.get("id","")==record.id,"Generation-qualified pickup candidate missing")
		candidate.buffer[0].quantity=999
		check(tools.states[record.id].buffer[0].quantity==12,"Candidate exposed mutable server state")
		check(visual.node.global_position.is_equal_approx(center+Vector3.UP*Tools.HOVER_HEIGHT),"Tool does not hover over source sampling point")
		check(visual.beam.to_global(Vector3.DOWN*Tools.HOVER_HEIGHT*0.5).distance_to(center)<0.001,"Mining beam misses original ground endpoint")
		check(candidate.sampling_position.distance_to(center)<0.001 and candidate.world_position.y>center.y+1.0,"Pickup candidate confuses floating model and server ground position")
		check(visual.label.text.contains("12 units"),"Confirmed buffer count missing")
		check(tools.reserved_ids()==["fixture"],"Reservation uses deployment generation instead of actual item ID")
		observer.position=center+Vector3(4,0,0); tools.sync_visuals()
		check(tools.visuals.size()==1,"Remote confirmed tool incorrectly requires adjacent deployment hand")
		check(not tools.ground_placement(pose).get("valid",false),"Manual deployment allowed distant hand")
	observer.position=center
	var many: Array=[]
	for index in range(40):
		var entry:=record.duplicate(true); entry.id="fixture_%d:1"%index; entry.tool_id="fixture_%d"%index; many.append(entry)
	check(tools.set_states(many),"Authoritative deployment count incorrectly capped")
	for index in range(10): tools.sync_visuals()
	check(tools.states.size()==40 and tools.reserved_ids().size()==40,"Hidden deployments lost server state or reservations")
	check(tools.visuals.size()==32,"Bounded display does not enforce nearest 32 limit")
	check(not tools.set_states([record,record]),"Duplicate state identities accepted")
	check(tools.states.size()==40,"Malformed refresh destroyed confirmed state")
	var missing:=record.duplicate(true); missing.id="missing:1"; missing.tool_id="missing"; missing.template="object/tangible/missing_original.iff"
	check(tools.set_states([missing]),"Unsupported-appearance authoritative state rejected")
	tools.sync_visuals()
	check(tools.visuals.is_empty() and tools.states.size()==1 and tools.report.failures.has(missing.id),"Missing original appearance received substitute or lost server state")
	tools.set_states(many)
	for index in range(10): tools.sync_visuals()
	floors.queue_free(); await process_frame; await physics_frame; tools.sync_visuals()
	check(tools.visuals.is_empty() and tools.states.size()==40,"Unloaded floors left floating tools or erased persistence")
	floors=Node3D.new(); root.add_child(floors); loader.install_floors(floors,scene.cells)
	await physics_frame; await physics_frame
	for index in range(10): tools.sync_visuals()
	check(tools.visuals.size()==32 and tools.states.size()==40,"Original ground reload did not restore confirmed tool visibility")
	var report:={"ok":errors.is_empty(),"renderer":"dummy; no GPU validation","source_floor":floor_id,"source_floor_file":scene.cells.get(floor_id,{}).get("floor_source",""),"state":tools.statistics(),"errors":errors}
	var file:=FileAccess.open("res://../runtime/evidence/deployed-resource-tools-smoke.json",FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(report,"  ")+"\n")
	print(JSON.stringify(report)); tools.clear(); tools.queue_free(); stage.queue_free(); observer.queue_free(); floors.queue_free()
	await process_frame; quit(0 if errors.is_empty() else 1)
