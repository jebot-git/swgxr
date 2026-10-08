#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/transform3d.hpp>
#include <godot_cpp/variant/vector2.hpp>
namespace godot {
// Runtime-neutral wrist hinge, floating view-follow and pointing. Never writes XR poses.
class SwgWristDatapad : public RefCounted {
    GDCLASS(SwgWristDatapad, RefCounted)
    double yaw=0, pitch=0;
    bool view_ready=false;
    double view_yaw=0, view_pitch=0;
    Vector3 view_anchor;
protected:
    static void _bind_methods();
public:
    void reset();
    Dictionary follow_view(const Transform3D &head, const Vector2 &size, double delta, double distance=0.75, bool frozen=false);
    Dictionary follow(const Transform3D &mount, const Vector3 &viewer, double delta, double pitch_limit=0.4363323129985824, double response=12.0);
    Dictionary point(const Transform3D &screen, const Vector2 &size, const Vector2 &pixels, const Vector3 &tip, const Vector3 &direction, double reach=0.65, double touch_depth=0.018) const;
};
}
