shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled;
instance uniform float pulse_phase = 0.0;
uniform float pulse_radius = 12.0;
void vertex() {
	float echo = UV.y;
	float width = mix(0.045, 0.024, echo);
	float center = max(0.0, pulse_phase - echo * 0.10);
	float radius = max(0.0, center + (UV.x * 2.0 - 1.0) * width);
	VERTEX.xz *= radius * pulse_radius;
}
void fragment() {
	float ring = 1.0 - smoothstep(0.4, 1.0, abs(UV.x * 2.0 - 1.0));
	float fade = smoothstep(0.0, 0.09, pulse_phase) * (1.0 - smoothstep(0.70, 1.0, pulse_phase));
	ALBEDO = vec3(0.10, 0.73, 1.0);
	ALPHA = ring * mix(1.0, 0.28, UV.y) * fade * 0.80;
}
