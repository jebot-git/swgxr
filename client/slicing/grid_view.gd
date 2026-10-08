extends Node3D
## Small open lattice and batched pipes, independent of player/head transforms.
const COLORS=[Color("5bdcff"),Color("ffb74d"),Color("dd7aff"),Color("80f58d")]
var board:RefCounted
var lattice:MultiMeshInstance3D
var endpoints:MultiMeshInstance3D
var lines:Array=[]
var labels:Node3D
var caption:Label3D
var cursor:MeshInstance3D
var last_revision:=-1
func material(color:Color)->StandardMaterial3D:
	var value:=StandardMaterial3D.new();value.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;value.albedo_color=color;return value
func _ready()->void:
	lattice=batch(Color("245469"));endpoints=batch(Color.WHITE,true)
	for color in COLORS:lines.append(batch(color))
	labels=Node3D.new();add_child(labels)
	caption=Label3D.new();caption.font=preload("res://resources/fonts/Jupiteroid-Regular.ttf");caption.font_size=28;caption.pixel_size=.001;caption.modulate=Color("d2f6ff");caption.outline_size=3;caption.billboard=BaseMaterial3D.BILLBOARD_ENABLED;add_child(caption)
	cursor=MeshInstance3D.new();var sphere:=SphereMesh.new();sphere.radius=.006;sphere.height=.012;cursor.mesh=sphere;cursor.material_override=material(Color.WHITE);cursor.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;add_child(cursor);cursor.hide()
func batch(color:Color,sphere:=false)->MultiMeshInstance3D:
	var node:=MultiMeshInstance3D.new();add_child(node);node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mesh:Mesh=SphereMesh.new() if sphere else CylinderMesh.new()
	if sphere:mesh.radius=1;mesh.height=2;mesh.radial_segments=12;mesh.rings=6
	else:mesh.top_radius=1;mesh.bottom_radius=1;mesh.height=1;mesh.radial_segments=8
	mesh.material=material(color)
	mesh.material.vertex_color_use_as_albedo=sphere
	node.multimesh=MultiMesh.new();node.multimesh.transform_format=MultiMesh.TRANSFORM_3D;node.multimesh.use_colors=sphere;node.multimesh.mesh=mesh
	return node
func segment(from:Vector3,to:Vector3,radius:float)->Transform3D:
	var direction:=to-from
	return Transform3D(Basis(Quaternion(Vector3.UP,direction.normalized()))*Basis.from_scale(Vector3(radius,direction.length(),radius)),(from+to)*.5)
func fill(node:MultiMeshInstance3D,segments:Array,radius:float)->void:
	node.multimesh.instance_count=segments.size()
	for index in range(segments.size()):node.multimesh.set_instance_transform(index,segment(segments[index][0],segments[index][1],radius))
func configure(value:RefCounted)->void:
	board=value;last_revision=-1
	var half:float=board.size*board.cell_size*.5
	var segments:Array=[]
	for axis in range(3):
		for a in range(board.size+1):
			for b in range(board.size+1):
				var from:=Vector3.ZERO;var to:=Vector3.ZERO
				from[axis]=-half;to[axis]=half
				from[(axis+1)%3]=a*board.cell_size-half;to[(axis+1)%3]=from[(axis+1)%3]
				from[(axis+2)%3]=b*board.cell_size-half;to[(axis+2)%3]=from[(axis+2)%3]
				segments.append([from,to])
	fill(lattice,segments,.001)
	endpoints.multimesh.instance_count=board.pairs.size()*2
	for child in labels.get_children():child.free()
	var index:=0
	for pair:Dictionary in board.pairs:
		for end in range(2):
			var point:Vector3=board.endpoint_position(pair.ends[end]);var color:Color=COLORS[int(pair.color)]
			endpoints.multimesh.set_instance_transform(index,Transform3D(Basis.IDENTITY.scaled(Vector3.ONE*.014),point));endpoints.multimesh.set_instance_color(index,color);index+=1
			var label:=Label3D.new();label.font=preload("res://resources/fonts/Jupiteroid-Regular.ttf");label.text=String.chr(65+int(pair.color))+str(end+1);label.font_size=24;label.pixel_size=.001;label.outline_size=4;label.modulate=color;label.billboard=BaseMaterial3D.BILLBOARD_ENABLED;label.position=point+Vector3(board.cell(pair.ends[end].face))*.025+Vector3.UP*.02;labels.add_child(label)
	caption.position=Vector3(0,half+.14,0);refresh()
func refresh()->void:
	if board==null or last_revision==board.revision:return
	last_revision=board.revision
	for color in range(4):
		var segments:Array=[]
		var path:Array=board.draft if board.active_color==color else board.wires.get(color,[])
		if not path.is_empty():
			var pair:Dictionary=board.pair_for(color)
			var first:int=0 if board.cell(path[0])==board.cell(pair.ends[0].cell) else 1
			var points:Array=[board.endpoint_position(pair.ends[first])]
			for value:Array in path:points.append(board.center(value))
			if board.wires.has(color):points.append(board.endpoint_position(pair.ends[1-first]))
			for index in range(1,points.size()):
				if Vector3(points[index]).distance_squared_to(points[index-1])>.000001:segments.append([points[index-1],points[index]])
		fill(lines[color],segments,.005)
func show_cursor(point:Vector3,tracked:bool,blocked:=false)->void:
	cursor.visible=tracked
	if tracked:cursor.position=point;cursor.material_override.albedo_color=Color("ff5d65") if blocked else Color.WHITE
func set_status(text:String)->void:caption.text=text
