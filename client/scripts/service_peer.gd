extends Node3D
## Local session peer presentation. Native appearance and body position only;
## tracked handshake points are transient collaboration data, never RPG authority.
const Avatar = preload("res://scripts/avatar.gd")
var avatar: Node3D
var label: Label3D
var catalog: Dictionary = {}
var catalog_path := ""
var row: Dictionary = {}
var appearance_key := ""
var solver := SwgTrackedIK.new()
var ik_ready := false
var previous_position := Vector3.ZERO
var velocity := Vector3.ZERO
var elapsed := 0.0
var sample_age := 100.0
var report: Dictionary = {}

func configure(path := "") -> void:
	if path.is_empty(): path = ProjectSettings.globalize_path("res://../runtime/assets/characters/catalog.json")
	catalog_path = path
	catalog = Avatar.read_json(path)
	if label == null:
		label = Label3D.new(); label.font = preload("res://resources/fonts/Jupiteroid-Regular.ttf")
		label.font_size = 32
		label.pixel_size = 0.002
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = false
		label.position.y = 2.1
		add_child(label)

func original_race(appearance: Dictionary) -> String:
	var template := str(appearance.get("template",appearance.get("shared_template","")))
	for id: String in catalog.get("races",{}):
		var descriptor: Dictionary = catalog.races[id]
		if template in [str(descriptor.get("template","")),str(descriptor.get("shared_template",""))] and not template.is_empty(): return id
	return ""

func apply_peer(value: Dictionary) -> void:
	if catalog.is_empty(): configure()
	var p: Variant = value.get("position")
	if not p is Vector3 or not p.is_finite():
		visible = false
		return
	visible = true
	row = value.duplicate(true)
	if sample_age>0.001 and sample_age<2.0:
		velocity = (p-previous_position)/sample_age
		if velocity.length()>25.0: velocity=Vector3.ZERO
	else: velocity=Vector3.ZERO
	previous_position = p
	global_position = p
	sample_age = 0.0
	var appearance: Dictionary = row.get("appearance",{})
	var key := JSON.stringify(appearance)
	if key != appearance_key:
		appearance_key = key
		if is_instance_valid(avatar):
			remove_child(avatar)
			avatar.queue_free()
		avatar = null
		ik_ready = false
		var race := original_race(appearance)
		if not race.is_empty():
			avatar = Avatar.new()
			avatar.load_catalog(catalog_path)
			add_child(avatar)
			var height := float(appearance.get("height",1.0))
			if not is_finite(height) or height<0.25 or height>3.0: height=1.0
			var values := {"height":height,"customization":appearance.get("customization",{})}
			if appearance.has("hair_template"): values.hair_template=appearance.hair_template
			if appearance.has("hair_customization"): values.hair_customization=appearance.hair_customization
			report = avatar.configure(race,values,appearance.get("equipment",[]))
			if str(report.get("error","")).is_empty():
				ik_ready = solver.configure(avatar.skeleton)
				if avatar.animation_player != null: avatar.animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
				# Remote heads remain visible; local first-person head exclusion
				# must never leak into another player's source meshes.
				for mesh in avatar.meshes: mesh.layers=1
			else:
				avatar.queue_free()
				avatar=null
		else: report={"error":"Original player appearance unavailable","template":appearance.get("template","")}
	label.text = str(row.get("name","Player")) + ("\nAppearance unavailable" if avatar==null else "")
	var hand: Variant = row.get("hand_position")
	if hand is Vector3 and hand.is_finite():
		var direction: Vector3 = hand-p
		direction.y=0.0
		if direction.length()>0.08: global_rotation.y=atan2(-direction.x,-direction.z)
	if row.has("heading_radians"): global_rotation.y=float(row.heading_radians)
	advance(0.0)

func advance(delta: float) -> void:
	elapsed += maxf(delta,0.0)
	sample_age += maxf(delta,0.0)
	if not is_instance_valid(avatar): return
	var current_velocity := velocity if sample_age<1.0 else Vector3.ZERO
	avatar.update_motion(delta,current_velocity.length(),{"velocity":global_basis.inverse()*current_velocity,"grounded":true})
	if avatar.animation_player != null: avatar.animation_player.advance(delta)
	if not ik_ready or not bool(row.get("tracked",false)) or sample_age>2.0: return
	var hand: Variant = row.get("hand_position")
	if not hand is Vector3 or not hand.is_finite(): return
	var side := "left" if str(row.get("main_hand_side","right"))=="left" else "right"
	var wrist: int = avatar.skeleton.find_bone("lwrist" if side=="left" else "rwrist")
	if wrist<0: return
	var target: Transform3D = avatar.skeleton.get_bone_global_pose(wrist)
	target.origin = avatar.skeleton.to_local(hand)
	if row.get("main_hand_transform") is Transform3D:
		target = avatar.skeleton.global_transform.affine_inverse()*row.main_hand_transform
		target.basis = target.basis.orthonormalized()
	var targets := {side+"_hand":target}
	report["hand_ik"] = solver.solve(targets,maxf(delta,1.0/90.0))
