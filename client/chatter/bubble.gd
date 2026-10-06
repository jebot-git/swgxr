extends Node3D
## Shared low-poly panel, two depth-tested labels; never a viewport or input target.
const TAIL_TIP:=Vector3(-.48,-.45,0)
const FONT=preload("res://resources/fonts/Jupiteroid-Regular.ttf")
static var shared_mesh:ArrayMesh
var words:Label3D
var caption:Label3D
func _ready()->void:
	var plate:=MeshInstance3D.new();plate.mesh=mesh();plate.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;add_child(plate)
	words=label(36,.003);words.width=450;words.autowrap_mode=TextServer.AUTOWRAP_OFF;words.position=Vector3(0,.035,.012)
	caption=label(24,.003);caption.position=Vector3(0,-.24,.013);caption.modulate=Color("95ced7")
func label(size:int,pixel:float)->Label3D:
	var result:=Label3D.new();result.font=FONT;result.font_size=size;result.pixel_size=pixel;result.no_depth_test=false;result.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;result.shaded=false;result.outline_size=2;result.modulate=Color("e1ffff");add_child(result);return result
func present(event:Dictionary)->void:
	words.text=fit_text(str(event.get("text","")),36,3)
	var language:=str(event.get("language_name",event.get("language_key",""))).replace("_"," ").capitalize()
	caption.text=fit_text(language,24,1)
static func fit_text(value:String,font_size:int,max_lines:int)->String:
	var remaining:=value.strip_edges().replace("\r","").replace("\n"," ").replace("\t"," ").left(2048)
	var lines:PackedStringArray=[]
	for line in range(max_lines):
		if remaining.is_empty():break
		var count:=0
		while count<remaining.length() and FONT.get_string_size(remaining.left(count+1),HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x<=450:count+=1
		count=maxi(1,count)
		if count<remaining.length() and line<max_lines-1:
			var space:=remaining.left(count).rfind(" ")
			if space>0:count=space
		var text:=remaining.left(count).strip_edges();remaining=remaining.substr(count).strip_edges()
		if line==max_lines-1 and not remaining.is_empty():
			while not text.is_empty() and FONT.get_string_size(text+"…",HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x>450:text=text.left(-1)
			text+="…"
		lines.append(text)
	return "\n".join(lines)
func clear()->void:
	hide()
	if is_instance_valid(words):words.text="";caption.text=""
static func mesh()->ArrayMesh:
	if shared_mesh!=null:return shared_mesh
	# Rounded rectangle with a downward left tail, inspired by the supplied CC0 reference.
	var outline:PackedVector2Array=[]
	for corner in [Vector2(.70,.27),Vector2(-.70,.27),Vector2(-.70,-.27),Vector2(.70,-.27)]:
		var start:=0.0 if corner.x>0 and corner.y>0 else PI/2 if corner.y>0 else PI if corner.x<0 else 3*PI/2
		for i in range(5):outline.append(corner+Vector2(cos(start+i*PI/8),sin(start+i*PI/8))*.05)
	# The bottom segment runs left to right. Its extra vertices form the speech tail.
	outline.insert(15,Vector2(-.28,-.32));outline.insert(15,Vector2(-.48,-.45));outline.insert(15,Vector2(-.48,-.32))
	shared_mesh=ArrayMesh.new()
	var inner:PackedVector2Array=[]
	for point in outline:inner.append(point*.965)
	for border in [true,false]:
		var vertices:PackedVector3Array=[];var indices:PackedInt32Array=[]
		if border:
			for i in range(outline.size()):vertices.append(Vector3(outline[i].x,outline[i].y,0));vertices.append(Vector3(inner[i].x,inner[i].y,0))
			for i in range(outline.size()):
				var n:=(i+1)%outline.size();indices.append_array([i*2,n*2,i*2+1,n*2,n*2+1,i*2+1])
		else:
			for point in inner:vertices.append(Vector3(point.x,point.y,0))
			indices=Geometry2D.triangulate_polygon(inner)
		var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_INDEX]=indices
		shared_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		var material:=StandardMaterial3D.new();material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;material.cull_mode=BaseMaterial3D.CULL_DISABLED;material.albedo_color=Color("67c6d1") if border else Color("0a2634");shared_mesh.surface_set_material(shared_mesh.get_surface_count()-1,material)
	return shared_mesh
