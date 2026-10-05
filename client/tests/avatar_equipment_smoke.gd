extends SceneTree
## Original skinned apparel/rigid weapon refresh without rebuilding tracked rig.
const Avatar=preload("res://scripts/avatar.gd")
var errors: Array[String]=[]
func _initialize() -> void: call_deferred("run")
func check(value: bool,message: String) -> void:
	if not value: errors.append(message); push_error(message)
func equipment_meshes(avatar: Node3D) -> int:
	var count:=0
	for mesh: MeshInstance3D in avatar.meshes:
		if mesh.get_meta("scope","")=="equipment": count+=1
	return count
func run() -> void:
	var avatar:=Avatar.new(); root.add_child(avatar)
	avatar.load_catalog()
	var hair: Dictionary=avatar.catalog.races.human_male.hair[0]
	var values:={"height":1.08,"hair_template":hair.template,"customization":{"/shared_owner/index_color_0":42},"hair_customization":{}}
	var initial:=avatar.configure("human_male",values,[])
	check(str(initial.error).is_empty(),"Original avatar configuration failed")
	check(equipment_meshes(avatar)==0,"Authoritative empty equipment silently restored starter clothes")
	check(avatar.loaded_parts.any(func(record): return record.scope=="hair"),"Authoritative empty equipment removed source hair")
	avatar.set_tracking_mode(true)
	avatar.transform=Transform3D(Basis.from_euler(Vector3(0,0.4,0)),Vector3(4,0,2))
	avatar.visual_root.position+=Vector3(0.02,0.06,-0.01)
	avatar.visual_root.scale*=1.04
	var skeleton: Skeleton3D=avatar.skeleton
	var player: AnimationPlayer=avatar.animation_player
	var face: AnimationPlayer=avatar.face_player
	var neck:=skeleton.find_bone("neck")
	skeleton.set_bone_pose_rotation(neck,Quaternion(Vector3.UP,0.23))
	var pose:=skeleton.get_bone_pose(neck)
	var visual:=avatar.visual_root.transform
	var placement:=avatar.transform
	var height:=avatar.height_meters
	var source_appearance:=avatar.appearance.duplicate(true)
	var naked_parts:=avatar.meshes.size()
	var items:=[
		{"id":"shirt","template":"object/tangible/wearables/shirt/shirt_s14.iff","customization":{"/private/index_color_1":12}},
		{"id":"bag","template":"object/tangible/wearables/backpack/backpack_s01.iff","customization":{}},
		{"id":"knife","template":"object/weapon/melee/knife/knife_survival.iff","equipped_slots":["hold_r"]}]
	var result:=avatar.refresh_equipment(items)
	check(result.get("ok",false) and result.get("complete",false),"Original equipment did not refresh completely: "+str(result))
	check(result.get("skinned_items",0)==2 and result.get("rigid_items",0)==1,"Original apparel/weapon selection differs")
	check(avatar.skeleton==skeleton and avatar.animation_player==player and avatar.face_player==face,"Equipment refresh replaced tracked skeleton or animation players")
	check(skeleton.get_bone_pose(neck).is_equal_approx(pose),"Equipment refresh overwrote tracked pose")
	check(avatar.visual_root.transform.is_equal_approx(visual) and avatar.transform.is_equal_approx(placement),"Equipment refresh moved or rescaled calibrated avatar")
	check(avatar.height_meters==height and avatar.tracking_mode and not player.active,"Equipment refresh changed height/tracking/playback policy")
	check(avatar.appearance==source_appearance,"Equipment refresh changed original player customization")
	var owner_shader:=false
	for material: Dictionary in avatar.materials:
		if material.scope=="equipment" and material.source.get("shader","")=="shader/skin_body.sht":
			owner_shader=material.source.get("resolved_skin_shader","")=="shader/hum_m_body.sht"
	check(owner_shader,"Original OPST shirt alias was not bound to actual race body material")
	check(avatar.rigid_equipment.size()==1 and avatar.rigid_equipment[0].attachment.get_parent()==skeleton and avatar.rigid_equipment[0].attachment.bone_name=="hold_r","Original weapon does not use authored hold bone")
	avatar.set_equipment_visual_hidden(["knife"])
	check(not avatar.rigid_equipment[0].instance.visible,"Combat-owned weapon duplicated its avatar equipment visual")
	var bag_visible:=false
	for mesh: MeshInstance3D in avatar.meshes:
		if mesh.get_meta("equipment_id","")=="bag": bag_visible=bag_visible or mesh.visible
	check(bag_visible,"Hiding one weapon suppressed unrelated worn backpack")
	avatar.set_equipment_visual_hidden([])
	check(avatar.rigid_equipment[0].instance.visible,"Equipment visual did not restore after combat relinquished ownership")
	var removed:=avatar.refresh_equipment([])
	check(removed.ok and removed.complete and equipment_meshes(avatar)==0 and avatar.rigid_equipment.is_empty(),"Unequip-all retained clothing/weapon or restored starter clothes")
	check(avatar.meshes.size()==naked_parts and avatar.loaded_parts.any(func(record): return record.scope=="hair"),"Unequip-all did not restore body occlusion and original hair")
	check(skeleton.get_bone_pose(neck).is_equal_approx(pose) and avatar.visual_root.transform.is_equal_approx(visual),"Unequip-all changed tracked pose/calibration")
	var unsupported:=avatar.refresh_equipment([{"id":"missing","template":"object/tangible/wearables/shirt/not_in_source.iff"}])
	check(unsupported.ok and not unsupported.complete and unsupported.failures.size()==1 and equipment_meshes(avatar)==0,"Missing source apparel received a substitute or no diagnostic")
	var live_fixture: Dictionary={}
	var fixture:=Avatar.read_json(ProjectSettings.globalize_path("res://../runtime/evidence/equipment-fixture-snapshot.json"))
	if fixture.get("backend","")=="core3" and fixture.get("race","")=="human_male":
		live_fixture=avatar.refresh_equipment(fixture.get("equipment",[]))
		check(live_fixture.ok and live_fixture.complete,"Actual disposable Core3 equipment did not render: "+str(live_fixture))
		check(int(live_fixture.skinned_items)+int(live_fixture.rigid_items)==fixture.get("equipment",[]).size(),"Actual Core3 worn objects were omitted")
		check(avatar.skeleton==skeleton and skeleton.get_bone_pose(neck).is_equal_approx(pose),"Actual Core3 clothing refresh disturbed tracking")
	var report:={"ok":errors.is_empty(),"renderer":"dummy; no GPU or live XR validation","refresh":result,"removed":removed,"unsupported":unsupported,"actual_core3_fixture":live_fixture,"source_race":"human_male","preserved_skeleton_id":skeleton.get_instance_id(),"errors":errors}
	var file:=FileAccess.open("res://../runtime/evidence/avatar-equipment-smoke.json",FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(report,"  ")+"\n")
	print(JSON.stringify(report))
	avatar.queue_free(); await process_frame
	quit(0 if errors.is_empty() else 1)
