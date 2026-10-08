extends RefCounted
## CPU equivalent of avatar_material.gdshader, excluding runtime environment light.
var failures:Array=[]
var evidence:Array=[]
var cache:Dictionary={}
var images:Dictionary={}
var provenance:Dictionary={}
func sha256(data:PackedByteArray)->String:
	var context:=HashingContext.new();context.start(HashingContext.HASH_SHA256);context.update(data);return context.finish().hex_encode()
func validate_paths(value:Variant,directory:String,key:String="")->void:
	if value is Dictionary:
		for field in value:validate_paths(value[field],directory,str(field))
	elif value is Array:
		for entry in value:validate_paths(entry,directory,key)
	elif value is String and (key=="texture" or key=="textures" or str(value).begins_with("textures/")) and not str(value).is_empty():
		var path:String=value if value.is_absolute_path() else directory.path_join(value)
		if not FileAccess.file_exists(path):failures.append("Missing original material texture: "+path)
		else:provenance[path]=FileAccess.get_sha256(path)
func image(texture:Texture2D,linear:bool)->Image:
	if texture==null:return null
	var key:=str(texture.get_instance_id())+str(linear)
	if images.has(key):return images[key]
	var original:=texture.get_image()
	var result:Image=original.duplicate() if original!=null else null
	if result==null or result.is_empty():failures.append("Material texture has no readable image");return null
	if result.is_compressed():result.decompress()
	result.clear_mipmaps();result.convert(Image.FORMAT_RGBAF)
	if linear:
		for y in range(result.get_height()):
			for x in range(result.get_width()):result.set_pixel(x,y,result.get_pixel(x,y).srgb_to_linear())
	images[key]=result;return result
func sample(img:Image,uv:Vector2,repeat_texture:bool=true)->Color:
	if img==null:return Color.WHITE
	var px:=uv.x*img.get_width()-.5;var py:=uv.y*img.get_height()-.5
	var x:=floori(px);var y:=floori(py);var sx:=px-x;var sy:=py-y
	var x0:=posmod(x,img.get_width()) if repeat_texture else clampi(x,0,img.get_width()-1)
	var x1:=posmod(x+1,img.get_width()) if repeat_texture else clampi(x+1,0,img.get_width()-1)
	var y0:=posmod(y,img.get_height()) if repeat_texture else clampi(y,0,img.get_height()-1)
	var y1:=posmod(y+1,img.get_height()) if repeat_texture else clampi(y+1,0,img.get_height()-1)
	return img.get_pixel(x0,y0).lerp(img.get_pixel(x1,y0),sx).lerp(img.get_pixel(x0,y1).lerp(img.get_pixel(x1,y1),sx),sy)
