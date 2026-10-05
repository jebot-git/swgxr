#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/skeleton3d.hpp>
#include <godot_cpp/classes/skin.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <vector>
namespace godot {
// Exact rank-one compression of a uniform residual skin-weight distribution.
// The virtual bind remains a full affine matrix: no quaternion decomposition,
// discarded influences, or CPU vertex re-upload is involved.
class SwgVirtualSkinBinding : public RefCounted {
    GDCLASS(SwgVirtualSkinBinding, RefCounted)
    struct Source { int bone; Transform3D inverse_bind; };
    struct Group { int bone; int bind; std::vector<Source> sources; };
    uint64_t skeleton_id=0;
    Ref<Skin> skin;
    std::vector<Group> groups;
protected:
    static void _bind_methods();
public:
    bool configure(Skeleton3D *skeleton, const Ref<Skin> &skin, const Array &definitions);
    Dictionary update();
};
}
