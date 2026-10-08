shader_type canvas_item;
render_mode unshaded;

// Sparse independently jittered layers: no cloud, glow, motion, or colored cast.
float hash21(vec2 p) { return fract(sin(dot(p, vec2(127.1,311.7))) * 43758.5453); }
float stars(vec2 uv, float density, float seed, float threshold, float size_scale) {
	vec2 p=uv*density;
	vec2 cell=floor(p);
	float choice=hash21(cell+seed+28.1);
	vec2 center=vec2(hash21(cell+seed),hash21(cell+seed+9.7))*.84+.08;
	float pixel_width=fwidth(p.y);
	float radius=mix(.38,.85,hash21(cell+seed+56.2))*pixel_width*size_scale;
	float point=1.0-smoothstep(max(0.0,radius-pixel_width*.45),radius+pixel_width*.45,length(fract(p)-center));
	float brightness=mix(.26,1.0,pow(hash21(cell+seed+84.3),1.8));
	return point*brightness*step(threshold,choice);
}
void fragment() {
	vec2 uv=UV;
	uv.x*=SCREEN_PIXEL_SIZE.y/SCREEN_PIXEL_SIZE.x;
	float field=stars(uv,36.0,3.0,.84,1.0)
		+stars(uv,68.0,17.0,.95,.75)
		+stars(uv,24.0,43.0,.985,1.8);
	COLOR=vec4(vec3(min(field,1.0)),1.0);
}
