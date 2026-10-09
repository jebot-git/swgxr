shader_type sky;
uniform mat3 ship_rotation=mat3(1.0);
void sky(){
	vec3 direction=ship_rotation*EYEDIR;
	vec3 cell=floor(direction*700.0);
	float hash=fract(sin(dot(cell,vec3(12.9898,78.233,37.719)))*43758.5453);
	float star=step(.9985,hash);
	COLOR=vec3(.001,.002,.006)+vec3(.7,.85,1.0)*star;
}
