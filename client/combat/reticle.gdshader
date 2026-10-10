shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_disabled, shadows_disabled;
uniform sampler2D source_art : source_color, filter_linear_mipmap;
void fragment() {
    vec4 original = texture(source_art, UV);
    float hollow = smoothstep(0.20, 0.25, length(UV - vec2(0.5)));
    ALBEDO = vec3(0.32, 0.9, 0.96);
    ALPHA = original.a * max(original.r,max(original.g,original.b)) * hollow * 0.32;
}
