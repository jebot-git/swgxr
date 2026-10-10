shader_type spatial;
render_mode unshaded, cull_back;
global uniform vec4 swg_environment_tint;
global uniform vec4 swg_indoor_tint;
global uniform vec4 swg_portal_view_a;
global uniform vec4 swg_portal_view_b;
global uniform sampler2D swg_portal_data;
global uniform vec3 swg_space_basis_x;
global uniform vec3 swg_space_basis_y;
global uniform vec3 swg_space_basis_z;
uniform bool sector_lighting=false;
uniform vec3 sector_ambient=vec3(1.0);
uniform vec3 sector_light_colors[4];
uniform vec3 sector_light_directions[4];
varying vec3 sector_normal;
instance uniform float swg_indoor = 0.0;
instance uniform float swg_portal_building = 0.0;
varying vec3 world_vertex;
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform bool has_texture = false;
uniform bool use_vertex_color = false;
uniform bool alpha_cutout = false;
void vertex() {
 world_vertex = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
 sector_normal=NORMAL;
 if(sector_lighting)sector_normal=mat3(swg_space_basis_x,swg_space_basis_y,swg_space_basis_z)*MODEL_NORMAL_MATRIX*NORMAL;
}
bool exterior_visible(vec3 camera) {
 bool second = distance(camera, swg_portal_view_b.xyz) < distance(camera, swg_portal_view_a.xyz);
 vec4 view = second ? swg_portal_view_b : swg_portal_view_a;
 if (view.w < 0.5 || abs(swg_portal_building - view.w) > 0.5) return true;
 vec3 ray = world_vertex - camera;
 int base = second ? 32 : 0;
 for (int opening = 0; opening < 32; opening++) {
  int row = base + opening;
  float encoded_count = texelFetch(swg_portal_data, ivec2(0, row), 0).x;
  if (encoded_count < 0.0) return true;
  int count = int(encoded_count + 0.5);
  if (count < 3) break;
  vec4 plane = texelFetch(swg_portal_data, ivec2(1, row), 0);
  float denominator = dot(plane.xyz, ray);
  if (abs(denominator) < 0.000001) continue;
  float t = (plane.w - dot(plane.xyz, camera)) / denominator;
  if (t < 0.0 || t > 1.001) continue;
  vec3 hit = camera + t * ray;
  bool inside = true;
  for (int edge = 0; edge < 20; edge++) {
   if (edge >= count) break;
   vec3 a = texelFetch(swg_portal_data, ivec2(edge + 2, row), 0).xyz;
   vec3 b = texelFetch(swg_portal_data, ivec2((edge + 1) % count + 2, row), 0).xyz;
   // Godot Plane uses clockwise winding; test against that orientation.
   if (dot(cross(b - a, hit - a), plane.xyz) > 0.002) { inside = false; break; }
  }
  if (inside) return true;
 }
 return false;
}
void fragment() {
 if (swg_portal_building > 0.5 && !exterior_visible(INV_VIEW_MATRIX[3].xyz)) discard;
 vec4 surface = albedo_color;
 if (has_texture) surface *= texture(albedo_texture, UV);
 if (alpha_cutout && surface.a < 0.5) discard;
 vec3 baked = use_vertex_color ? COLOR.rgb : vec3(1.0);
 ALBEDO = surface.rgb * baked * mix(swg_environment_tint.rgb, swg_indoor_tint.rgb, clamp(swg_indoor, 0.0, 1.0));
 if(sector_lighting){
  vec3 illumination=sector_ambient;
  for(int i=0;i<4;i++)illumination+=sector_light_colors[i]*max(0.0,dot(normalize(sector_normal),sector_light_directions[i]));
  ALBEDO=surface.rgb*baked*clamp(illumination,vec3(0.0),vec3(1.5));
 }
}
