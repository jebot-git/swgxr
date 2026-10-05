#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/vector3.hpp>

namespace godot {
// Spatial recovery between strikes. Tracking-relative hand positions only;
// never writes controller/head transforms and takes combat readiness only, never a trigger edge.
class SwgMeleeSwing : public RefCounted {
    GDCLASS(SwgMeleeSwing, RefCounted)
    Vector3 previous, last_strike;
    bool seeded = false;
    double last_speed_required = 0, last_recovery_required = 0;
protected:
    static void _bind_methods();
public:
    void reset();
    Dictionary sample(double delta, const Vector3& position, bool enabled,
                      double speed_required, double recovery_required, bool combat_ready = true);
};
}
