shader_type spatial;
render_mode unshaded, blend_mix, depth_test_disabled, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;
uniform float damage_amount = 0.0;
uniform float heal_amount = 0.0;
void vertex() {
	POSITION = vec4(VERTEX.xy * 2.0, 0.0, 1.0);
}
void fragment() {
	// Clear central view, soft static peripheral tint. No shake, flash or blur.
	float edge = smoothstep(0.58, 1.0, length((UV - 0.5) * 2.0));
	float damage = damage_amount * 0.085;
	float heal = heal_amount * 0.055;
	ALBEDO = (vec3(0.62, 0.14, 0.10) * damage + vec3(0.12, 0.68, 0.52) * heal) / max(damage + heal, 0.0001);
	ALPHA = edge * min(0.10, damage + heal);
}
