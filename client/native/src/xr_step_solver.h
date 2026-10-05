#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/character_body3d.hpp>
#include <godot_cpp/variant/vector3.hpp>

namespace godot {
// Bounded collision helper. It never owns input, velocity, an XR origin or
// tracked poses, and can be reused with any CharacterBody3D capsule.
class SwgXRStepSolver : public RefCounted {
    GDCLASS(SwgXRStepSolver, RefCounted)
protected:
    static void _bind_methods();
public:
    bool has_support(CharacterBody3D *body, double distance = 0.1) const;
    bool step_up(CharacterBody3D *body, const Vector3 &motion, double maximum = 0.35) const;
    bool step_down(CharacterBody3D *body, double maximum = 0.35) const;
};
}
