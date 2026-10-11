shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D source_texture : source_color, filter_linear_mipmap;
void fragment() {
	vec4 source = texture(source_texture, UV);
	// Preserve the original coin's engraved texture detail while displaying a
	// gold UI tint instead of its authored faction glow colour.
	float relief = clamp(max(source.r, max(source.g, source.b)) * 2.0, 0.0, 1.0);
	ALBEDO = mix(vec3(0.24, 0.075, 0.006), vec3(1.0, 0.72, 0.10), relief);
	EMISSION = ALBEDO * 0.35;
}
