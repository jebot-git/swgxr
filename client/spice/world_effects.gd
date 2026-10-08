extends Node3D
## Local original-mesh overlays. No network writes, actor relation or collision changes.
var app:Node
var outlines:Dictionary={}
var outline_sources:Dictionary={}
var source_assets:RefCounted
var source_dead_assets:RefCounted
var painted:Dictionary={}
var outline_material:ShaderMaterial
var hostile_material:ShaderMaterial
var poll:=0.0
var glove_overrides:Dictionary={}
var profile_key:=""
var profile_busy:=false
var epoch:=-1
func setup(host:Node)->void:
	app=host;epoch=app.datapad_epoch;process_priority=40
	outline_material=ShaderMaterial.new();outline_material.shader=preload("res://spice/outline.gdshader");outline_material.render_priority=110
	hostile_material=ShaderMaterial.new();hostile_material.shader=preload("res://spice/hostile_illusion.gdshader")
func meshes(node:Node)->Array:
	var result:Array=[]
	if node is MeshInstance3D and node.mesh!=null:result.append(node)
	for child:Node in node.get_children():result.append_array(meshes(child))
	return result
func reset()->void:
	for bundle:Dictionary in outlines.values():
		for pair:Dictionary in bundle.parts:if is_instance_valid(pair.proxy):pair.proxy.free()
	outlines.clear()
	for actor:Node in outline_sources.values():actor.free()
	outline_sources.clear()
	for bundle:Dictionary in painted.values():restore(bundle)
	painted.clear();clear_gloves();profile_key="";profile_busy=false;epoch=app.datapad_epoch if is_instance_valid(app) else -1
func restore(bundle:Dictionary)->void:
	for part:Dictionary in bundle.parts:
		if is_instance_valid(part.mesh) and part.mesh.material_overlay==hostile_material:part.mesh.material_overlay=part.previous
	if is_instance_valid(bundle.get("label")):
		bundle.label.remove_meta("spice_hostile_illusion");bundle.label.modulate=bundle.label_color
		if bundle.label.get_parent().has_method("refresh_label"):bundle.label.get_parent().refresh_label()
func add_outline(actor:Node3D)->void:
	var parts:Array=[]
	for original:MeshInstance3D in meshes(actor.visual):
		var proxy:=MeshInstance3D.new();proxy.mesh=original.mesh;proxy.skin=original.skin;proxy.material_override=outline_material;proxy.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;proxy.ignore_occlusion_culling=true
		add_child(proxy);proxy.global_transform=original.global_transform
		var skeleton:=original.get_node_or_null(original.skeleton)
		if skeleton is Skeleton3D:proxy.skeleton=skeleton.get_path()
		parts.append({"source":original,"proxy":proxy})
	outlines[actor.get_instance_id()]={"actor":actor,"parts":parts}
func refresh(actors:Array,ambient:Array,center:Vector3,policy:Dictionary)->void:
	var wanted:Dictionary={};var hostile:Dictionary={}
	for actor:Node3D in actors:
		if not is_instance_valid(actor) or actor.record.get("kind","")!="creature" or actor.record.get("dead",false):continue
		if policy.outlines and bool(actor.record.get("aggressive",false)) and actor.global_position.distance_to(center)<=64:
			wanted[actor.get_instance_id()]=actor
		if policy.hostile_illusion:hostile[actor.get_instance_id()]={"node":actor.visual,"label":actor.label}
	if policy.hostile_illusion:
		for avatar:Node3D in ambient:
			if is_instance_valid(avatar):hostile[avatar.get_instance_id()]={"node":avatar}
	for id in outlines.keys():
		if not wanted.has(id) or not is_instance_valid(outlines[id].actor):
			for part:Dictionary in outlines[id].parts:if is_instance_valid(part.proxy):part.proxy.free()
			outlines.erase(id)
	for id in wanted:if not outlines.has(id):add_outline(wanted[id])
	for id in painted.keys():
		if not hostile.has(id):restore(painted[id]);painted.erase(id)
	for id in hostile:
		if painted.has(id):continue
		var row:Dictionary=hostile[id];var parts:Array=[]
		for mesh:MeshInstance3D in meshes(row.node):parts.append({"mesh":mesh,"previous":mesh.material_overlay});mesh.material_overlay=hostile_material
		var bundle:Dictionary={"parts":parts,"label":row.get("label")}
		if is_instance_valid(bundle.label):bundle.label_color=bundle.label.modulate;bundle.label.set_meta("spice_hostile_illusion",true);bundle.label.modulate=Color("ff2020")
		painted[id]=bundle
func copy_transforms()->void:
	for bundle:Dictionary in outlines.values():
		for pair:Dictionary in bundle.parts:
			if is_instance_valid(pair.source) and is_instance_valid(pair.proxy):pair.proxy.global_transform=pair.source.global_transform
