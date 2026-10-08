#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
namespace godot {
// Pure movement modifiers: no ownership of tracking, physics bodies or authority.
class SwgScoutLocomotion : public RefCounted {
    GDCLASS(SwgScoutLocomotion, RefCounted)
protected:
    static void _bind_methods();
public:
    static Dictionary source_movement(const Dictionary &profile, double current_speed, double input_magnitude, bool walking, const Dictionary &environment, double delta);
    static double terrain_factor(double angle_degrees, double uphill, double negotiation);
    static double speed_factor(double angle_degrees, double uphill, double negotiation,
                               bool burst_active, double burst_remaining, double snapshot_age);
};
}
