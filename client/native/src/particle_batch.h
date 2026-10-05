#pragma once
#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/classes/multi_mesh.hpp>
#include <godot_cpp/classes/multi_mesh_instance3d.hpp>
#include <godot_cpp/classes/shader_material.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <array>
#include <vector>
namespace godot {
// Presentation only: dropping any entry never changes projectile/game state.
class SwgParticleBatch : public Node3D {
    GDCLASS(SwgParticleBatch, Node3D)
    static constexpr int MAX_STYLES=48, MAX_PARTICLES=2048, MAX_TRACERS=512, STYLE_CAP=512, EVENT_CAP=96;
    struct Style {
        Ref<MultiMesh> mesh; MultiMeshInstance3D *node=nullptr;
        PackedFloat32Array buffer;
        Color color=Color(1,0.2,0.05,1), end_color=Color(1,0.2,0.05,0);
        float width=.06f,length=.4f,end_width=.06f,end_length=.4f,life=.25f,speed=1,spread=.5f,gravity=0,max_distance=100;
        int kind=0,visible=0; bool secondary=false;
    };
    struct Particle { bool active=false; int style=0; Vector3 position,velocity; float age=0; uint32_t seed=0; };
    struct Tracer { bool active=false; int style=0; uint32_t generation=1; Transform3D pose; };
    std::vector<Style> styles;
    std::array<Particle,MAX_PARTICLES> particles;
    std::array<Tracer,MAX_TRACERS> tracers;
    Transform3D view;
    bool view_ready=false;
    float tan_v=1.732f,tan_h=2.425f;
    int live_particles=0,live_tracers=0,peak_particles=0,peak_tracers=0,frame_events=0,frame_tracer_events=0,peak_visible=0,render_visible=0;
    uint64_t requested=0,admitted=0,drop_distance=0,drop_frustum=0,drop_budget=0,drop_lod=0,drop_invalid=0,drop_no_view=0;
    uint64_t lod_full=0,lod_reduced=0,lod_minimal=0;
    uint32_t random_state=0x58391U;
    float random_unit();
    int visibility(const Style &,const Vector3 &,bool count=true);
    bool event_allowed(int style,const Vector3 &position,int &tier);
    void append(Style &,const Transform3D &,const Color &,float age);
    bool valid_handle(int handle,int &index) const;
protected:
    static void _bind_methods();
public:
    int register_style(const Dictionary &style);
    bool emit_burst(int style,const Transform3D &pose,int count=1);
    int create_tracer(int style,const Transform3D &pose);
    void update_tracer(int handle,const Transform3D &pose);
    void release_tracer(int handle);
    void set_view(const Transform3D &pose,double fov_y_degrees=100.0,double aspect=1.4);
    void advance(double delta);
    Dictionary statistics() const;
    void clear();
};
}
