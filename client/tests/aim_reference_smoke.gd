extends SceneTree
const AimReference = preload("res://combat/aim_reference.gd")
var checks := 0
var errors: Array[String] = []

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		errors.append(message)
		push_error(message)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var aim := AimReference.new()
	world.add_child(aim)
	var art := ImageTexture.create_from_image(Image.create(4,4,false,Image.FORMAT_RGBA8))
	aim.configure(art)
	var material: ShaderMaterial = aim.material_override
	check(material.render_priority == Material.RENDER_PRIORITY_MAX,"Reticle renders at highest transparent material priority")
	check(material.shader.code.contains("depth_test_disabled") and material.shader.code.contains("depth_draw_never"),"Reticle ignores scene depth without writing depth")
	check(material.get_shader_parameter("source_art") == art,"Reticle preserves supplied original artwork")
	check(not aim.visible and aim.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,"Reticle starts hidden and casts no scene shadow")
	for angle in [0.0,0.7,-1.4]:
		var basis := Basis.from_euler(Vector3(0.2,angle,0.1))
		var reference := Transform3D(basis.scaled(Vector3(1.1,0.9,1.2)),Vector3(4,1.7,-6))
		aim.update_aim(reference,true)
		var direction := -reference.basis.orthonormalized().z
		check(aim.visible and aim.global_position.is_equal_approx(reference.origin+direction*3.0),"Reticle retains 3 m world anchor at yaw %.1f" % angle)
		check(aim.global_basis.is_equal_approx(reference.basis.orthonormalized()),"Reticle retains aim orientation independent of source scale")
		check(is_equal_approx(aim.global_basis.determinant(),1.0),"Reticle remains fixed physical size for stereo projection")
	var camera:=Camera3D.new(); world.add_child(camera)
	aim.update_head_aim(camera,true)
	for frame in range(120):
		# Move AFTER the combat update: late head poses must not require another
		# reticle update or leave a stale world-space transform behind.
		camera.transform=Transform3D(Basis.from_euler(Vector3(sin(frame)*0.1,frame*0.01,0.02)),Vector3(frame*0.03,1.6+sin(frame)*0.02,0))
		var relative:Transform3D=camera.global_transform.affine_inverse()*aim.global_transform
		check(relative.is_equal_approx(Transform3D(Basis.IDENTITY,Vector3(0,0,-3))),"Late head movement preserves fixed view-space reticle")
	var reference:=Transform3D(Basis(Vector3.UP,0.4),Vector3(1,2,3))
	aim.update_aim(reference,true)
	var fixed:Transform3D=aim.global_transform
	camera.rotate_y(0.7); camera.position+=Vector3.ONE
	check(aim.global_transform.is_equal_approx(fixed),"Returning to ranged aim detaches from head")
	aim.update_aim(Transform3D.IDENTITY,false)
	check(not aim.visible,"Disabling aim hides the reference immediately")
	var report := {"test":"aim_reference_material_and_anchor","checks":checks,"passed":errors.is_empty(),"errors":errors,"gpu_validated":false,"hardware_tested":false}
	FileAccess.open("res://../runtime/evidence/aim-reference-smoke.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print(JSON.stringify(report))
	world.queue_free()
	await process_frame
	quit(0 if errors.is_empty() else 1)
