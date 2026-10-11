extends Node3D
## Original yacht cells use the same native geometry/portal/ground support as houses.
const Loader=preload("res://scripts/stage_loader.gd")
const Housing=preload("res://housing/world.gd")
var stage:Node3D
var exterior:Node3D
var decorations:Dictionary={}
var models=preload("res://scripts/inventory_assets.gd").new()
var builder:=SwgMeshBuilder.new()
var catalog_path:="res://../runtime/assets/jtl/catalog.json"
var catalog:Dictionary={}
var error:=""
var ship_id:=""
var template_entry:Dictionary={}
var cockpit:Node3D
var control_node:Node3D
var crew:Node3D
var nearby:Dictionary={}
var visual_ship_pose:=Transform3D.IDENTITY
var visual_from:=Transform3D.IDENTITY
var visual_target:=Transform3D.IDENTITY
var visual_age:=0.0
var visual_duration:=.1
var visual_stamp:=-1
var nearby_poses:Dictionary={}
var visual_velocity:=Vector3.ZERO
var visual_angular:=Vector3.ZERO
var nearby_motion:Dictionary={}
var combat_effects:Node3D
func _process(delta:float)->void:
	if visual_stamp<0:return
	visual_age+=delta
	# Dead reckon from native velocity while smoothly removing receipt error.
	# Interpolating toward a stationary receipt made every packet brake the view.
	var horizon:=minf(visual_age,.75)
	var predicted:=visual_target
	predicted.origin+=visual_velocity*horizon
	var rotation_step:=Basis(Vector3.UP,visual_angular.y*horizon)*Basis(Vector3.RIGHT,visual_angular.x*horizon)*Basis(Vector3.BACK,visual_angular.z*horizon)
	predicted.basis=predicted.basis*rotation_step
	var blend:=1.0-exp(-visual_age/.10)
	var advanced_from:=visual_from;advanced_from.basis=advanced_from.basis*rotation_step
	visual_ship_pose=advanced_from.interpolate_with(predicted,blend)
	visual_ship_pose.origin=predicted.origin+(visual_from.origin-visual_target.origin)*(1.0-blend)
	if is_instance_valid(combat_effects):combat_effects.advance(delta,visual_ship_pose)
	if is_instance_valid(exterior):
		exterior.transform=visual_ship_pose.affine_inverse()
		if exterior.has_method("observe"):exterior.observe(visual_ship_pose)
	for id in nearby_poses:
		if nearby_motion.has(id):
			var m:Dictionary=nearby_motion[id];m.age+=delta
			var pose:Transform3D=m.from.interpolate_with(m.target,minf(1.0,m.age/m.duration))
			pose.origin+=m.velocity*clampf(m.age-m.duration,0,.35);nearby_poses[id]=pose
		if nearby.has(id):nearby[id].transform=visual_ship_pose.affine_inverse()*nearby_poses[id]
func observe_motion(pose:Transform3D,velocity:=Vector3.ZERO,angular:=Vector3.ZERO)->void:
	# The action and shared player envelope can contain the same snapshot.
	# Restarting twice shortened every blend to 50ms, then froze until the reply.
	if visual_stamp>=0 and pose.is_equal_approx(visual_target) and velocity.is_equal_approx(visual_velocity) and angular.is_equal_approx(visual_angular):return
	var now:=Time.get_ticks_msec()
	if visual_stamp<0:visual_ship_pose=pose
	visual_from=visual_ship_pose;visual_target=pose;visual_age=0
	visual_duration=clampf((now-visual_stamp)/1000.0,.05,1.5) if visual_stamp>=0 else .1
	visual_velocity=velocity;visual_angular=angular
	visual_stamp=now
	_process(0)

func ready_assets(template:="")->bool:
	if not FileAccess.file_exists(catalog_path):error="Luxury Yacht assets are missing. Install the testing data archive.";return false
	var value:Variant=JSON.parse_string(FileAccess.get_file_as_string(catalog_path))
	if not value is Dictionary:error="Luxury Yacht asset catalog is invalid.";return false
	catalog=value
	template_entry=catalog.get("templates",{}).get(template if not template.is_empty() else "object/ship/player/player_sorosuub_space_yacht.iff",{})
	if template_entry.is_empty():error="This ship’s original cockpit has not been installed.";return false
	var path:=str(template_entry.get("descriptor",""))
	if path.is_empty() or not FileAccess.file_exists(catalog_path.get_base_dir().path_join(path)):error="Original yacht interior stage is unavailable.";return false
	return true
