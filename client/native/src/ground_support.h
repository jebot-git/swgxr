#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/vector3.hpp>
#include <vector>
#include <map>
namespace godot {
// Independent evaluation of locally imported, authored walkable floor data.
// No XR poses, physics bodies, streaming or scene membership are owned here.
class SwgGroundSupport : public RefCounted {
    GDCLASS(SwgGroundSupport, RefCounted)
    struct Triangle { Vector3 a,b,c,normal; int64_t id; Array neighbors,edges,portals; };
    struct Floor { String id; Variant building; bool exterior; Vector3 minimum,maximum; std::vector<Triangle> triangles; };
    std::vector<Floor> floors;
    std::map<String,std::vector<Floor>> regions;
    std::vector<const Floor *> floor_index;
    void rebuild_index();
protected:
    static void _bind_methods();
public:
    bool configure(const Array &regions);
    bool adopt_region(const String &key,const Ref<SwgGroundSupport> &prepared);
    void remove_region(const String &key);
    Dictionary sample_support(const Vector3 &position, const Array &allowed_cell_ids, double max_up, double max_down, const Dictionary &previous = Dictionary()) const;
    Dictionary capsule_support(const Vector3 &position, double radius, const Array &allowed_cell_ids, double max_up, double max_down) const;
    Dictionary constrain_motion(const Vector3 &position, const Vector3 &motion, const Array &allowed_cell_ids, double radius, double height_tolerance = 0.35) const;
};
}
