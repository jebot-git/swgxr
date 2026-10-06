#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/skeleton3d.hpp>
#include <godot_cpp/variant/dictionary.hpp>

namespace godot {
// Tracking targets are bone frames in Skeleton3D space, independent of world
// scale, OpenXR runtime, controller models and the camera's scene hierarchy.
class SwgTrackedIK : public RefCounted {
    GDCLASS(SwgTrackedIK, RefCounted)
    struct Arm {
        int upper = -1, lower = -1, hand = -1;
        Quaternion upper_pose, lower_pose;
        double first_length = 0, second_length = 0;
        Vector3 bend;
        bool have_bend = false;
        bool attached = false;
        Vector3 free_hand_position;
    };
    uint64_t skeleton_id = 0;
    int head = -1;
    Arm left, right;
    Dictionary solve_arm(Skeleton3D *skeleton, Arm &arm, const Transform3D &target,
                         const Vector3 &pole, double delta, bool attached = false);
protected:
    static void _bind_methods();
public:
    bool configure(Skeleton3D *skeleton, const Dictionary &mapping = Dictionary());
    Dictionary solve(const Dictionary &targets, double delta);
    void reset_smoothing();
    Transform3D limit_hand_target(const String &side, const Transform3D &target) const;
    Transform3D limit_hand_pair(const String &side, const Transform3D &target, const Transform3D &support) const;
};
}
