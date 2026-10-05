#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>

namespace godot {
// Presentation-only state. Never writes a tracking pose, body or velocity.
class SwgViewPosture : public RefCounted {
    GDCLASS(SwgViewPosture, RefCounted)
    PackedVector2Array jump_curve;
    double jump_time = -1, offset = 0, since_attempt = 1;
    bool knocked = false, pending = false;
protected:
    static void _bind_methods();
public:
    bool configure_jump(const PackedVector2Array &curve);
    void reset();
    bool knock_down(int physical_posture);
    Dictionary press_jump(int physical_posture, bool grounded, bool allowed);
    void resolve_recovery(bool success);
    void clear_knockdown() { knocked = pending = false; }
    Dictionary advance(double delta, int physical_posture, double eye_height, bool tracked);
    bool is_knocked_down() const { return knocked; }
    double get_view_offset() const { return offset; }
    double get_jump_time() const { return jump_time; }
};
}
