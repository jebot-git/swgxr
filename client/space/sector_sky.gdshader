shader_type sky;
// Original space terrain textures and planet spheres rendered behind geometry.
// The source background parallax is 100 metres across the 16384 metre sector.
uniform mat3 ship_rotation = mat3(1.0);
uniform vec3 ship_position = vec3(0.0);
uniform vec3 view_origin = vec3(0.0);
uniform float sector_width = 16384.0;
uniform samplerCube sky_cube : source_color, filter_linear_mipmap;
uniform samplerCube starfield : source_color, filter_linear_mipmap;
uniform sampler2DArray celestial_textures : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 celestial_points[40];
uniform int celestial_count = 0;
uniform sampler2DArray halo_textures : source_color, filter_linear_mipmap, repeat_disable;
uniform vec2 halo_settings[8];
uniform int planet_count = 0;
uniform vec4 planets[8];
uniform mat3 planet_rotations[8];
uniform vec4 surface_settings[8];
uniform vec4 cloud_settings[8]; // radius, source UV scale, rotation radians/sec
uniform vec3 ambient = vec3(0.2);
uniform vec3 light_directions[4];
uniform vec3 light_colors[4];
uniform sampler2D surface_0 : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D clouds_0 : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D surface_1 : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D clouds_1 : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D surface_2 : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D clouds_2 : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D surface_3 : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D clouds_3 : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D surface_4 : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D clouds_4 : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D surface_5 : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D clouds_5 : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D surface_6 : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D clouds_6 : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D surface_7 : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D clouds_7 : source_color, filter_linear_mipmap, repeat_enable;
vec4 surface_at(int i, vec2 uv) {
 if (i == 0) return texture(surface_0, uv);
 if (i == 1) return texture(surface_1, uv);
 if (i == 2) return texture(surface_2, uv);
 if (i == 3) return texture(surface_3, uv);
 if (i == 4) return texture(surface_4, uv);
 if (i == 5) return texture(surface_5, uv);
 if (i == 6) return texture(surface_6, uv);
 if (i == 7) return texture(surface_7, uv);
 return vec4(0.0);
}
vec4 clouds_at(int i, vec2 uv) {
 if (i == 0) return texture(clouds_0, uv);
 if (i == 1) return texture(clouds_1, uv);
 if (i == 2) return texture(clouds_2, uv);
 if (i == 3) return texture(clouds_3, uv);
 if (i == 4) return texture(clouds_4, uv);
 if (i == 5) return texture(clouds_5, uv);
 if (i == 6) return texture(clouds_6, uv);
 if (i == 7) return texture(clouds_7, uv);
 return vec4(0.0);
}
vec3 background(vec3 d) {
 // Mirror only the source Z coordinate. Cubemap filtering crosses face edges.
 vec3 source_direction=vec3(d.x,d.y,-d.z);
 return texture(sky_cube,source_direction).rgb+texture(starfield,source_direction).rgb;
}
float intersection(vec3 ray, vec3 center, float radius) {
 float b=dot(ray,center); float h=b*b-dot(center,center)+radius*radius;
 if(h<0.0 || b<0.0)return -1.0;
 return b-sqrt(h);
}
vec2 sphere_uv(vec3 normal) {
 return vec2(1.0-atan(normal.x,-normal.z)/(2.0*PI),acos(clamp(normal.y,-1.0,1.0))/PI);
}
vec2 billboard_uv(vec3 ray, vec3 direction, float half_size, float roll) {
 vec3 forward=normalize(direction);
 vec3 right=normalize(cross(forward,abs(forward.y)>.99 ? vec3(0,0,1) : vec3(0,1,0)));
 vec3 up=cross(right,forward);
 float depth=dot(ray,forward);
 if(depth<=0.0 || half_size<=0.0)return vec2(-1.0);
 vec2 uv=vec2(dot(ray,right),-dot(ray,up))/depth/half_size;
 uv=mat2(vec2(cos(roll),sin(roll)),vec2(-sin(roll),cos(roll)))*uv;
 return uv*.5+.5;
}
void sky() {
 vec3 ray=normalize(ship_rotation*EYEDIR);
 vec3 color=background(ray);
 vec3 observer=ship_position+ship_rotation*(POSITION-view_origin);
 for(int i=0;i<40;i++) {
  if(i>=celestial_count)break;
  vec2 uv=billboard_uv(ray,celestial_points[i].xyz,celestial_points[i].w,0.0);
  if(all(greaterThanEqual(uv,vec2(0))) && all(lessThanEqual(uv,vec2(1)))) {
   vec4 glow=texture(celestial_textures,vec3(uv,float(i)));color+=glow.rgb*glow.a;
  }
 }
 for(int i=0;i<8;i++) {
  if(i>=planet_count)break;
  vec3 center=planets[i].xyz-observer*(100.0/sector_width);
  float edge=sqrt(max(.001,dot(center,center)-planets[i].w*planets[i].w));
  vec2 uv=billboard_uv(ray,center,planets[i].w/edge*halo_settings[i].x,halo_settings[i].y);
  if(all(greaterThanEqual(uv,vec2(0))) && all(lessThanEqual(uv,vec2(1)))) {
   vec4 glow=texture(halo_textures,vec3(uv,float(i)));color+=glow.rgb*glow.a;
  }
 }
 float nearest=100000.0;
 for(int i=0;i<8;i++) {
  if(i>=planet_count)break;
  vec3 center=planets[i].xyz-observer*(100.0/sector_width);
  float t=intersection(ray,center,planets[i].w);
  vec4 settings=cloud_settings[i];
  float ct=settings.x>0.0 ? intersection(ray,center,settings.x) : -1.0;
  float depth=t>=0.0 ? t : ct;
  if(depth<0.0 || depth>=nearest)continue;
  nearest=depth;
  vec3 normal=normalize(ray*depth-center);
  vec3 illumination=ambient;
  for(int l=0;l<4;l++)illumination+=light_colors[l]*max(0.0,dot(normal,light_directions[l]));
  illumination=clamp(illumination,vec3(0.0),vec3(1.5));
  if(t>=0.0){
   vec2 uv=sphere_uv(planet_rotations[i]*normal);
   uv.x+=TIME*surface_settings[i].z;
   color=surface_at(i,uv*surface_settings[i].xy).rgb*illumination;
  }
  if(ct>=0.0){
   vec2 cuv=sphere_uv(planet_rotations[i]*normalize(ray*ct-center));
   cuv.x+=TIME*settings.w;
   vec4 clouds=clouds_at(i,cuv*settings.yz);
   color=mix(color,clouds.rgb*illumination,clouds.a);
  }
 }
 COLOR=color;
}
