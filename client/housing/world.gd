extends Node3D
const Loader=preload("res://scripts/stage_loader.gd")
var app:Node
var catalog:Dictionary={}
var directory:="res://../runtime/assets/housing"
var structures:Dictionary={}
var items:Dictionary={}
var fall:Dictionary={}
var models=preload("res://scripts/inventory_assets.gd").new()
var cache:Dictionary={}
var collision_builder:=SwgMeshBuilder.new()
func setup(host:Node)->void:
	app=host;models.configure()
	var path:=directory+"/catalog.json"
	if FileAccess.file_exists(path):
		var parsed:Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary:catalog=parsed
func clear()->void:
	for id:String in structures:
		if is_instance_valid(app.stage):app.stage.unregister_cell_region("house:"+id)
		structures[id].queue_free()
	for node:Node3D in items.values():node.queue_free()
	structures.clear();items.clear();fall.clear()
func remap_ids(value:Variant,id:String)->Variant:
	if value is Dictionary:
		var out:Dictionary={}
		for key:Variant in value:
			var target:Variant=id+str(key).substr(1) if str(key).begins_with("1:") else key
			out[target]=int(id) if str(key)=="building_object_id" and int(value[key])==1 else remap_ids(value[key],id)
		return out
	if value is Array:
		var out:Array=[]
		for entry:Variant in value:out.append(remap_ids(entry,id))
		return out
	if value is String and value.begins_with("1:"):return id+value.substr(1)
	return value
func model(template:String,id:String,preview:bool=false)->Node3D:
	var record:Dictionary=catalog.get("structures",{}).get(template,{})
	if record.is_empty():return null
	var path:=directory+"/"+str(record.path)
	if not cache.has(template):cache[template]=JSON.parse_string(FileAccess.get_file_as_string(path))
	if not cache[template] is Dictionary:return null
	var data:Dictionary=remap_ids(cache[template],id)
	var result:Node3D=Loader.new().load_data(data,path)
	if result==null:return null
	if preview:
		for body:Node in result.find_children("*","StaticBody3D",true,false):body.free()
		result.set_physics_process(false)
	return result
func color_preview(node:Node3D,valid:bool)->void:
	if node.has_meta("hologram_valid") and bool(node.get_meta("hologram_valid"))==valid:return
	node.set_meta("hologram_valid",valid)
	var material:=StandardMaterial3D.new();material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;material.albedo_color=Color(.15,.9,1,.16) if valid else Color(1,.12,.08,.24);material.no_depth_test=false
	for mesh:MeshInstance3D in node.find_children("*","MeshInstance3D",true,false):mesh.material_override=material;mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
func mirror_quaternion(q:Array)->Quaternion:return Quaternion(-float(q[0]),-float(q[1]),float(q[2]),float(q[3])).normalized()
func apply(state:Dictionary)->void:
	if not is_instance_valid(app.stage):return
	var keep:Dictionary={}
	for row:Dictionary in state.get("structures",[]):
		var id:=str(row.id);keep[id]=true
		if not structures.has(id):
			var node:=model(str(row.template),id)
			if node==null:continue
			add_child(node);node.global_position=app.services.world(row.position);node.quaternion=mirror_quaternion(row.quaternion)
			node.set_physics_process(false);structures[id]=node
			app.stage.register_cell_region("house:"+id,node,node.classifier,node.exterior_instances,node.get_meta("manifest",{}).get("cells",{}))
	for id:String in structures.keys():
		if not keep.has(id):app.stage.unregister_cell_region("house:"+id);structures[id].queue_free();structures.erase(id)
	keep={}
	for row:Dictionary in state.get("items",[]):
		if row.get("terminal",false):continue
		var id:=str(row.id);keep[id]=true
		if not items.has(id):
			var mesh:ArrayMesh=models.model(str(row.template))
			if mesh==null:continue
			var node:=MeshInstance3D.new();node.mesh=mesh;add_child(node);items[id]=node
			var body:=StaticBody3D.new();body.collision_layer=4;body.collision_mask=0;node.add_child(body)
			var shape:=CollisionShape3D.new();shape.shape=collision_builder.create_collision(mesh);body.add_child(shape)
		var node:Node3D=items[id];node.set_meta("native",row)
		var destination:Vector3=app.services.world(row.position)
		if fall.has(id):
			if node.global_position.distance_to(fall[id])>.05:node.global_position=fall[id]
			fall.erase(id);node.set_meta("fall_target",destination);node.set_meta("fall_speed",0.0)
		elif not node.has_meta("fall_target"):node.global_position=destination
		var basis:=Basis.IDENTITY
		if structures.has(str(row.building_id)):basis=structures[str(row.building_id)].global_basis
		node.global_basis=basis*Basis(mirror_quaternion(row.quaternion))
	for id:String in items.keys():
		if not keep.has(id):items[id].queue_free();items.erase(id)
func _process(dt:float)->void:
	for node:Node3D in items.values():
		if not node.has_meta("fall_target"):continue
		var target:Vector3=node.get_meta("fall_target");var speed:float=float(node.get_meta("fall_speed"))+9.81*minf(dt,.05)
		node.global_position=node.global_position.move_toward(target,speed*minf(dt,.05));node.set_meta("fall_speed",speed)
		if node.global_position.distance_to(target)<.001:node.remove_meta("fall_target")

func touches_structure(id:String,point:Vector3)->bool:
	if not structures.has(id):return false
	for node:MeshInstance3D in structures[id].find_children("*","MeshInstance3D",true,false):
		if node.mesh!=null and node.mesh.get_aabb().grow(.12).has_point(node.to_local(point)):return true
	return false
func structure_from_collider(collider:Variant)->String:
	if not collider is Node:return ""
	var node:Node=collider
	while node!=null:
		for id:String in structures:
			if structures[id]==node:return id
		node=node.get_parent()
	return ""
