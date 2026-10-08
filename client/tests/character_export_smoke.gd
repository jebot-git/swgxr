extends SceneTree
const Exporter=preload("res://tools/character_exporter.gd")
const Baker=preload("res://tools/avatar_export_materials.gd")
var checks:=0
var errors:Array=[]
func check(value:bool,message:String)->void:
	checks+=1
	if not value:errors.append(message);push_error(message)
func texture(color:Color)->Texture2D:
	var img:=Image.create_empty(1,1,false,Image.FORMAT_RGBA8);img.fill(color);return ImageTexture.create_from_image(img)
func shader()->ShaderMaterial:
	var result:=ShaderMaterial.new();result.shader=load("res://shaders/avatar_material.gdshader")
	result.set_meta("swg_surface",{});result.set_meta("swg_directory","")
	for key in ["normal_mode","layer_count","color_mode"]:result.set_shader_parameter(key,0)
	result.set_shader_parameter("alpha_cutout",false)
	result.set_shader_parameter("main_texture",texture(Color(.4,.3,.2,.25)));result.set_shader_parameter("hue_texture",texture(Color(1,1,1,.15)))
	result.set_shader_parameter("main_color",Color(.8,.4,.2));result.set_shader_parameter("hue_color",Color(.2,.8,.6));return result
