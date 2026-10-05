shader_type spatial;
render_mode unshaded, cull_back, blend_mix, depth_draw_opaque;
uniform sampler2D source_texture : source_color, filter_linear_mipmap;
uniform bool has_texture = false;
uniform bool alpha_cutout = false;
void fragment() {
	vec4 source = has_texture ? texture(source_texture, UV) : vec4(1.0);
	if (alpha_cutout && source.a < 0.35) discard;
	float detail = dot(source.rgb, vec3(0.2126, 0.7152, 0.0722));
	float rim = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 3.0);
	ALBEDO = vec3(0.12, 0.72, 0.90) * (0.58 + 0.42 * detail) + vec3(0.18, 0.42, 0.45) * rim;
	ALPHA = 0.67;
}