func sync_outline_sources(rows:Array,normal:Array)->Array:
	var present:Dictionary={};var existing:Dictionary={}
	for actor:Node in normal:existing[str(actor.record.get("id",""))]=true
	for row in rows.slice(0,256):
		if not row is Dictionary or not bool(row.get("outline_only",false)) or not bool(row.get("aggressive",false)) or row.get("kind","")!="creature" or bool(row.get("dead",true)):continue
		var id:=str(row.get("id",""))
		if id.is_empty() or existing.has(id) or not preload("res://multiplayer/replication_state.gd").finite_point(row.get("position")) or not is_finite(float(row.get("heading_radians",NAN))):continue
		present[id]=row
	for id in outline_sources.keys():
		if not present.has(id) or outline_sources[id].record.get("template","")!=present[id].get("template",""):
			outline_sources[id].free();outline_sources.erase(id)
	var created:=0
	for id in present:
		var row:Dictionary=present[id];var initial:=false
		if not outline_sources.has(id):
			if created>=2:continue
			created+=1
			if source_assets==null:
				source_assets=preload("res://scripts/inventory_assets.gd").new();source_assets.configure()
				source_dead_assets=preload("res://scripts/inventory_assets.gd").new();source_dead_assets.configure(ProjectSettings.globalize_path("res://../runtime/assets/corpses/catalog.json"))
			var actor:=preload("res://combat/live_actor.gd").new();add_child(actor)
			actor.catalog_candidates=app.planet_assets.get("entity_catalogs",[])
			if not actor.configure(row,"spice_visual_only",source_assets,source_dead_assets,preload("res://scripts/planet_catalog.gd").context_path(app,"entities","res://../runtime/assets/combat_population/native_current/catalog.json")):actor.free();continue
			actor.visible=false;actor.collision_layer=0;actor.collision_mask=0
			if actor.collider!=null:actor.collider.disabled=true
			outline_sources[id]=actor;initial=true
		var actor:Node3D=outline_sources[id]
		var basis:=Basis(Vector3.UP,-float(row.heading_radians))
		if is_instance_valid(app.stage):basis=app.stage.global_basis*basis
		actor.apply_record(row,Transform3D(basis,app.services.world(row.position)),.2,initial)
		actor.collision_layer=0;actor.collision_mask=0
	return outline_sources.values()

func clear_gloves()->void:
	for entry:Dictionary in glove_overrides.values():
		if is_instance_valid(entry.glove):entry.glove.remove_target_override(entry.target)
		if is_instance_valid(entry.target):entry.target.free()
	glove_overrides.clear()
func update_gloves(policy:Dictionary)->void:
	if float(policy.tremor)<=0 or not is_instance_valid(app.xr_origin):clear_gloves();return
	var head:Node3D=app.xr_origin.get_node_or_null("XRCamera3D")
	if head==null:return
	for side:String in ["left","right"]:
		var hand:XRController3D=app.xr_origin.get_node_or_null(side.capitalize()+"Hand")
		var glove:Node3D=hand.get_node_or_null("Hand") if hand!=null else null
		if glove==null or not glove.has_method("add_target_override"):continue
		if not preload("res://scripts/tracked_hand_input.gd").controller_tracked(hand):
			if glove_overrides.has(side):glove.remove_target_override(glove_overrides[side].target);glove_overrides[side].target.free();glove_overrides.erase(side)
			continue
		if not glove_overrides.has(side):
			var target:=Node3D.new();add_child(target);target.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF
			glove_overrides[side]={"target":target,"glove":glove};glove.add_target_override(target,90)
		glove_overrides[side].target.global_transform=app.player.feedback.spice.hand_pose(hand.global_transform,head.global_transform,side)

func refresh_profiles(key:String)->void:
	profile_busy=true;var version:int=app.datapad_epoch
	await app.sync_inventory_equipment(true)
	if version!=app.datapad_epoch:return
	profile_key=key;profile_busy=false
func _process(delta:float)->void:
	if not is_instance_valid(app) or not is_instance_valid(app.player):return
	if epoch!=app.datapad_epoch:reset()
	if not app.world_ready:return
	var spice=app.player.feedback.spice;var policy:Dictionary=spice.policy()
	update_gloves(policy)
	var key:="%s:%s:%s"%[spice.revision,spice.effect.get("episode_id",""),spice.effect.get("phase","")]
	if spice.revision>=0 and key!=profile_key and not profile_busy and not app.inventory_request_pending:refresh_profiles(key)
	var actors:Array=get_tree().get_nodes_in_group("swg_radar_contacts").filter(func(node):return node.has_method("is_targetable"))
	var rows:Array=[]
	if policy.outlines and is_instance_valid(app.multiplayer_sync):rows=app.multiplayer_sync.state.native_world.get("spice_outlines",[])
	actors.append_array(sync_outline_sources(rows,actors))
	poll-=delta
	if poll<=0:
		poll=.1
		var ambient:Array=[]
		if is_instance_valid(app.ambient_npcs):
			for row:Dictionary in app.ambient_npcs.records.values():
				if is_instance_valid(row.get("avatar")):ambient.append(row.avatar)
		refresh(actors,ambient,app.player.global_position,policy)
	copy_transforms()
func _exit_tree()->void:reset()