func near(a:Color,b:Color)->bool:return absf(a.r-b.r)<.01 and absf(a.g-b.g)<.01 and absf(a.b-b.b)<.01 and absf(a.a-b.a)<.01
func _initialize()->void:run.call_deferred()
func run()->void:
	var source:=shader();source.set_shader_parameter("color_mode",1)
	var baker:=Baker.new();var material:=baker.convert(source)
	var main:Color=source.get_shader_parameter("main_texture").get_image().get_pixel(0,0).srgb_to_linear()
	var tint:=Color(.8,.4,.2).srgb_to_linear().lerp(Color(.2,.8,.6).srgb_to_linear(),main.a)
	var expected:=Color(main.r*tint.r,main.g*tint.g,main.b*tint.b,main.a).linear_to_srgb()
	check(near(material.albedo_texture.get_image().get_pixel(0,0),expected),"Dual dye preserves alpha-mask palette mix in linear light")
	source=shader();source.set_shader_parameter("color_mode",2);source.set_shader_parameter("normal_mode",2);source.set_shader_parameter("normal_texture",texture(Color(.1,.7,.2,.8)));source.set_shader_parameter("alpha_cutout",true)
	material=Baker.new().convert(source)
	check(material.transparency==BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR and is_equal_approx(material.alpha_scissor_threshold,.5),"Original alpha cutout threshold retained")
	var normal:=material.normal_texture.get_image().get_pixel(0,0)
	check(absf(normal.r-.8)<.01 and absf(normal.g-.7)<.01 and absf(normal.b-(sqrt(.48)+1)*.5)<.01,"CNRM alpha/green channels decode to tangent-space XYZ")
	check(absf(material.albedo_texture.get_image().get_pixel(0,0).a-.4)<.01,"Dual-alpha source masks combine into preserved opacity")
	source=shader();source.set_shader_parameter("layer_count",2)
	for index in range(2):
		var prefix:="layer_%d_"%index;source.set_shader_parameter(prefix+"rect",Vector4(0,0,1,1));source.set_shader_parameter(prefix+"uv",Vector4(0,0,1,1));source.set_shader_parameter(prefix+"color",Color.WHITE);source.set_shader_parameter(prefix+"copy",index==0)
	source.set_shader_parameter("layer_0_texture",texture(Color(.8,.2,.1,.5)));source.set_shader_parameter("layer_1_texture",texture(Color(.1,.2,.8,.25)))
	material=Baker.new().convert(source)
	var first:Color=source.get_shader_parameter("layer_0_texture").get_image().get_pixel(0,0).srgb_to_linear();var last:Color=source.get_shader_parameter("layer_1_texture").get_image().get_pixel(0,0).srgb_to_linear()
	expected=first.lerp(last,last.a);expected.a=last.a+first.a*(1-last.a)
	check(near(material.albedo_texture.get_image().get_pixel(0,0),expected.linear_to_srgb()),"Facial copy and alpha layers bake without losing dye or opacity")
	var snapshot:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/evidence/ranged-final-character.json"))
	var exporter:=Exporter.new();root.add_child(exporter)
	var destination:=ProjectSettings.globalize_path("res://../runtime/evidence/character-export-smoke.glb")
	var report:Dictionary=exporter.export_character(snapshot,destination)
	check(report.ok,"Actual native snapshot exports completely: "+str(report.errors))
	check(report.equipment.size()==6 and report.intrinsic_nonvisual_equipment.size()==1,"Current equipment retained with explicit nonvisual unarmed exception")
	check(report.materials.any(func(row):return row.layers==5),"Actual source facial layers included in material evidence")
	check(not report.validated_assets.is_empty(),"Converted original models and textures recorded with SHA256 provenance")
	var bone_map:Dictionary={}
	for bone:Dictionary in report.bones:bone_map[bone.name]=bone
	for side in ["l","r"]:
		var shoulder:Array=bone_map[side+"arm"].global_rest.translation;var wrist:Array=bone_map[side+"wrist"].global_rest.translation
		check(absf(shoulder[1]-wrist[1])<.0001 and absf(shoulder[2]-wrist[2])<.0001,"Rebound "+side+" arm is horizontal in T-pose")
	var document:=GLTFDocument.new();var state:=GLTFState.new();var err:=document.append_from_file(destination,state)
	check(err==OK,"Exported embedded GLB reimports into Godot")
	var restored:=document.generate_scene(state);root.add_child(restored)
	var meshes:=restored.find_children("*","MeshInstance3D",true,false)
	check(meshes.size()==int(report.meshes) and meshes.all(func(mesh):return mesh.skin!=null),"All exported apparel and rigid attachments roundtrip as skinned meshes")
	check(restored.find_children("*","AnimationPlayer",true,false).is_empty(),"Exported avatar contains no runtime animations")
	restored.free();exporter.free()
	exporter=Exporter.new();root.add_child(exporter)
	var customized:=snapshot.duplicate(true)
	var catalog:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/assets/characters/catalog.json"))
	customized.character.appearance.hair={"template":catalog.races.human_male.hair[0].template,"customization":{"/private/index_color_0":50}}
	customized.character.appearance.customization={"/private/blend_fat":180,"/shared_owner/index_color_skin":42}
	var customized_report:Dictionary=exporter.export_character(customized,destination+".customized.glb")
	check(customized_report.ok and int(customized_report.get("morph_applications",0))>0,"Current body/face morph customization bakes into the exported rest shape")
	check(int(customized_report.get("meshes",0))>int(report.meshes),"Requested original hairstyle is retained alongside current equipment")
	var base_face:Array=report.materials.filter(func(row):return row.layers==5)
	var custom_face:Array=customized_report.get("materials",[]).filter(func(row):return row.layers==5)
	check(not custom_face.is_empty() and custom_face[0].baked_rgba_sha256!=base_face[0].baked_rgba_sha256,"Native palette customization changes the baked facial appearance")
	exporter.free()
	baker=Baker.new();source=shader();source.set_meta("swg_surface",{"texture":"/missing-original-texture.png"})
	check(baker.convert(source)==null and not baker.failures.is_empty(),"Missing source texture is rejected rather than exported as neutral white")
	exporter=Exporter.new();root.add_child(exporter)
	var broken:=snapshot.duplicate(true);broken.character.equipment.append({"id":"missing","template":"object/tangible/wearables/not_in_source.iff"});broken.character.appearance.equipment=broken.character.equipment
	check(not exporter.export_character(broken,destination+".missing.glb").ok,"Missing equipped geometry refuses export instead of removing clothing")
	exporter.free();exporter=Exporter.new();root.add_child(exporter)
	broken=snapshot.duplicate(true);broken.character.appearance.hair={"template":"object/tangible/hair/missing.iff","customization":{}}
	check(not exporter.export_character(broken,destination+".hair.glb").ok,"Missing hairstyle refuses export instead of silent bald fallback")
	exporter.free()
	print(JSON.stringify({"passed":errors.is_empty(),"checks":checks,"errors":errors,"renderer":"headless dummy","native_snapshot":true,"headset_tested":false}));quit(0 if errors.is_empty() else 1)
