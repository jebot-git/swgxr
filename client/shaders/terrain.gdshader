shader_type spatial;
render_mode unshaded, cull_back;
global uniform vec4 swg_environment_tint;
global uniform float swg_daylight;
varying float baked_light;
uniform sampler2DArray terrain_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray terrain_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec2 family_info[64];
uniform sampler2D interior_mask : filter_nearest, repeat_disable;
uniform vec4 interior_rect;
uniform bool mask_enabled = false;
global uniform vec4 swg_portal_view_a;
global uniform vec4 swg_portal_view_b;
uniform float volume_mask_building = 0.0;
uniform sampler2D interior_volume_mask : filter_nearest, repeat_disable;
uniform vec4 interior_volume_rect;
uniform bool volume_mask_enabled = false;
uniform float volume_mask_building2 = 0.0;
uniform sampler2D interior_volume_mask2 : filter_nearest, repeat_disable;
uniform bool volume_mask_enabled2 = false;
varying float terrain_world_height;
varying flat vec4 families;
varying vec4 weights;
varying vec3 terrain_tint;
void vertex() {
 terrain_world_height = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
 families = CUSTOM0;
 weights = COLOR;
 terrain_tint = CUSTOM1.rgb;
 baked_light = CUSTOM1.a;
}
void fragment() {
 vec2 volume_uv = (UV - interior_volume_rect.xy) / max(interior_volume_rect.zw, vec2(1.0));
 if (all(greaterThanEqual(volume_uv, vec2(0.0))) && all(lessThanEqual(volume_uv, vec2(1.0)))) {
  vec4 viewer = distance(CAMERA_POSITION_WORLD, swg_portal_view_a.xyz) <= distance(CAMERA_POSITION_WORLD, swg_portal_view_b.xyz) ? swg_portal_view_a : swg_portal_view_b;
  if (viewer.w > 0.0) {
   vec2 limits = vec2(1e20, -1e20);
   if (volume_mask_enabled && abs(viewer.w-volume_mask_building) < 0.5) limits = texture(interior_volume_mask, volume_uv).rg;
   else if (volume_mask_enabled2 && abs(viewer.w-volume_mask_building2) < 0.5) limits = texture(interior_volume_mask2, volume_uv).rg;
   if (terrain_world_height >= limits.x && terrain_world_height <= limits.y) discard;
  }
 }
 vec2 mask_uv = (UV - interior_rect.xy) / max(interior_rect.zw, vec2(1.0));
 if (mask_enabled && all(greaterThanEqual(mask_uv, vec2(0.0))) && all(lessThanEqual(mask_uv, vec2(1.0))) && texture(interior_mask, mask_uv).r > 0.5) { discard; }
 vec4 w = max(weights, vec4(0.0));
 w /= max(dot(w, vec4(1.0)), 0.0001);
 vec3 albedo = vec3(0.0);
 vec3 normal = vec3(0.0);
 for (int i = 0; i < 4; i++) {
  vec2 info = family_info[clamp(int(families[i]+0.5), 0, 63)];
  vec3 coord = vec3(UV / max(info.y, 0.1), info.x);
  albedo += texture(terrain_albedo, coord).rgb * w[i];
  normal += texture(terrain_normal, coord).rgb * w[i];
 }
 ALBEDO = albedo * terrain_tint * swg_environment_tint.rgb * mix(0.7, baked_light, swg_daylight);
 NORMAL_MAP = normal;
 ROUGHNESS = 0.95;
}