func build(id:String,template:="",sector:="space_tatooine")->bool:
	if not ready_assets(template):return false
	var source:=catalog_path.get_base_dir().path_join(str(template_entry.get("descriptor","")))
	var data:Variant=JSON.parse_string(FileAccess.get_file_as_string(source))
	if not data is Dictionary:error="Yacht stage could not be read.";return false
	var remapper:=Housing.new()
	var remapped:Dictionary=remapper.remap_ids(data,id);remapper.free()
	var loader:=Loader.new();stage=loader.load_data(remapped,source)
	if stage==null:error=str(loader.report.get("error","Yacht geometry could not be loaded."));return false
	combat_effects=preload("res://space/combat_effects.gd").new();add_child(combat_effects)
	ship_id=id;stage.name="OriginalShipCells";add_child(stage);models.configure()
	if template_entry.get("kind","pob")!="pob":
		cockpit=stage
		stage=preload("res://scripts/cell_stage.gd").new();add_child(stage)
		cockpit.set_physics_process(false)
		for body:Node in cockpit.find_children("*","StaticBody3D",true,false):body.free()
	var controls:Dictionary=template_entry.get("controls",{})
	if is_instance_valid(cockpit) and not controls.is_empty():
		var control_path:=catalog_path.get_base_dir().path_join(str(controls.descriptor))
		control_node=Loader.new().load_stage(control_path)
		if not is_instance_valid(control_node):error="Original cockpit controls could not be loaded.";return false
		cockpit.add_child(control_node);control_node.set_physics_process(false)
		for body:Node in control_node.find_children("*","StaticBody3D",true,false):body.free()
	crew=preload("res://multiplayer/remote_players.gd").new();add_child(crew);crew.configure()
	return set_sector(sector)
func set_sector(zone:String)->bool:
	if is_instance_valid(exterior) and exterior.zone==zone:return true
	var entry:Dictionary=catalog.get("sectors",{}).get(zone,{})
	if entry.is_empty():error="Original sector data missing: "+zone;return false
	var next:=preload("res://space/sector_scene.gd").new()
	if not next.build(catalog_path.get_base_dir().path_join(str(entry.descriptor))):error=next.error;next.free();return false
	if is_instance_valid(exterior):exterior.free()
	exterior=next;add_child(exterior)
	visual_stamp=-1
	for id in nearby:nearby[id].queue_free()
	nearby.clear();nearby_poses.clear();nearby_motion.clear()
	return true
func control_grips()->Array:
	var result:Array=[]
	for p:Array in template_entry.get("controls",{}).get("grips",[]):result.append(Vector3(p[0],p[1],p[2]))
	return result
func control_pivot()->Vector3:
	var p:Array=template_entry.get("controls",{}).get("pivot",[0,0,0])
	return Vector3(p[0],p[1],p[2])
func align_cockpit(eye_world:Vector3)->void:
	if not is_instance_valid(cockpit):return
	var eye:Array=template_entry.get("cockpit_position",[0,0,0])
	cockpit.position=to_local(eye_world)-Vector3(float(eye[0]),float(eye[1]),float(eye[2]))
func source(point:Vector3)->Array:
	var p:=stage.to_local(point);return [p.x,p.y,-p.z]
func world(value:Array)->Vector3:
	return stage.to_global(Vector3(float(value[0]),float(value[1]),-float(value[2])))
func cell_index()->int:
	return int(str(stage.current_cell.get("cell_id","")).get_slice(":",1)) if is_instance_valid(stage) else 0
func place_player(body:CharacterBody3D,point:Array,index:int)->void:
	body.apply_world_correction(world(point)-body.global_position)
	body.velocity=Vector3.ZERO
	stage.seed_membership_at(body.global_position,ship_id+":"+str(index))
