extends SceneTree
const Avatar=preload("res://scripts/avatar.gd")
const Hologram=preload("res://scripts/equipment_hologram.gd")
var checks:=0
var errors:Array=[]
func check(value:bool,label:String)->void:
	checks+=1
	if not value:errors.append(label);push_error(label)
func _initialize()->void:create_timer(60).timeout.connect(func():quit(2));call_deferred("run")
func run()->void:
	var world:=Node3D.new();root.add_child(world)
	var avatar:=Avatar.new();world.add_child(avatar)
	var initial:Dictionary=avatar.configure("human_male",{},[]);avatar.set_process(false);avatar.set_tracking_mode(true)
	check(str(initial.get("error","")).is_empty(),"Original human skeleton loads without substitute equipment")
	var skeleton:Skeleton3D=avatar.skeleton
	var hold:=skeleton.find_bone("hold_r");check(hold>=0 and skeleton.find_bone("hold_l")>=0,"Original skeleton supplies both native hand slots")
	var hand_pose:Transform3D=skeleton.get_bone_pose(hold)
	var source_catalog:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/assets/inventory/catalog.json"))
	var hologram:=Hologram.new();world.add_child(hologram)
	for key:String in ["heavy_particle_beam","heavy_acid_beam","heavy_lightning_beam","heavy_rocket_launcher"]:
		var template:="object/weapon/ranged/heavy/"+key+".iff"
		var item:Dictionary={"id":key,"template":template,"equipped_slots":["hold_r","hold_l"],"equip_arrangements":[{"index":0,"slots":["hold_r","hold_l"],"available":true,"displaced_item_ids":[]}]}
		var original:Dictionary=source_catalog.items[source_catalog.get("aliases",{}).get(template,template)]
		check(original.source_arrangement=="abstract/slot/arrangement/wearables/empty.iff" and original.source_arrangements==[[]],"Original empty arrangement stays truthful: "+key)
		var absent:=item.duplicate(true);absent.equipped_slots=[]
		check(avatar.equipment_selection([absent]).rigid.is_empty(),"Heavy exception requires authoritative equipped hand slots: "+key)
		absent.equipped_slots=["hold_r"]
		check(avatar.equipment_selection([absent]).rigid.is_empty(),"Single-slot claim cannot impersonate native hold_both: "+key)
		var result:Dictionary=avatar.refresh_equipment([item])
		check(result.get("ok",false) and result.get("complete",false) and avatar.rigid_equipment.size()==1,"Native heavy attaches through actual avatar equipment consumer: "+key)
		if avatar.rigid_equipment.is_empty():continue
		var attached:Dictionary=avatar.rigid_equipment[0]
		check(attached.attachment.get_parent()==skeleton and attached.attachment.bone_name=="hold_r","Heavy uses original held bone without replacing tracking skeleton: "+key)
		check(attached.source.attachment_provenance=="native_commando_hold_both" and attached.source.source_arrangement==original.source_arrangement,"Derived native attachment and original source descriptor remain distinct: "+key)
		var grip:Basis=preload("res://combat/original_assets.gd").grip_basis(key)
		check(attached.local_transform.basis.is_equal_approx(grip),"Remote/equipment mesh has same +90-degree grip correction as first-person rig: "+key)
		await process_frame;await process_frame
		var expected:Transform3D=skeleton.global_transform*skeleton.get_bone_global_pose(hold)*attached.local_transform
		check(attached.instance.global_transform.is_equal_approx(expected),"Actual bone attachment has correct world placement: "+key)
		hologram.configure(avatar,[item]);check(hologram.show_item(item,Transform3D(Basis.IDENTITY,Vector3(0,1.7,0))),"Equipment hologram opens for native heavy: "+key)
		check(hologram.markers.has("hold_r") and hologram.markers.has("hold_l"),"Both verified native hold markers remain reachable: "+key)
		var copies:Array=hologram.skeleton.find_children("*","MeshInstance3D",true,false).filter(func(node):return node.get_meta("source_equipment",{}).get("template","")==template)
		check(copies.size()==1 and copies[0].transform.basis.is_equal_approx(grip),"Frozen hologram includes correctly oriented original heavy mesh: "+key)
		check(skeleton.get_bone_pose(hold).is_equal_approx(hand_pose) and avatar.skeleton==skeleton,"Heavy equip and hologram do not move tracked hand pose: "+key)
		avatar.set_equipment_visual_hidden([key]);check(not attached.instance.visible,"First-person rig can suppress duplicate avatar heavy: "+key)
		avatar.set_equipment_visual_hidden([])
	world.queue_free();await process_frame;await process_frame
	var report:Dictionary={"checks":checks,"errors":errors,"original_skeleton":true,"native_equipment":"mocked_slots","renderer":"dummy","live_xr":false};print(JSON.stringify(report));FileAccess.open("res://../runtime/evidence/commando-equipment-client.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "));quit(0 if errors.is_empty() else 1)
