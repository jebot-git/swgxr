extends SceneTree
const Peer = preload("res://scripts/service_peer.gd")
var checks := 0
var failures: Array = []
func check(value: bool, message: String) -> void:
	checks+=1
	if not value: failures.append(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var host := Node3D.new()
	root.add_child(host)
	host.position=Vector3(7,2,-3)
	host.rotation.y=0.4
	var peer := Peer.new()
	host.add_child(peer)
	peer.configure()
	check(peer.original_race({"template":"unknown"}).is_empty(),"Unknown native race never silently replaced")
	var row := {"id":"peer1","name":"Source Peer","position":Vector3.ZERO,"hand_position":Vector3(0.3,1.3,-0.35),"tracked":true,"main_hand_side":"right","appearance":{"template":"object/creature/player/human_male.iff","customization":{},"equipment":[],"height":1.0}}
	peer.apply_peer(row)
	check(peer.avatar != null,"Original human native template rendered")
	check(peer.global_position.is_equal_approx(Vector3.ZERO),"Native world position retained beneath transformed parent")
	check(peer.ik_ready,"Native arm IK configured")
	for i in range(10): peer.advance(1.0/90.0)
	check(peer.report.get("hand_ik",{}).get("right",{}).get("valid",false),"Tracked handshake target drives original arm")
	for mesh in peer.avatar.meshes: check(mesh.layers==1,"Remote head visible in world layer")
	peer.velocity=peer.global_basis*Vector3(2,0,0)
	peer.advance(0.05)
	check(peer.avatar.motion_state=="strafe_right","Peer sideways movement selects original strafe")
	peer.velocity=peer.global_basis*Vector3(0,0,2)
	peer.advance(0.05)
	check(peer.avatar.motion_state=="backpedal","Peer backward movement selects original backpedal")
	peer.advance(1.1)
	check(peer.avatar.motion_state=="idle","Stale movement sample returns to idle")
	var before: Transform3D = peer.avatar.skeleton.get_bone_global_pose(peer.avatar.skeleton.find_bone("rwrist"))
	peer.row.tracked=false
	peer.row.hand_position=Vector3(10,100,10)
	peer.advance(0.0)
	check(not peer.row.tracked,"Untracked peer does not drive stale hand target")
	row.appearance.template="object/creature/player/ithorian_male.iff"
	peer.apply_peer(row)
	check(peer.avatar.race_id=="ithorian_male","Native alien template preserved")
	check(peer.ik_ready,"Alien original rig supports handshake")
	row.appearance.template="object/creature/player/missing_male.iff"
	peer.apply_peer(row)
	check(peer.avatar==null and "unavailable" in peer.label.text,"Missing appearance explicitly labeled")
	row.position=Vector3.INF
	peer.apply_peer(row)
	check(not peer.visible,"Invalid world placement rejected")
	var result:={"checks":checks,"failures":failures,"validation":"Mock peer data and dummy renderer, no live multiplayer or XR validation"}
	FileAccess.open(ProjectSettings.globalize_path("res://../runtime/evidence/service-peer-smoke.json"),FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	print(JSON.stringify(result))
	host.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