func convert(source:Material)->StandardMaterial3D:
	if source is StandardMaterial3D:return source.duplicate(true)
	if not source is ShaderMaterial:failures.append("Unsupported material type");return null
	if cache.has(source.get_instance_id()):return cache[source.get_instance_id()]
	var shader:ShaderMaterial=source
	var kind:=shader.shader.resource_path
	var material:=StandardMaterial3D.new();material.roughness=.85;material.metallic=0;material.vertex_color_use_as_albedo=true
	material.cull_mode=BaseMaterial3D.CULL_BACK
	if kind=="res://shaders/static_baked.gdshader":
		material.albedo_color=shader.get_shader_parameter("albedo_color")
		if shader.get_shader_parameter("has_texture"):material.albedo_texture=shader.get_shader_parameter("albedo_texture")
		material.vertex_color_use_as_albedo=bool(shader.get_shader_parameter("use_vertex_color"))
	elif kind=="res://shaders/avatar_material.gdshader":
		var definition:Dictionary=shader.get_meta("swg_surface",{})
		validate_paths(definition,str(shader.get_meta("swg_directory","")))
		if not failures.is_empty():return null
		var layers:Array=[]
		var count:=int(shader.get_shader_parameter("layer_count"))
		if definition.get("texture_renderer_definition",{}).get("layers",[]).size()>6:failures.append("Avatar material exceeds supported six source layers");return null
		var main:=image(shader.get_shader_parameter("main_texture"),true)
		var hue:=image(shader.get_shader_parameter("hue_texture"),false)
		if main==null:return null
		var width:=main.get_width();var height:=main.get_height()
		if hue!=null:width=maxi(width,hue.get_width());height=maxi(height,hue.get_height())
		for index in range(count):
			var prefix:="layer_%d_"%index
			var rect:Vector4=shader.get_shader_parameter(prefix+"rect")
			var uv:Vector4=shader.get_shader_parameter(prefix+"uv")
			var layer_image:=image(shader.get_shader_parameter(prefix+"texture"),true)
			if rect.z<=0 or rect.w<=0 or layer_image==null:failures.append("Invalid source layer bounds or texture");return null
			width=maxi(width,ceili(layer_image.get_width()*absf(uv.z)/rect.z-.001));height=maxi(height,ceili(layer_image.get_height()*absf(uv.w)/rect.w-.001))
			layers.append({"image":layer_image,"rect":rect,"uv":uv,"color":(shader.get_shader_parameter(prefix+"color") as Color).srgb_to_linear(),"copy":shader.get_shader_parameter(prefix+"copy")})
		if width>4096 or height>4096:failures.append("Source layer density requires texture larger than 4096; refusing a lossy bake");return null
		var baked:=Image.create_empty(width,height,false,Image.FORMAT_RGBA8)
		var a:Color=(shader.get_shader_parameter("main_color") as Color).srgb_to_linear()
		var b:Color=(shader.get_shader_parameter("hue_color") as Color).srgb_to_linear()
		var mode:=int(shader.get_shader_parameter("color_mode"))
		for y in range(height):
			for x in range(width):
				var uv:=Vector2((x+.5)/width,(y+.5)/height)
				var base:=sample(main,uv);var tint:=a;var opacity:=base.a
				if mode==1:tint=a.lerp(b,base.a)
				elif mode==2:
					var mask:=sample(hue,uv).a;tint=b.lerp(a,clampf(base.a-mask,0,1));opacity=clampf(base.a+mask,0,1)
				var result:=Color(base.r*tint.r,base.g*tint.g,base.b*tint.b,opacity)
				for layer:Dictionary in layers:
					var rect:Vector4=layer.rect;var local:=(uv-Vector2(rect.x,rect.y))/Vector2(rect.z,rect.w)
					if local.x<0 or local.y<0 or local.x>1 or local.y>1:continue
					var bounds:Vector4=layer.uv
					var pixel:Color=sample(layer.image,Vector2(bounds.x,bounds.y)+local*Vector2(bounds.z,bounds.w),false)*Color(layer.color)
					if layer.copy:result=pixel
					else:
						var alpha:=pixel.a+result.a*(1-pixel.a);result=result.lerp(pixel,pixel.a);result.a=alpha
				baked.set_pixel(x,y,result.linear_to_srgb())
		material.albedo_texture=ImageTexture.create_from_image(baked)
		var normal_mode:=int(shader.get_shader_parameter("normal_mode"))
		if normal_mode!=0:
			var normal:=image(shader.get_shader_parameter("normal_texture"),false)
			if normal==null:return null
			var decoded:=normal.duplicate()
			if normal_mode==2:
				for y in range(decoded.get_height()):
					for x in range(decoded.get_width()):
						var encoded:=normal.get_pixel(x,y);var nx:=encoded.a*2-1;var ny:=encoded.g*2-1
						decoded.set_pixel(x,y,Color(encoded.a,encoded.g,(sqrt(maxf(0,1-nx*nx-ny*ny))+1)*.5,1))
			decoded.convert(Image.FORMAT_RGBA8);material.normal_enabled=true;material.normal_texture=ImageTexture.create_from_image(decoded)
		evidence.append({"shader":definition.get("shader",""),"width":width,"height":height,"layers":count,"color_mode":mode,"normal_mode":normal_mode,"baked_rgba_sha256":sha256(baked.get_data())})
	else:failures.append("Unsupported shader: "+kind);return null
	if shader.get_shader_parameter("alpha_cutout"):
		material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR;material.alpha_scissor_threshold=.5
	cache[source.get_instance_id()]=material
	return material
