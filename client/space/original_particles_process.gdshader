shader_type particles;
render_mode disable_velocity;
uniform float speed=1.0;
uniform float spread=0.0;
uniform vec2 distance_range=vec2(0.0);
uniform sampler2D speed_curve;
float random(uint seed){seed=((seed>>16u)^seed)*73244475u;seed=((seed>>16u)^seed)*73244475u;seed=(seed>>16u)^seed;return float(seed & 16777215u)/16777216.0;}
void start(){
 uint seed=NUMBER^RANDOM_SEED;
 float angle=random(seed)*TAU;float cone=random(seed+7u)*spread;
 vec3 direction=vec3(sin(cone)*cos(angle),cos(cone),sin(cone)*sin(angle));
 TRANSFORM[3].xyz=direction*mix(distance_range.x,distance_range.y,random(seed+17u));
 vec3 side=normalize(cross(direction,abs(direction.z)<.99?vec3(0,0,1):vec3(1,0,0)));
 TRANSFORM[0].xyz=side;TRANSFORM[1].xyz=direction;TRANSFORM[2].xyz=cross(side,direction);
 VELOCITY=direction*speed;CUSTOM=vec4(0.0);
}
void process(){
 CUSTOM.x+=DELTA;CUSTOM.y=clamp(CUSTOM.x/LIFETIME,0.0,1.0);
 TRANSFORM[3].xyz+=VELOCITY*texture(speed_curve,vec2(CUSTOM.y,.5)).r*DELTA;
}
