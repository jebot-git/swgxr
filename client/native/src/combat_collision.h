#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/aabb.hpp>
#include <vector>
#include <map>
namespace godot {
// Immutable authored geometry snapshots; no dependence on PhysicsServer layers,
// camera membership or render visibility. Call updates on the simulation thread.
class SwgCombatCollision : public RefCounted {
    GDCLASS(SwgCombatCollision, RefCounted)
    struct Triangle { Vector3 a,b,c; String cell; int layer; AABB bounds; };
    struct Branch { AABB bounds; int left=-1,right=-1,start=0,count=0; };
    struct Group { std::vector<Triangle> triangles; std::vector<Branch> tree; AABB coverage; int coverage_layer=1; bool valid=true; };
    struct Portal { std::vector<Vector3> points; String target; };
    struct Cell { bool exterior=false; std::vector<Portal> portals; };
    std::map<String,Cell> cells;
    std::map<String,Group> groups;
    bool require_terrain=false;
    int build(Group &group,int start,int count);
    bool covered(const Vector3 &from,const Vector3 &to,int layer) const;
protected: static void _bind_methods();
public:
    void configure(const Array &regions);
    void set_geometry(const String &key,const Array &surfaces,const AABB &coverage,int coverage_layer=1);
    bool adopt_geometry(const String &key,const Ref<SwgCombatCollision> &prepared,const String &source_key);
    void remove_geometry(const String &key);
    void set_require_terrain(bool value);
    Dictionary trace_segment(const Vector3 &from,const Vector3 &to,const String &cell_id=String(),int mask=7) const;
    Array trace_segments(const Array &segments) const;
    Dictionary statistics() const;
};
}
