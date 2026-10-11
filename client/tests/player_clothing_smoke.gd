extends SceneTree
## Original rig-bound wearables, including the reported Rodian Mabari boots.
const Avatar=preload("res://scripts/avatar.gd")
const MABARI="object/tangible/wearables/armor/zam/armor_zam_wesell_"
var errors:Array=[]
var checks:=0
var results:Array=[]
var attachment_gaps:Array=[]
func check(value:bool,label:String)->void:
	checks+=1
	if not value:errors.append(label);push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	var assets:=preload("res://scripts/inventory_assets.gd").new();assets.configure()
	for species in ["human","rodian","bothan","moncal","twilek","sullustan","zabrak"]:
		for sex in ["male","female"]:
			var race:String=species+"_"+sex
			var avatar:=Avatar.new();root.add_child(avatar)
			avatar.configure(race,{},[]);avatar.set_tracking_mode(true)
			var skeleton:Skeleton3D=avatar.skeleton
			var placement:Transform3D=avatar.visual_root.transform
			var bare_triangles:=triangles(avatar,"body")
			var items:Array=[]
			for part in ["boots","pants","chest_plate","gloves","belt","helmet"]:
				items.append({"id":part,"template":MABARI+part+".iff"})
			var result:Dictionary=avatar.refresh_equipment(items)
			results.append({"race":race,"mabari":result})
			check(result.get("complete",false),race+" complete original Mabari armor: "+str(result.get("failures",[])))
			if result.get("complete",false):
				for item:Dictionary in items:
					check(avatar.meshes.any(func(mesh):return mesh.get_meta("equipment_id","")==item.id and mesh.visible and mesh.mesh.get_surface_count()>0),race+" visible "+item.id)
				check(triangles(avatar,"body")<bare_triangles,race+" armor occludes covered body triangles")
			check(avatar.skeleton==skeleton and avatar.visual_root.transform==placement,race+" equipping preserves tracked rig and calibration")
			avatar.refresh_equipment([])
			check(triangles(avatar,"body")==bare_triangles,race+" unequipping restores original body")
			avatar.free()
	# Mixed clothing families on the affected rig, not just source starter items.
	var avatar:=Avatar.new();root.add_child(avatar);avatar.configure("rodian_male",{},[])
	var family_counts:Dictionary={}
	for template:String in assets.catalog.get("equipment",{}).get("rodian_male",{}):
		var descriptor:Dictionary=assets.catalog.equipment.rodian_male[template]
		if descriptor.get("status")!="ready":continue
		var family:=template.trim_prefix("object/tangible/wearables/").get_slice("/",0)
		if family_counts.has(family) or family=="armor":continue
		family_counts[family]=1
		var result:Dictionary=avatar.refresh_equipment([{"id":"sample","template":template}])
		if descriptor.get("kind")=="skinned":check(result.get("complete",false),"Rodian "+family+" binds to original skeleton")
		elif not result.get("complete",false):attachment_gaps.append({"template":template,"failures":result.get("failures",[])})
		var preview:ArrayMesh=assets.model(template)
		check(preview!=null,"Inventory preview available for "+family)
	check(family_counts.size()>=12,"Coverage includes different clothing families beyond starter outfits")
	for part in ["boots","pants","chest_plate","gloves","belt","helmet"]:
		var preview:ArrayMesh=assets.model(MABARI+part+".iff")
		check(preview!=null,"Mabari inventory preview: "+part)
	avatar.free();await process_frame
	var report:Dictionary={"passed":errors.is_empty(),"checks":checks,"errors":errors,"mabari_rigs":results,"rodian_families":family_counts.keys(),"rigid_attachment_gaps":attachment_gaps,"renderer":"dummy","headset_tested":false}
	FileAccess.open("res://../runtime/evidence/player-clothing-smoke.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print(JSON.stringify(report));quit(0 if errors.is_empty() else 1)
func triangles(avatar:Node3D,scope:String)->int:
	var total:=0
	for mesh:MeshInstance3D in avatar.meshes:
		if mesh.get_meta("scope","")!=scope:continue
		for i in range(mesh.mesh.get_surface_count()):total+=mesh.mesh.surface_get_array_index_len(i)/3
	return total
