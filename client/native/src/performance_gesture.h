#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/transform3d.hpp>
#include <godot_cpp/variant/string.hpp>
namespace godot {
class SwgPerformanceGesture : public RefCounted {
    GDCLASS(SwgPerformanceGesture, RefCounted)
    Vector3 previous_main, previous_off, anchor;
    String mode;
    bool have = false;
    double elapsed = 0, held = 0, last_stroke = -10;
    double key_top_main = 0, key_top_off = 0;
    int direction = 0, axis = -1, strokes = 0, last_hand = -1;
protected:
    static void _bind_methods();
public:
    void reset();
    bool sample(double delta, const String &kind, const Transform3D &head,
                const Transform3D &main, const Transform3D &off, bool tracked);
};
}