func observe(ship:Dictionary)->void:
	if ship.has("zone") and str(ship.zone).begins_with("space_"):set_sector(str(ship.zone))
	if is_instance_valid(exterior) and ship.get("position") is Array and ship.get("quaternion") is Array:
		var p:Array=ship.position;var q:Array=ship.quaternion
		var pose:=Transform3D(Basis(Quaternion(-q[0],-q[1],q[2],q[3]).normalized()),Vector3(p[0],p[1],-p[2]))
		var v:Array=ship.get("velocity",[])
		var a:Array=ship.get("angular_velocity",[0,0,0])
		observe_motion(pose,Vector3(v[0],v[1],-v[2]) if v.size()==3 else pose.basis*Vector3(0,0,-float(ship.get("speed_mps",0))),Vector3(-a[0],-a[1],a[2]))
	var keep:Dictionary={}
	for row:Dictionary in ship.get("decorations",[]):
		var id:=str(row.get("id",""));keep[id]=true
		if not decorations.has(id):
			var mesh:ArrayMesh=models.model(str(row.get("template","")))
			if mesh==null:continue
			var node:=MeshInstance3D.new();node.mesh=mesh;stage.add_child(node)
			var body:=StaticBody3D.new();body.collision_layer=4;body.collision_mask=0;node.add_child(body)
			var shape:=CollisionShape3D.new();shape.shape=builder.create_collision(mesh);body.add_child(shape)
			decorations[id]=node
		var item:MeshInstance3D=decorations[id];item.position=Vector3(row.position[0],row.position[1],-row.position[2]);item.set_meta("native",row)
		var q:Array=row.get("quaternion",[0,0,0,1]);item.quaternion=Quaternion(-q[0],-q[1],q[2],q[3]).normalized()
	for id in decorations.keys():
		if not keep.has(id):decorations[id].queue_free();decorations.erase(id)
func update_crew(ship:Dictionary,poses:Array,owner:String,observer:Vector3)->void:
	if not is_instance_valid(crew):return
	# Original small craft expose one CPIT first-person frame and no separate
	# avatar seat anchors yet. Keep the native roster, without overlapping bodies.
	if ship.get("kind","pob")!="pob":crew.clear();return
	var rows:Array=preload("res://space/crew_presentation.gd").new().normalize(ship,poses,owner,stage)
	crew.apply_snapshot(rows,owner,observer,ship_id+":"+str(cell_index()),true)
func update_nearby(rows:Array,ship:Dictionary,busy:=false)->void:
	if not ship.get("position") is Array or not ship.get("quaternion") is Array:return
	var keep:Dictionary={}
	for row:Dictionary in rows.slice(0,32):
		var id:=str(row.get("id",row.get("ship_id","")))
		if id.is_empty() or id==ship_id or not row.get("position") is Array or not row.get("quaternion") is Array:continue
		# Station contacts are authoritative interaction targets, but their original
		# geometry already exists in the authored sector. A second hull z-fights.
		if is_instance_valid(exterior) and exterior.represents_station(row):continue
		var entry:Dictionary=catalog.get("templates",{}).get(str(row.get("template","")),{})
		var descriptor:=str(entry.get("exterior_descriptor",entry.get("descriptor","") if entry.get("kind","pob")=="pob" else ""))
		if descriptor.is_empty():continue
		keep[id]=true
		if not nearby.has(id):
			var loader:=Loader.new();var node:Node3D=loader.load_stage(catalog_path.get_base_dir().path_join(descriptor))
			if node==null:continue
			add_child(node);node.set_physics_process(false)
			for body:Node in node.find_children("*","StaticBody3D",true,false):body.free()
			if is_instance_valid(exterior):
				for mesh:MeshInstance3D in node.find_children("*","MeshInstance3D",true,false):
					for surface in range(mesh.mesh.get_surface_count()):exterior.light_material(mesh.get_active_material(surface))
			nearby[id]=node
		var point:Array=row.position;var rotation:Array=row.quaternion
		var target:=Transform3D(Basis(Quaternion(-rotation[0],-rotation[1],rotation[2],rotation[3]).normalized()),Vector3(point[0],point[1],-point[2]))
		var stamp:=Time.get_ticks_msec();var velocity:Vector3=target.basis*Vector3(0,0,-float(row.get("speed_mps",0)))
		if not nearby_motion.has(id):nearby_poses[id]=target
		elif target.is_equal_approx(nearby_motion[id].target):continue
		var previous_stamp:int=nearby_motion.get(id,{}).get("stamp",stamp-100)
		nearby_motion[id]={"from":nearby_poses[id],"target":target,"velocity":velocity,"stamp":stamp,"age":0.0,"duration":clampf((stamp-previous_stamp)/1000.0,.05,1.5)}
	for id in nearby.keys():
		if not keep.has(id) and (not busy or Time.get_ticks_msec()-int(nearby_motion.get(id,{}).get("stamp",0))>1500):nearby[id].queue_free();nearby.erase(id);nearby_poses.erase(id);nearby_motion.erase(id)
