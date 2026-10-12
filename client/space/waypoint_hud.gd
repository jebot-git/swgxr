extends Node3D
## Original SwgCuiAllTargetsSpace: active waypoints, ship distance, >50m,
## far-plane-independent projection. Edge arrows are an XR guidance adaptation.
const Targeting=preload("res://space/targeting.gd")
const DRAW_DISTANCE:=2.0
const EDGE:=Vector2(.9,.62)
var markers:Dictionary={}
static func placement(local:Vector3)->Dictionary:
	var forward:=-local.z
	var p:=Vector2(local.x,local.y)*DRAW_DISTANCE/maxf(.001,forward)
	var outside:=forward<=0 or absf(p.x)>EDGE.x or absf(p.y)>EDGE.y
	if outside:
		p=Vector2(local.x,local.y)
		if p.length_squared()<.0001:p=Vector2(0,-1)
		p/=maxf(absf(p.x)/EDGE.x,absf(p.y)/EDGE.y)
	return {"position":Vector3(p.x,p.y,-DRAW_DISTANCE),"outside":outside,"angle":p.angle()}
func clear()->void:
	for node:Node in markers.values():node.queue_free()
	markers.clear();hide()
func make_marker()->Node3D:
	var node:=Node3D.new();add_child(node)
	var shape:=MeshInstance3D.new();shape.name="Shape";node.add_child(shape)
	var mat:=StandardMaterial3D.new();mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;mat.no_depth_test=true;mat.albedo_color=Color("73c6ff")
	shape.material_override=mat;shape.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var label:=Label3D.new();label.name="Label";label.font=preload("res://resources/fonts/Jupiteroid-Regular.ttf");label.font_size=32;label.pixel_size=.0014;label.no_depth_test=true;label.position.y=-.09;label.modulate=Color("a8ddff");node.add_child(label)
	return node
func shape_mesh(outside:bool)->ImmediateMesh:
	var mesh:=ImmediateMesh.new();mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var points:Array=[Vector2(-1,-1),Vector2(1,0),Vector2(1,0),Vector2(-1,1)] if outside else [Vector2(0,1),Vector2(1,0),Vector2(1,0),Vector2(0,-1),Vector2(0,-1),Vector2(-1,0),Vector2(-1,0),Vector2(0,1)]
	for p:Vector2 in points:mesh.surface_add_vertex(Vector3(p.x,p.y,0)*.025)
	mesh.surface_end();return mesh
func update_view(scene:Node3D,rows:Array,head:Transform3D)->void:
	show();var current:Dictionary={}
	for row:Dictionary in rows:
		var id:=str(row.get("id",""));var source:Variant=row.get("position")
		if id.is_empty() or not source is Array or source.size()!=3:continue
		var point:=Targeting.vector(source)
		if not point.is_finite():continue
		var distance:float=scene.visual_ship_pose.origin.distance_to(point)
		if distance<=50:continue
		current[id]=true
		if not markers.has(id):markers[id]=make_marker()
		var node:Node3D=markers[id]
		var world:Vector3=scene.to_global(scene.visual_ship_pose.affine_inverse()*point)
		var draw:=placement(head.affine_inverse()*world)
		node.global_transform=head*Transform3D(Basis.IDENTITY,draw.position)
		var shape:MeshInstance3D=node.get_node("Shape")
		if not node.has_meta("outside") or node.get_meta("outside")!=draw.outside:
			shape.mesh=shape_mesh(draw.outside);node.set_meta("outside",draw.outside)
		shape.rotation.z=float(draw.angle) if draw.outside else 0.0
		var label:Label3D=node.get_node("Label")
		var colors:=[Color.WHITE,Color("73c6ff"),Color("72f29c"),Color("ff9d52"),Color("ffeb71"),Color("cb92ff"),Color.WHITE,Color("73c6ff")]
		var color:Color=colors[clampi(int(row.get("color",1)),0,7)]
		shape.material_override.albedo_color=color;label.modulate=color
		label.text="%s\n%d m"%[str(row.get("name","Waypoint")),int(distance)]
		label.position.x=-.12*signf(float(draw.position.x)) if draw.outside else 0.0
	for id in markers.keys():
		if not current.has(id):markers[id].queue_free();markers.erase(id)
