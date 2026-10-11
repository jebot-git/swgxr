extends Node3D
const Targeting=preload("res://space/targeting.gd")
var bracket:MeshInstance3D
var reticle:MeshInstance3D
var lead:MeshInstance3D
var status:Label3D
var identity:=""
var smoothed_offset:=Vector3.ZERO
func _ready()->void:
	bracket=marker([Vector2(-1,-.55),Vector2(-1,-1),Vector2(-1,-1),Vector2(-.55,-1),Vector2(1,-.55),Vector2(1,-1),Vector2(1,-1),Vector2(.55,-1),Vector2(-1,.55),Vector2(-1,1),Vector2(-1,1),Vector2(-.55,1),Vector2(1,.55),Vector2(1,1),Vector2(1,1),Vector2(.55,1)],Color("ffe399"),.06)
	reticle=marker([Vector2(-1,0),Vector2(-.3,0),Vector2(.3,0),Vector2(1,0),Vector2(0,-1),Vector2(0,-.3),Vector2(0,.3),Vector2(0,1)],Color("6ee7dc"),.018)
	lead=marker([Vector2(0,-1),Vector2(1,0),Vector2(1,0),Vector2(0,1),Vector2(0,1),Vector2(-1,0),Vector2(-1,0),Vector2(0,-1)],Color("6ee7dc"),.014)
	status=Label3D.new();status.font=preload("res://resources/fonts/Jupiteroid-Regular.ttf");status.font_size=22;status.pixel_size=.00065;status.no_depth_test=true;add_child(status)
	hide()
func marker(points:Array,color:Color,size:float)->MeshInstance3D:
	var mesh:=ImmediateMesh.new();mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for point:Vector2 in points:mesh.surface_add_vertex(Vector3(point.x*size,point.y*size,0))
	mesh.surface_end()
	var node:=MeshInstance3D.new();node.mesh=mesh
	var material:=StandardMaterial3D.new();material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;material.no_depth_test=true;material.albedo_color=color
	node.material_override=material;node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;add_child(node);return node
func project(node:Node3D,point:Vector3,head:Transform3D)->void:
	var ray:=point-head.origin
	node.visible=ray.dot(-head.basis.z)>0
	if not node.visible:return
	node.global_transform=Transform3D(head.basis,head.origin+ray.normalized()*2.0)
func world_point(scene:Node3D,point:Vector3)->Vector3:return scene.to_global(scene.visual_ship_pose.affine_inverse()*point)
func positions(scene:Node3D,rows:Array)->Dictionary:
	var result:Dictionary={}
	for row:Dictionary in rows:
		var id:=str(row.id);var point:=Targeting.vector(row.position)
		if scene.nearby_poses.has(id):point=scene.nearby_poses[id].origin
		result[id]=world_point(scene,point)
	return result
func update_view(scene:Node3D,ship:Dictionary,head:Transform3D,delta:float)->void:
	show();bracket.hide();lead.hide()
	var data:Dictionary=ship.get("targeting",{});var target:Dictionary=data.get("target",{})
	var weapon:Dictionary={}
	for row:Dictionary in data.get("weapons",[]):
		if row.get("primary",false) and row.get("available",false):weapon=row;break
	var distance:=float(weapon.get("range",500))
	# This point follows the ship's firing axis, independent of head orientation.
	project(reticle,world_point(scene,scene.visual_ship_pose.origin-scene.visual_ship_pose.basis.z*distance),head)
	status.global_transform=head*Transform3D(Basis.IDENTITY,Vector3(-.27,-.27,-1.25))
	if target.is_empty():
		status.text="Updating target…" if data.get("busy",false) else "A/X · Select looked-at ship\nShip commands · Targeting"
		identity="";return
	var key:=str(target.id)+":"+str(target.get("component_slot",-1))
	var center:=Targeting.vector(target.position);var aim:=Targeting.vector(target.get("aim_position",target.position))
	if scene.nearby_poses.has(str(target.id)):aim+=scene.nearby_poses[str(target.id)].origin-center
	project(bracket,world_point(scene,aim),head)
	var component_name:="Hull"
	for component:Dictionary in target.get("components",[]):
		if int(component.slot)==int(target.get("component_slot",-1)):component_name=str(component.name).replace("_"," ").capitalize()
	status.text="%s · %.0f m\n%s"%[str(target.get("name","Target")),float(target.get("distance_m",0)),component_name]
	if not bracket.visible:status.text+=" · Outside view"
	var solution:=Targeting.intercept(aim-scene.visual_ship_pose.origin,Targeting.vector(target.get("velocity",[0,0,0])),float(weapon.get("speed",0)),distance/maxf(1,float(weapon.get("speed",0))))
	if key!=identity:smoothed_offset=Vector3.ZERO;identity=key
	if not solution.is_empty():
		smoothed_offset=smoothed_offset.lerp(solution.offset,1.0-exp(-delta/.10))
		project(lead,world_point(scene,aim+smoothed_offset),head)
	elif not weapon.is_empty():status.text+="\nOutside gun intercept range"
	if int(data.get("missile_slot",-1))>=0:
		var duration:=0.0
		for row:Dictionary in data.get("weapons",[]):
			if int(row.slot)==int(data.missile_slot):duration=float(row.get("acquisition_seconds",0))
		status.text+="\n"+("MISSILE LOCK" if data.get("lock_acquired",false) else str(data.get("lock_reason","")) if not str(data.get("lock_reason","")).is_empty() else "Acquiring · %d%%"%int(100*clampf(float(data.get("lock_seconds",0))/maxf(.01,duration),0,1)))
