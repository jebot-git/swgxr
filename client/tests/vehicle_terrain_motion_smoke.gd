extends "res://tests/vehicle_wheel_drive_smoke.gd"
## Original X31 hull, production local driver path, resident terrain and solid wall.
func run()->void:
	var app:=Host.new();root.add_child(app)
	var driver=load("res://vehicles/controller.gd").new();app.add_child(driver);driver.set_process(false);driver.set_physics_process(false)
	driver.state={"driver_motion":"client_pose"}
	var assets=load("res://scripts/inventory_assets.gd").new();assets.configure(ProjectSettings.globalize_path("res://../runtime/assets/vehicles/catalog.json"))
	var mesh:Mesh=assets.model("object/mobile/vehicle/landspeeder_x31.iff")
	var hull:=CharacterBody3D.new();hull.collision_layer=32;hull.collision_mask=7;app.add_child(hull)
	var collision:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=mesh.get_aabb().size;collision.shape=box;collision.position=mesh.get_aabb().get_center();hull.add_child(collision)
	var terrain:=StaticBody3D.new();terrain.collision_layer=2;terrain.collision_mask=0;app.add_child(terrain)
	var shape:=ConcavePolygonShape3D.new();shape.set_faces(PackedVector3Array([Vector3(-20,-1,10),Vector3(-20,3,-30),Vector3(20,3,-30),Vector3(-20,-1,10),Vector3(20,3,-30),Vector3(20,-1,10)]))
	var floor_shape:=CollisionShape3D.new();floor_shape.shape=shape;terrain.add_child(floor_shape)
	hull.position=Vector3(0,.001,0)
	await physics_frame;await physics_frame
	var v:Dictionary={"node":hull,"speed":5.0}
	for i in 100:driver.move_driver(v,Vector3(0,0,-.05))
	verify(absf(hull.position.y-.501)<.01 and absf(hull.position.z+5)<.1,"Original chassis follows resident uphill terrain with local motion")
	var wall:=StaticBody3D.new();wall.collision_layer=4;wall.collision_mask=0;app.add_child(wall);wall.position=Vector3(0,3,-10)
	var wall_shape:=CollisionShape3D.new();var wall_box:=BoxShape3D.new();wall_box.size=Vector3(15,8,.2);wall_shape.shape=wall_box;wall.add_child(wall_shape)
	await physics_frame;await physics_frame
	for i in 100:driver.move_driver(v,Vector3(0,0,-.05))
	verify(hull.position.z> -7.1 and v.speed==0,"Full original chassis hull still collides with source-solid wall")
	var before:=hull.position
	for i in 50:driver.move_driver(v,Vector3(0,0,.05))
	verify(hull.position.y<before.y-.2,"Local chassis follows descending resident terrain without hovering at prior elevation")
	app.queue_free();await process_frame
	var report:Dictionary={"passed":failures.is_empty(),"checks":count,"failures":failures,"source_vehicle":"object/mobile/vehicle/landspeeder_x31.iff","renderer":"headless dummy","native_server_tested":false}
	FileAccess.open("res://../runtime/evidence/vehicle-terrain-motion.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"));print(JSON.stringify(report));quit(0 if failures.is_empty() else 1)
