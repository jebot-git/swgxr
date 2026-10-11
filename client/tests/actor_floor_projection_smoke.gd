extends SceneTree
const Actor=preload("res://combat/live_actor.gd")
const FloorProjection=preload("res://combat/actor_floor_projection.gd")
class TerrainFixture extends Node:
	var configured:=true
	var evaluator:=SwgTerrainEvaluator.new()
	var origin:=Vector3(3618.98388671875,5,-4801.0859375)
class StageFixture extends Node3D:
	var interior:=false
	var definitions:Dictionary={}
	var exterior_ids:Array=[]
	var ground_support:=SwgGroundSupport.new()
	func classify_world(_point:Vector3)->Dictionary:return {"cell_id":"test:1"} if interior else {}
var checks:=0
var failures:Array=[]
func check(value:bool,label:String)->void:
	if not value:failures.append(label);push_error(label)
	checks+=1
func _initialize()->void:call_deferred("run")
func run()->void:
	var row:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://../runtime/evidence/alpha-grounding-regression/scientist-native-row.json")))
	# Actual native static commoner source placement is one metre under terrain;
	# use the prepared screenshot humanoid appearance to exercise shared policy.
	row.position=[3535.10009765625,4.0,-4724.2001953125]
	var native:=row.duplicate(true)
	var terrain:=TerrainFixture.new();root.add_child(terrain);terrain.evaluator.configure(JSON.parse_string(FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://../runtime/assets/terrain/tatooine.json"))))
	var stage:=StageFixture.new();root.add_child(stage)
	var actor:=Actor.new();root.add_child(actor);actor.configure(row,"recorded",RefCounted.new(),RefCounted.new(),ProjectSettings.globalize_path("res://../runtime/assets/ambient_npcs/catalog.json"));actor.apply_record(row,Transform3D.IDENTITY,.1,true)
	var collider_y:=actor.collider.position.y;var label_y:=actor.label.position.y
	var helper:=FloorProjection.new();helper.apply(actor,row,terrain,stage)
	check(is_equal_approx(actor.presentation_floor_height,1.0),"Source terrain raises buried passive NPC by measured one metre")
	check(actor.record==native and actor.global_position==Vector3.ZERO,"Native identity/source coordinates and actor root preserved")
	check(is_equal_approx(actor.collider.position.y-collider_y,1.0) and is_equal_approx(actor.label.position.y-label_y,1.0),"Visual proxy and label follow presentation")
	for i:int in range(20):helper.apply(actor,row,terrain,stage)
	check(helper.samples==1,"Identical snapshots reuse source sample without per-frame rays")
	for patch:Dictionary in [{"pvp_status":1},{"posture":1},{"posture":8},{"dead":true},{"incapacitated":true},{"building_id":"42","cell_index":1},{"kind":"lair"},{"mood":"npc_sitting_chair"}]:
		var excluded:=row.duplicate(true);excluded.merge(patch,true);helper.apply(actor,excluded,terrain,stage)
		check(actor.presentation_floor_height==0,"Excluded actor retains native pose: "+str(patch))
	# Re-entering eligible state invalidates the prior result, not just position.
	helper.apply(actor,row,terrain,stage);check(is_equal_approx(actor.presentation_floor_height,1.0),"Eligibility transition restores support")
	actor.remove_meta("terrain_projection_key");stage.interior=true;helper.apply(actor,row,terrain,stage)
	check(actor.presentation_floor_height==0,"Source-classified interior excluded even with stale native cell")
	stage.interior=false;row.position=[3526.85009765625,4.44117021560669,-4700.740234375];helper.apply(actor,row,terrain,stage);check(is_equal_approx(actor.presentation_floor_height,.55882978439331),"Second recorded native deficit reconciled")
	row.position=[3468.60205078125,5,-4738.1630859375];helper.apply(actor,row,terrain,stage);check(actor.presentation_floor_height==0,"Exact current scientist already grounded receives no offset")
	row.position[1]=7;helper.apply(actor,row,terrain,stage);check(actor.presentation_floor_height==0,"Above-ground actor never pulled down")
	row.position[1]=2;helper.apply(actor,row,terrain,stage);check(actor.presentation_floor_height==0,"Large mismatch remains explicit rather than hidden")
	# Real Bestine association-hall stair/ramp floor, not a flat test stage.
	var world:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/assets/tatooine_world/world.json"))
	var chunk:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/assets/tatooine_world/"+str(world.chunks["-19:-5"].path)))
	stage.definitions=chunk.cells;stage.ground_support.configure([{"transform":Transform3D.IDENTITY,"cells":chunk.cells}])
	var ramp:Array=[];var ramp_cell:=""
	for id:String in chunk.cells:
		if not id.begins_with("1028590:") or chunk.cells[id].get("is_exterior",false):continue
		var cell:Dictionary=chunk.cells[id];var vertices:Array=cell.get("floor_vertices",[]);var indices:Array=cell.get("floor_indices",[])
		for i in range(0,indices.size(),3):
			var points:Array=[]
			for j in range(3):
				var k:int=int(indices[i+j])*3;points.append(Vector3(vertices[k],vertices[k+1],vertices[k+2]))
			var normal:Vector3=(points[1]-points[0]).cross(points[2]-points[0]).normalized()
			if absf(normal.y)>.65 and absf(normal.y)<.98:ramp=points;ramp_cell=id;break
		if not ramp.is_empty():break
	check(not ramp.is_empty(),"Actual Bestine authored floor contains a walkable slope")
	if not ramp.is_empty():
		row.building_id="1028590";row.cell_index=int(ramp_cell.get_slice(":",1));actor.record=row.duplicate(true)
		var authoritative:=actor.record.duplicate(true)
		for t in [.15,.4,.65]:
			var point:Vector3=ramp[0]*(.8-t)+ramp[1]*t+ramp[2]*.2
			actor.global_position=point-Vector3.UP*.25;helper.bind(actor,row,terrain,stage)
			print("RAMP ",point," ",actor.report.get("terrain_projection")," height ",actor.presentation_floor_height)
			check(absf(actor.presentation_floor_height-.25)<.002,"Moving citizen follows Bestine ramp at interpolation fraction "+str(t))
			actor.global_position=point+Vector3.UP*.2;actor.presentation_floor_update.call()
			check(absf(actor.presentation_floor_height+.2)<.002,"Descending citizen settles to authored floor at "+str(t))
		check(actor.record==authoritative,"Floor presentation leaves authoritative NPC coordinates untouched")
		var missing:=row.duplicate(true);missing.cell_index=999;helper.apply(actor,missing,terrain,stage)
		check(actor.presentation_floor_height==0,"Missing source cell never snaps to a different floor")
	row.building_id="0";row.cell_index=0
	# Exterior building approach floors are distinct from the terrain heightmap.
	var exterior_point:=Vector3.INF
	for id:String in chunk.cells:
		if not chunk.cells[id].get("is_exterior",false):continue
		stage.exterior_ids.append(id)
		var cell:Dictionary=chunk.cells[id];var vertices:Array=cell.get("floor_vertices",[]);var indices:Array=cell.get("floor_indices",[])
		for i in range(0,indices.size(),3):
			var points:Array=[]
			for j in range(3):
				var k:int=int(indices[i+j])*3;points.append(Vector3(vertices[k],vertices[k+1],vertices[k+2]))
			var normal:Vector3=(points[1]-points[0]).cross(points[2]-points[0]).normalized()
			if absf(normal.y)<.65 or absf(normal.y)>.98:continue
			var point:Vector3=(points[0]+points[1]+points[2])/3.0
			var height:float=terrain.evaluator.sample_height(point.x+terrain.origin.x,terrain.origin.z-point.z)-terrain.origin.y
			if point.y-height>.1 and point.y-height<1.5:exterior_point=point
	check(exterior_point.is_finite(),"Actual Bestine exterior approach has a slope above terrain")
	if exterior_point.is_finite():
		actor.record=row.duplicate(true);actor.global_position=exterior_point-Vector3.UP*.15
		helper.bind(actor,row,terrain,stage)
		check(absf(actor.presentation_floor_height-.15)<.002,"Outdoor citizen follows authored approach slope above terrain")
	var combat:=row.duplicate(true);combat.pvp_status=1;helper.bind(actor,combat,terrain,stage)
	check(not actor.presentation_floor_update.is_valid() and actor.presentation_floor_height==0,"Combat actor clears citizen callback and floor offset")
	var ankle:int=actor.visual.skeleton.find_bone("lankle")
	actor.visual.skeleton.set_bone_name(ankle,"nonhumanoid_foot")
	row.position[1]=4;helper.apply(actor,row,terrain,stage);check(actor.presentation_floor_height==0,"Nonhumanoid/flying rigs excluded")
	print(JSON.stringify({"passed":failures.is_empty(),"checks":checks,"failures":failures,"renderer":"dummy","headset_validated":false}));actor.free();stage.free();terrain.free();quit(0 if failures.is_empty() else 1)
