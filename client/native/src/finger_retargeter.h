#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/skeleton3d.hpp>
#include <godot_cpp/variant/dictionary.hpp>
namespace godot {
class SwgFingerRetargeter : public RefCounted {
    GDCLASS(SwgFingerRetargeter, RefCounted)
    struct Finger { int first=-1, second=-1; Quaternion rest_first, rest_second; Vector3 direction_first, direction_second; };
    struct Hand { int wrist=-1; Finger thumb, index, ring; Basis anatomy; Vector3 inward; };
    uint64_t skeleton_id=0;
    Hand left, right;
    Dictionary controller_hand(Skeleton3D *, Hand &, const Dictionary &);
protected:
    static void _bind_methods();
public:
    bool configure(Skeleton3D *skeleton);
    Dictionary apply_controller(const Dictionary &left, const Dictionary &right);
    Dictionary apply_hand_joints(const String &side, const Dictionary &joints);
};
}
