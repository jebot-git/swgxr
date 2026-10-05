#include "particle_batch.h"
#include <godot_cpp/classes/quad_mesh.hpp>
#include <godot_cpp/classes/shader.hpp>
#include <godot_cpp/classes/texture2d.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <algorithm>
#include <cmath>
using namespace godot;
namespace {
float number(const Dictionary &d,const char *key,float fallback,float lo,float hi) {
    double n=d.get(key,fallback); return std::isfinite(n)?std::clamp(float(n),lo,hi):fallback;
}
bool finite_pose(const Transform3D &t) { return t.origin.is_finite() && t.basis.is_finite(); }
}
void SwgParticleBatch::_bind_methods() {
    ClassDB::bind_method(D_METHOD("register_style","style"),&SwgParticleBatch::register_style);
    ClassDB::bind_method(D_METHOD("emit_burst","style_id","pose","count"),&SwgParticleBatch::emit_burst,DEFVAL(1));
    ClassDB::bind_method(D_METHOD("create_tracer","style_id","pose"),&SwgParticleBatch::create_tracer);
    ClassDB::bind_method(D_METHOD("update_tracer","handle","pose"),&SwgParticleBatch::update_tracer);
    ClassDB::bind_method(D_METHOD("release_tracer","handle"),&SwgParticleBatch::release_tracer);
    ClassDB::bind_method(D_METHOD("set_view","pose","fov_y_degrees","aspect"),&SwgParticleBatch::set_view,DEFVAL(100.0),DEFVAL(1.4));
    ClassDB::bind_method(D_METHOD("advance","delta"),&SwgParticleBatch::advance);
    ClassDB::bind_method(D_METHOD("statistics"),&SwgParticleBatch::statistics);
    ClassDB::bind_method(D_METHOD("clear"),&SwgParticleBatch::clear);
}
int SwgParticleBatch::register_style(const Dictionary &d) {
    if (styles.size()>=MAX_STYLES) { ++drop_budget;return -1; }
    Style s;
    String kind=d.get("kind","impact"); s.kind=kind=="tracer"?0:(kind=="muzzle"?1:2);
    s.color=d.get("color",s.color); s.end_color=d.get("color_end",Color(s.color.r,s.color.g,s.color.b,0));
    s.width=number(d,"width",.06,.001,8); s.length=number(d,"length",s.width,.001,8);
    s.end_width=number(d,"width_end",s.width,.001,8); s.end_length=number(d,"length_end",s.length,.001,8);
    s.life=number(d,"life",.25,.016,3);s.speed=number(d,"speed",1,0,40);s.spread=number(d,"spread",.5,0,3.14159);
    s.gravity=number(d,"gravity",0,-30,30);s.max_distance=number(d,"max_distance",100,1,100);s.secondary=d.get("secondary",false);
    Ref<Shader> shader;shader.instantiate();
    String blend=d.get("blend","additive");
    String code="shader_type spatial; render_mode unshaded, cull_disabled, depth_draw_never, fog_disabled, ";
    code+=(blend=="alpha"?"blend_mix;\n":"blend_add;\n");
    code+=R"SHADER(
uniform sampler2D source_texture : source_color, hint_default_white, filter_linear_mipmap;
uniform bool ribbon = false;
uniform vec4 core_color : source_color = vec4(1.);
uniform float core_ratio = 0.;
uniform vec4 uv_rect = vec4(0.,0.,1.,1.);
uniform ivec2 atlas_grid = ivec2(1);
uniform int frame_count = 1;
varying vec2 source_uv;
void vertex() {
    vec3 side = INV_VIEW_MATRIX[0].xyz;
    vec3 up = INV_VIEW_MATRIX[1].xyz;
    if (ribbon) {
        up = normalize(MODEL_MATRIX[1].xyz);
        vec3 to_eye = normalize(INV_VIEW_MATRIX[3].xyz - MODEL_MATRIX[3].xyz);
        vec3 candidate = cross(up, to_eye);
        if (dot(candidate,candidate)>0.00001) side=normalize(candidate);
    }
    mat4 billboard=mat4(vec4(side*length(MODEL_MATRIX[0].xyz),0.),vec4(up*length(MODEL_MATRIX[1].xyz),0.),vec4(cross(side,up),0.),MODEL_MATRIX[3]);
    MODELVIEW_MATRIX=VIEW_MATRIX*billboard;
    int frame=min(frame_count-1,int(INSTANCE_CUSTOM.x*float(frame_count)));
    vec2 tile=vec2(float(frame%atlas_grid.x),float(frame/atlas_grid.x));
    source_uv=uv_rect.xy+(UV+tile)/vec2(atlas_grid)*uv_rect.zw;
}
void fragment() {
    vec4 tex=texture(source_texture,source_uv);
    vec3 tint=COLOR.rgb;
    if(ribbon && core_ratio>0.) {
        float distance_from_center=abs(UV.x-.5)*2.;
        float core=1.-smoothstep(core_ratio*.65,core_ratio,distance_from_center);
        tint=mix(tint,core_color.rgb,core*core_color.a);
    }
    ALBEDO=tex.rgb*tint;
    ALPHA=tex.a*COLOR.a;
}
)SHADER";
    shader->set_code(code);
    Ref<ShaderMaterial> material;material.instantiate();material->set_shader(shader);
    if(d.has("texture")) material->set_shader_parameter("source_texture",d["texture"]);
    material->set_shader_parameter("ribbon",s.kind==0);
    material->set_shader_parameter("core_color",d.get("core_color",Color(1,1,1,1)));
    material->set_shader_parameter("core_ratio",number(d,"core_ratio",0,0,1));
    material->set_shader_parameter("uv_rect",d.get("uv_rect",Vector4(0,0,1,1)));
    int cols=int(number(d,"atlas_columns",1,1,32)),rows=int(number(d,"atlas_rows",1,1,32));
    material->set_shader_parameter("atlas_grid",Vector2i(cols,rows));
    material->set_shader_parameter("frame_count",int(number(d,"frame_count",1,1,cols*rows)));
    Ref<QuadMesh> quad;quad.instantiate();quad->set_size(Vector2(1,1));quad->set_material(material);
    s.mesh.instantiate();s.mesh->set_transform_format(MultiMesh::TRANSFORM_3D);s.mesh->set_use_colors(true);s.mesh->set_use_custom_data(true);
    s.mesh->set_mesh(quad);s.mesh->set_instance_count(STYLE_CAP);s.mesh->set_visible_instance_count(0);
    s.buffer.resize(STYLE_CAP*20);s.buffer.fill(0);
    s.node=memnew(MultiMeshInstance3D);s.node->set_name(String("ParticleBatch_")+String::num_int64(styles.size()));
    s.node->set_multimesh(s.mesh);s.node->set_cast_shadows_setting(GeometryInstance3D::SHADOW_CASTING_SETTING_OFF);
    add_child(s.node);
    styles.push_back(s);return int(styles.size()-1);
}
float SwgParticleBatch::random_unit() { random_state^=random_state<<13;random_state^=random_state>>17;random_state^=random_state<<5;return float(random_state&0xffffff)/float(0x1000000); }
int SwgParticleBatch::visibility(const Style &s,const Vector3 &p,bool count) {
    if(!view_ready) {if(count)++drop_no_view;return -1;}
    Vector3 relative=p-view.origin;float distance=relative.length();
    if(distance>s.max_distance) {if(count)++drop_distance;return -1;}
    // Two metres always admitted: avoids popping at either eye/near controllers.
    // 15 degree angular margin plus emitter radius covers stereo and late head motion.
    if(distance>2) {
        Vector3 local=view.basis.transposed().xform(relative);float depth=-local.z;
        float radius=std::max(s.width,s.length)*.5f+2;
        if(depth < -radius || std::abs(local.x)>std::max(0.0f,depth)*tan_h+radius || std::abs(local.y)>std::max(0.0f,depth)*tan_v+radius) {
            if(count)++drop_frustum;return -1;
        }
    }
    int tier=distance<=20?0:(distance<=50?1:2);
    if(tier==2&&(s.kind==1||s.secondary)) {if(count)++drop_lod;return -1;}
    return tier;
}
bool SwgParticleBatch::event_allowed(int style,const Vector3 &position,int &tier) {
    ++requested;
    if(style<0||style>=int(styles.size())||!position.is_finite()) {++drop_invalid;return false;}
    tier=visibility(styles[style],position);
    if(tier<0)return false;
    if(frame_events>=EVENT_CAP) {++drop_budget;return false;}
    ++frame_events;
    if(tier==0)++lod_full;else if(tier==1)++lod_reduced;else ++lod_minimal;
    return true;
}
bool SwgParticleBatch::emit_burst(int style,const Transform3D &pose,int count) {
    if(!finite_pose(pose)) {++drop_invalid;return false;}
    int tier;if(!event_allowed(style,pose.origin,tier))return false;
    count=std::clamp(count,0,64);if(!count)return false;
    const Style &s=styles[style];
    int accepted_count=tier==0?count:(tier==1?std::max(1,count/3):1);
    drop_lod+=count-accepted_count;
    int made=0;
    for(int i=0;i<MAX_PARTICLES&&made<accepted_count;++i) {
        Particle &p=particles[i];if(p.active)continue;
        p.active=true;p.style=style;p.age=0;p.position=pose.origin;p.seed=++random_state;
        // Density was already reduced on admission; do not thin twice on the
        // first advance. This seed still enforces stricter tiers on movement.
        if(tier==1)p.seed-=p.seed%3;
        if(tier==2)p.seed-=p.seed%24;
        float angle=random_unit()*6.2831853f,cos_theta=1-random_unit()*(1-std::cos(s.spread)),sin_theta=std::sqrt(std::max(0.0f,1-cos_theta*cos_theta));
        Vector3 velocity(std::cos(angle)*sin_theta,cos_theta,std::sin(angle)*sin_theta);
        p.velocity=pose.basis.orthonormalized().xform(velocity)*(s.speed*(.65f+random_unit()*.7f));
        ++live_particles;++made;
    }
    if(made<accepted_count)drop_budget+=accepted_count-made;
    peak_particles=std::max(peak_particles,live_particles);if(made)++admitted;return made>0;
}
int SwgParticleBatch::create_tracer(int style,const Transform3D &pose) {
    if(!finite_pose(pose)) {++drop_invalid;return -1;}
    ++requested;
    if(style<0||style>=int(styles.size())) {++drop_invalid;return -1;}
    if(frame_tracer_events>=EVENT_CAP) {++drop_budget;return -1;}
    ++frame_tracer_events;
    // Bounded logical handles survive visibility rejection: a projectile born
    // outside the view can enter it later without replaying any burst.
    for(int i=0;i<MAX_TRACERS;++i) if(!tracers[i].active) {
        Tracer &t=tracers[i];t.active=true;t.style=style;t.pose=pose;++live_tracers;++admitted;
        peak_tracers=std::max(peak_tracers,live_tracers);return int(t.generation*MAX_TRACERS+i);
    }
    ++drop_budget;return -1;
}
bool SwgParticleBatch::valid_handle(int handle,int &index) const {
    if(handle<0)return false;index=handle%MAX_TRACERS;
    return tracers[index].active&&tracers[index].generation==uint32_t(handle/MAX_TRACERS);
}
void SwgParticleBatch::update_tracer(int handle,const Transform3D &pose) {int i;if(valid_handle(handle,i)&&finite_pose(pose))tracers[i].pose=pose;}
void SwgParticleBatch::release_tracer(int handle) {int i;if(!valid_handle(handle,i))return;tracers[i].active=false;tracers[i].generation=(tracers[i].generation+1)%4000000+1;--live_tracers;}
void SwgParticleBatch::set_view(const Transform3D &pose,double fov,double aspect) {
    if(!finite_pose(pose)||!std::isfinite(fov)||!std::isfinite(aspect)) {view_ready=false;return;}
    view=Transform3D(pose.basis.orthonormalized(),pose.origin);view_ready=true;
    tan_v=std::tan(std::clamp(fov*.5+15.0,30.0,85.0)*3.141592653589793/180.0);
    tan_h=tan_v*std::clamp(aspect,.5,3.0);
}
void SwgParticleBatch::append(Style &s,const Transform3D &pose,const Color &color,float age) {
    if(s.visible>=STYLE_CAP) {++drop_budget;return;}
    float *p=s.buffer.ptrw()+20*s.visible++;
    for(int r=0;r<3;++r) {for(int c=0;c<3;++c)p[r*4+c]=pose.basis.rows[r][c];p[r*4+3]=pose.origin[r];}
    p[12]=color.r;p[13]=color.g;p[14]=color.b;p[15]=color.a;p[16]=age;p[17]=p[18]=p[19]=0;
}
void SwgParticleBatch::advance(double delta) {
    // Drop elapsed backlog after pauses. No emission catch-up or per-effect ticks.
    float elapsed=std::isfinite(delta)?std::clamp(float(delta),0.0f,4.0f):0;
    float dt=std::min(elapsed,.1f);
    for(Style &s:styles)s.visible=0;
    for(Particle &p:particles) if(p.active) {
        Style &s=styles[p.style];p.age+=elapsed;
        if(p.age>=s.life) {p.active=false;--live_particles;continue;}
        p.velocity.y-=s.gravity*dt;p.position+=p.velocity*dt;
        int tier=visibility(s,p.position);
        if(tier<0||(tier==1&&p.seed%3!=0)||(tier==2&&p.seed%8!=0)) {
            if(tier>=0)++drop_lod;p.active=false;--live_particles;continue;
        }
        float progress=p.age/s.life;
        Color color=s.color.lerp(s.end_color,progress);
        Basis basis;basis.scale(Vector3(s.width+(s.end_width-s.width)*progress,s.length+(s.end_length-s.length)*progress,1));
        append(s,Transform3D(basis,p.position),color,progress);
    }
    for(int i=0;i<MAX_TRACERS;++i) if(tracers[i].active) {
        Tracer &t=tracers[i];Style &s=styles[t.style];int tier=visibility(s,t.pose.origin);
        if(tier<0)continue;
        if(tier==2&&i%2) {++drop_lod;continue;}
        Vector3 direction=-t.pose.basis.get_column(2).normalized();
        if(direction.length_squared()<.01)direction=Vector3(0,0,-1);
        Vector3 side=direction.cross(Vector3(0,1,0));if(side.length_squared()<.01)side=Vector3(1,0,0);else side.normalize();
        Basis basis(side*s.width,direction*s.length,side.cross(direction));
        append(s,Transform3D(basis,t.pose.origin),s.color,0);
    }
    render_visible=0;
    for(Style &s:styles) {
        if(s.visible)s.mesh->set_buffer(s.buffer);
        s.mesh->set_visible_instance_count(s.visible);render_visible+=s.visible;
    }
    peak_visible=std::max(peak_visible,render_visible);frame_events=0;frame_tracer_events=0;
}
Dictionary SwgParticleBatch::statistics() const {
    Dictionary d;d["styles"]=int(styles.size());d["particles"]=live_particles;d["tracers"]=live_tracers;d["render_visible"]=render_visible;
    d["peak_particles"]=peak_particles;d["peak_tracers"]=peak_tracers;d["peak_visible"]=peak_visible;
    d["max_styles"]=MAX_STYLES;d["max_particles"]=MAX_PARTICLES;d["max_tracers"]=MAX_TRACERS;d["max_instances_per_style"]=STYLE_CAP;d["max_events_per_frame"]=EVENT_CAP;
    d["max_tracer_events_per_frame"]=EVENT_CAP;
    d["events_requested"]=requested;d["events_admitted"]=admitted;d["dropped_distance"]=drop_distance;d["dropped_frustum"]=drop_frustum;d["dropped_budget"]=drop_budget;d["dropped_lod"]=drop_lod;d["dropped_invalid"]=drop_invalid;d["dropped_no_view"]=drop_no_view;
    d["lod_full"]=lod_full;d["lod_reduced"]=lod_reduced;d["lod_minimal"]=lod_minimal;d["view_ready"]=view_ready;
    d["lod_full_distance"]=20;d["lod_reduced_distance"]=50;d["hard_distance"]=100;
    d["near_frustum_distance"]=2;
    d["render_nodes"]=int(styles.size());d["materials"]=int(styles.size());d["batches"]=int(styles.size());
    int active_batches=0;for(const Style &s:styles)if(s.visible)++active_batches;
    d["active_batches"]=active_batches;d["max_render_nodes"]=MAX_STYLES;d["max_materials"]=MAX_STYLES;
    return d;
}
void SwgParticleBatch::clear() {
    for(Particle &p:particles)p.active=false;
    for(int i=0;i<MAX_TRACERS;++i) if(tracers[i].active)release_tracer(int(tracers[i].generation*MAX_TRACERS+i));
    live_particles=0;render_visible=0;frame_events=0;frame_tracer_events=0;
    for(Style &s:styles) {s.visible=0;s.mesh->set_visible_instance_count(0);}
}
