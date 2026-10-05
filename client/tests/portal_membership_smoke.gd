extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var assets := "res://../runtime/assets_review" if "--review-assets" in OS.get_cmdline_user_args() else "res://../runtime/assets"
	var directory:=ProjectSettings.globalize_path(assets.path_join("tatooine_world"))
	var chunk:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("chunks/-1_0.json")))
	var house:Dictionary={}
	for id:String in chunk.cells:
		if id.begins_with("1281533:"):
			house[id]=chunk.cells[id]
	var stage=load("res://scripts/cell_stage.gd").new()
	stage.set_meta("manifest",{"cells":house})
	stage.classifier.configure(house)
	root.add_child(stage)
	var body:=CharacterBody3D.new()
	root.add_child(body)
	body.position=Vector3(-246.63273,.861283,38.20935)
	stage.set_observer(body)
	assert(stage.current_cell.is_empty(),"Exterior ramp misclassified as basement")
	assert(body.collision_mask==7 and stage.interior_floor_regions().is_empty())
	var center:=Vector3(-244.99495,1.13636,38.86325)
	var outward:=Vector3(-.789,0,-.614).normalized()
	var before:=center+outward*.6+Vector3.UP*.5
	var after:=center-outward*.6+Vector3.UP*.5
	var entered:Dictionary=stage.classifier.advance(before,after,"")
	assert(entered.get("cell_id","")=="1281533:1",str(entered))
	assert(stage.classifier.advance(after,before,"1281533:1").is_empty())
	assert(stage.classifier.advance(before+Vector3.UP*10,after+Vector3.UP*10,"").is_empty(),"Crossed outside finite portal polygon")
	stage.seed_pending=false
	stage.current_cell={}
	stage.have_previous=true
	stage.previous_position=before-Vector3.UP*.5
	body.position=after-Vector3.UP*.5
	stage.update_cell()
	assert(stage.current_cell.get("cell_id","")=="1281533:1")
	assert(body.collision_mask==5 and not stage.interior_floor_regions().is_empty())
	var ext:=MeshInstance3D.new()
	ext.set_meta("building_object_id",1281533)
	var collision:=StaticBody3D.new()
	collision.collision_layer=1
	ext.add_child(collision)
	stage.add_child(ext)
	stage.refresh_exterior(ext)
	assert(ext.visible and collision.collision_layer==1,"Membership disabled exterior stair collision")
	body.position=before-Vector3.UP*.5
	stage.update_cell()
	assert(stage.current_cell.is_empty() and body.collision_mask==7 and stage.interior_floor_regions().is_empty())
	var report:Dictionary={"test":"source_house_portal_membership","passed":true,"buried_floor_does_not_capture_exterior":true,"actual_doorway_enter_exit":true,"finite_portal_height":true,"outside_terrain_render_and_collision_retained":true,"exterior_geometry_collision_independent":true,"source_cells":house.size()}
	print(JSON.stringify(report))
	FileAccess.open(ProjectSettings.globalize_path("res://../runtime/evidence/portal-membership-smoke.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	body.queue_free();stage.queue_free()
	await process_frame
	quit()
