extends RefCounted
## Original SWG palette, texture-selector and facial-layer evaluator.
## Imported definitions retain the source operation names and asset hashes.

static var textures: Dictionary = {}
static var shaders: Dictionary = {}
static var neutral: ImageTexture

static func value(values: Dictionary, descriptor: Dictionary) -> int:
	var path: String = descriptor.get("variable_path", descriptor.get("variable", ""))
	if values.has(path):
		return int(values[path])
	var short_name := path.get_file()
	for key in values:
		if str(key).get_file() == short_name:
			return int(values[key])
	return int(descriptor.get("default", 0))

static func texture(path: String, directory: String) -> Texture2D:
	if path.is_empty():
		if neutral == null:
			var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
			img.fill(Color.WHITE)
			neutral = ImageTexture.create_from_image(img)
		return neutral
	var full_path := path if path.is_absolute_path() else directory.path_join(path)
	if not textures.has(full_path):
		var img := Image.load_from_file(full_path)
		if img == null:
			return texture("", directory)
		img.generate_mipmaps()
		textures[full_path] = ImageTexture.create_from_image(img)
	return textures[full_path]

static func color(descriptor: Dictionary, values: Dictionary) -> Color:
	var colors: Array = descriptor.get("colors", [])
	if colors.is_empty():
		return Color.WHITE
	var rgba: Array = colors[clampi(value(values, descriptor), 0, colors.size() - 1)]
	return Color(float(rgba[0]), float(rgba[1]), float(rgba[2]), float(rgba[3]) if rgba.size() > 3 else 1.0)

static func selected_texture(descriptor: Dictionary, values: Dictionary, directory: String) -> Texture2D:
	var options: Array = descriptor.get("textures", [])
	if options.is_empty():
		return texture("", directory)
	return texture(str(options[clampi(value(values, descriptor), 0, options.size() - 1)]), directory)

static func create(surface: Dictionary, directory: String) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	if not shaders.has("avatar"):
		shaders.avatar = load("res://shaders/avatar_material.gdshader")
	material.shader = shaders.avatar
	material.set_meta("swg_surface", surface)
	material.set_meta("swg_directory", directory)
	apply(material, {})
	return material

static func apply(material: ShaderMaterial, values: Dictionary) -> void:
	var surface: Dictionary = material.get_meta("swg_surface", {})
	var directory: String = material.get_meta("swg_directory", "")
	var bindings: Dictionary = surface.get("texture_bindings", {}).duplicate()
	if not bindings.has("MAIN"):
		bindings.MAIN = surface.get("texture", "")
	var maps: Dictionary = {}
	for tag in bindings:
		maps[tag] = texture(str(bindings[tag]), directory)
	for selector in surface.get("texture_selectors", []):
		maps[selector.tag] = selected_texture(selector, values, directory)
	material.set_shader_parameter("main_texture", maps.get("MAIN", texture("", directory)))
	material.set_shader_parameter("hue_texture", maps.get("HUEB", texture("", directory)))
	material.set_shader_parameter("normal_texture", maps.get("CNRM", maps.get("NRML", texture("", directory))))
	material.set_shader_parameter("normal_mode", 2 if maps.has("CNRM") else 1 if maps.has("NRML") else 0)
	var palette_by_tag := {}
	for palette in surface.get("palettes", []):
		if not palette_by_tag.has(palette.tag):
			palette_by_tag[palette.tag] = palette
	material.set_shader_parameter("main_color", color(palette_by_tag.get("MAIN", {}), values))
	material.set_shader_parameter("hue_color", color(palette_by_tag.get("HUEB", {}), values))
	material.set_shader_parameter("color_mode", {"single":0, "dual":1, "dual_alpha":2}.get(surface.get("color_mode", "single"), 0))
	material.set_shader_parameter("alpha_cutout", surface.get("alpha", false))
	var layers: Array = surface.get("texture_renderer_definition", {}).get("layers", [])
	material.set_shader_parameter("layer_count", mini(layers.size(), 6))
	for i in range(6):
		var prefix := "layer_%d_" % i
		if i >= layers.size():
			material.set_shader_parameter(prefix + "texture", texture("", directory))
			continue
		var layer: Dictionary = layers[i]
		var rect: Array = layer.rect
		var uv: Array = layer.uv_rect
		material.set_shader_parameter(prefix + "rect", Vector4(rect[0], rect[1], rect[2], rect[3]))
		material.set_shader_parameter(prefix + "uv", Vector4(uv[0], uv[1], uv[2], uv[3]))
		material.set_shader_parameter(prefix + "copy", layer.mode == "copy")
		material.set_shader_parameter(prefix + "color", color(layer.get("palette", {}), values))
		var layer_texture := selected_texture(layer.selector, values, directory) if layer.has("selector") else texture(str(layer.get("texture", "")), directory)
		material.set_shader_parameter(prefix + "texture", layer_texture)

static func supported_variables(surface: Dictionary) -> Array:
	var result: Array = []
	for palette in surface.get("palettes", []):
		var variable: String = str(palette.get("variable_path", palette.get("variable", ""))).get_file()
		if not variable in result:
			result.append(variable)
	for selector in surface.get("texture_selectors", []):
		var variable: String = str(selector.get("variable_path", selector.get("variable", ""))).get_file()
		if not variable in result:
			result.append(variable)
	for layer in surface.get("texture_renderer_definition", {}).get("layers", []):
		for key in ["selector", "palette"]:
			if layer.has(key):
				var definition: Dictionary = layer[key]
				var variable: String = str(definition.get("variable_path", definition.get("variable", ""))).get_file()
				if not variable in result:
					result.append(variable)
	return result
