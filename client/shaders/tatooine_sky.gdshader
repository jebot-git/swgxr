shader_type sky;
uniform vec4 top_color : source_color = vec4(0.23,0.46,0.62,1.0);
uniform vec4 horizon_color : source_color = vec4(0.71,0.61,0.50,1.0);
uniform float phase = 0.25;
uniform float daylight = 1.0;
uniform sampler2D sun_texture : source_color, filter_linear_mipmap;
uniform sampler2D moon_texture : source_color, filter_linear_mipmap;
uniform bool sun_enabled = true;
uniform bool moon_enabled = true;
uniform bool second_sun = true;
uniform float sun_size = 0.018;
vec3 disk(vec3 direction, vec3 center, float size, sampler2D image) {
 vec3 right = normalize(cross(center, vec3(0.0,0.0,1.0)));
 vec3 up = normalize(cross(right, center));
 vec2 uv = vec2(dot(direction,right),dot(direction,up)) / size * 0.5 + 0.5;
 if (dot(direction,center) < 0.0 || any(lessThan(uv,vec2(0.0))) || any(greaterThan(uv,vec2(1.0)))) return vec3(0.0);
 vec4 pixel = texture(image,uv);
 return pixel.rgb * pixel.a;
}
void sky() {
 float height = clamp(EYEDIR.y,0.0,1.0);
 vec3 color = mix(horizon_color.rgb,top_color.rgb,pow(height,0.45));
 float angle = phase * 6.2831853;
 vec3 sun = normalize(vec3(cos(angle),sin(angle),-0.25));
 vec3 second = normalize(vec3(cos(angle+0.10),sin(angle+0.10),-0.40));
 if (sun_enabled) color += disk(EYEDIR,sun,sun_size,sun_texture) * vec3(1.0,0.93,0.76) * daylight;
 if (second_sun) color += disk(EYEDIR,second,sun_size*0.8,sun_texture) * vec3(1.0,0.65,0.40) * daylight;
 if (moon_enabled) color += disk(EYEDIR,-sun,sun_size*0.8,moon_texture) * (1.0-daylight) * 0.55;
 // Static star field; original stellar palette/sky art remain the color source.
 vec3 cell = floor(EYEDIR * 900.0);
 float star = fract(sin(dot(cell,vec3(12.9898,78.233,37.719)))*43758.5453);
 color += vec3(step(0.9996,star)*0.6*(1.0-daylight)*smoothstep(0.0,0.15,EYEDIR.y));
 COLOR = color;
}
