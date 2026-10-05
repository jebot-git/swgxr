extends SceneTree
## Actual original item model dropped onto an imported SWG FLR; dummy renderer.
const Assets=preload("res://scripts/inventory_assets.gd")
const Drops=preload("res://scripts/local_inventory_drops.gd")
const Loader=preload("res://scripts/stage_loader.gd")
var errors: Array[String]=[]

func _initialize() -> void: call_deferred("run")
func check(value: bool,message: String) -> void:
	if not value: errors.append(message); push_error(message)
func point(vertices: Array,index: int) -> Vector3:
	return Vector3(vertices[index*3],vertices[index*3+1],vertices[index*3+2])

func run() -> void:
	var assets:=Assets.new()
	assets.configure()
	var drops:=Drops.new()
	root.add_child(drops)
	drops.configure(assets)
	var scene: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/assets/mos_eisley/scene.json"))
	var floor_id:=""
	var floor_center:=Vector3.ZERO
	var largest:=0.0
	for id: String in scene.cells:
		var cell: Dictionary=scene.cells[id]
		if bool(cell.get("is_exterior",false)): continue
		var vertices: Array=cell.get("floor_vertices",[])
		for triangle: Dictionary in cell.get("floor_triangles",[]):
			if bool(triangle.get("fallthrough",false)) or float(triangle.normal[1])<0.999: continue
			var indices: Array=triangle.indices
			var a:=point(vertices,int(indices[0])); var b:=point(vertices,int(indices[1])); var c:=point(vertices,int(indices[2]))
			var area:=(b-a).cross(c-a).length()
			if area>largest: largest=area; floor_id=id; floor_center=(a+b+c)/3.0
	check(not floor_id.is_empty(),"Actual imported SWG floor unavailable")
	var floor_root:=Node3D.new()
	root.add_child(floor_root)
	var loader:=Loader.new()
	if not floor_id.is_empty(): check(loader.install_floors(floor_root,{floor_id:scene.cells[floor_id]})==1,"Native source FLR collision did not build")
	var item:={"id":"inventory_drop_fixture","template":"object/weapon/melee/knife/knife_stone.iff","quantity":1,"name":"original test item"}
	var source_copy:=item.duplicate(true)
	var pose:=Transform3D(Basis.IDENTITY,floor_center+Vector3.UP*1.5)
	check(drops.drop(item,pose),"Original held appearance failed to create local drop")
	check(item==source_copy,"Local drop mutated source inventory metadata")
	check(not drops.drop(item,pose),"Duplicate source ID created two local items")
	check(drops.reserved_ids().size()==1,"Source inventory slot was not reserved")
	var candidate: Dictionary=drops.nearest(pose.origin)
	check(candidate.get("id","")==item.id and drops.reserved_ids().size()==1,"Nearest search consumed reservation")
	if not candidate.is_empty(): candidate.item.quantity=999
	check(drops.nearest(pose.origin).get("item",{}).get("quantity",0)==1,"Nearest lookup exposed mutable source metadata")
	var body: RigidBody3D=drops.records.get(item.id,{}).get("body")
	var start_y:=pose.origin.y
	var end_y:=start_y
	var speed:=0.0
	if body!=null:
		check(body.collision_layer==32 and body.collision_mask==7 and body.continuous_cd and body.can_sleep,"Drop physics policy differs")
		var collision: CollisionShape3D=drops.records[item.id].collision
		var bounds: AABB=drops.records[item.id].source_bounds
		check(collision.shape.size.is_equal_approx(bounds.size.max(Vector3.ONE*0.012)) and collision.position.is_equal_approx(bounds.get_center()),"Collider does not fit actual displayed original mesh")
		for step in range(240): await physics_frame
		end_y=body.global_position.y; speed=body.linear_velocity.length()
		check(end_y<start_y-0.5,"Original item did not fall under physics")
		check(end_y>=floor_center.y-0.03 and end_y<=floor_center.y+0.3,"Dropped item fell through or floated over original FLR")
		check(speed<0.12,"Dropped item failed to settle on source floor")
		check(not drops.nearest(body.global_position,0.22).is_empty(),"Settled original item cannot be recovered")
		check(drops.nearest(body.global_position+Vector3(5,0,0),0.22).is_empty(),"Pickup radius admitted distant object")
		var hand_point:=body.global_position+Vector3(0,1.2,0.25)
		var hand_pose:=Transform3D(Basis.looking_at(body.global_position-hand_point,Vector3.UP),hand_point)
		check(drops.pickup_candidate(hand_pose).get("id","")==item.id,"Standing aimed short-distance grip cannot recover floor item")
		var turned:=hand_pose; turned.basis=turned.basis.rotated(hand_pose.basis.x,PI/2)
		check(drops.pickup_candidate(turned).is_empty(),"Remote grip accepted item outside deliberate aim cone")
		var far_point:=body.global_position+Vector3(0,2.2,0.3)
		check(drops.pickup_candidate(Transform3D(Basis.looking_at(body.global_position-far_point,Vector3.UP),far_point)).is_empty(),"Remote grip exceeded2m hard range")
		var wall:=StaticBody3D.new(); wall.collision_layer=1;root.add_child(wall)
		var wall_shape:=CollisionShape3D.new();var wall_box:=BoxShape3D.new();wall_box.size=Vector3.ONE*0.45;wall_shape.shape=wall_box;wall.add_child(wall_shape)
		wall.global_position=(hand_point+body.global_position)*0.5
		await physics_frame;await physics_frame
		check(drops.pickup_candidate(hand_pose).is_empty(),"Remote grip passed through solid environment")
		wall.free();await physics_frame

	var invalid:=Transform3D.IDENTITY; invalid.origin.x=NAN
	check(not drops.drop({"id":"bad_pose","template":item.template},invalid),"Nonfinite pose accepted")
	check(not drops.drop({"id":"bad_asset","template":"object/tangible/missing_original.iff"},pose),"Missing original asset received a placeholder")
	check(drops.nearest(Vector3.INF).is_empty(),"Nonfinite pickup query returned an item")
	drops.remove(item.id)
	check(drops.reserved_ids().is_empty(),"Successful recovery did not release local reservation")
	drops.remove(item.id) # Idempotent recovery cleanup.
	await process_frame
	for index in range(Drops.MAX_DROPS):
		check(drops.drop({"id":"capacity_%d"%index,"template":item.template},Transform3D(Basis.IDENTITY,pose.origin+Vector3(index*0.5,4,0))),"Drop rejected below session capacity")
	check(not drops.drop({"id":"overflow","template":item.template},pose),"Session drop cap not enforced")
	var before:=drops.statistics()
	drops.clear()
	check(drops.reserved_ids().is_empty(),"World cleanup retained source reservations")
	await process_frame
	check(drops.get_child_count()==0,"World cleanup retained physics bodies")
	var report:={"ok":errors.is_empty(),"renderer":"dummy; no GPU validation","source_floor":floor_id,"source_floor_file":scene.cells.get(floor_id,{}).get("floor_source",""),"floor_y":floor_center.y,"drop_start_y":start_y,"settled_y":end_y,"settled_speed":speed,"capacity_state":before,"errors":errors}
	var path:=ProjectSettings.globalize_path("res://../runtime/evidence/local-inventory-drops-smoke.json")
	var file:=FileAccess.open(path,FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(report,"  ")+"\n")
	print(JSON.stringify(report))
	drops.queue_free(); floor_root.queue_free()
	await process_frame
	quit(0 if errors.is_empty() else 1)
