shader_type sky;
// The surround uses the same quiet, neutral-white-on-black title treatment.
float hash21(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
void sky() {
	vec3 direction=normalize(EYEDIR);
	vec2 uv=vec2(atan(direction.x,direction.z)/6.2831853+.5,asin(direction.y)/3.14159265+.5);
	vec2 grid=vec2(600.0,300.0);
	vec2 p=uv*grid;
	vec2 cell=floor(p);
	float chance=hash21(cell);
	vec2 center=vec2(hash21(cell+19.3),hash21(cell+43.7))*.84+.08;
	// Correct longitude scale so stars stay round away from the equator.
	vec2 delta=fract(p)-center;
	delta.x*=max(.02,cos((uv.y-.5)*3.14159265));
	float size=mix(.018,.052,hash21(cell+71.2));
	if (hash21(cell+97.1)>.985) { size*=1.8; }
	float star=1.0-smoothstep(size*.35,size,length(delta));
	float brightness=mix(.26,1.0,pow(hash21(cell+121.4),1.8));
	COLOR=vec3(star*brightness*step(.975,chance));
}
