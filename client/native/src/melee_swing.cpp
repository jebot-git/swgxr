#include "melee_swing.h"
#include <godot_cpp/core/class_db.hpp>
#include <cmath>
#include <algorithm>

using namespace godot;
void SwgMeleeSwing::_bind_methods() {
    ClassDB::bind_method(D_METHOD("reset"), &SwgMeleeSwing::reset);
    ClassDB::bind_method(D_METHOD("sample", "delta", "position", "enabled", "speed_required", "recovery_required", "combat_ready"), &SwgMeleeSwing::sample, DEFVAL(true));
}
void SwgMeleeSwing::reset() {
    seeded = false;
    last_speed_required = last_recovery_required = 0;
}
Dictionary SwgMeleeSwing::sample(double delta, const Vector3& position, bool enabled,
                               double speed_required, double recovery_required, bool combat_ready) {
    Dictionary result;
    result["hit"] = false; result["engaged"] = false;
    result["speed"] = 0.0; result["travel"] = 0.0;
    if (!enabled || !position.is_finite() || !std::isfinite(delta) || delta <= 0 || delta > 0.1 ||
        !std::isfinite(speed_required) || speed_required <= 0 ||
        !std::isfinite(recovery_required) || recovery_required <= 0) {
        reset(); return result;
    }
    // A draw, tracking recovery or stat/grip change establishes a fresh spatial
    // origin. None can spend movement collected before that transition.
    if (!seeded || last_speed_required != speed_required || last_recovery_required != recovery_required) {
        previous = last_strike = position;
        last_speed_required = speed_required; last_recovery_required = recovery_required;
        seeded = true; result["engaged"] = combat_ready;
        return result;
    }
    const double distance = position.distance_to(previous);
    const double speed = distance / delta;
    const double start_recovery = previous.distance_to(last_strike);
    const double recovery = position.distance_to(last_strike);
    previous = position;
    if (speed > 15.0 || distance > 0.5) { reset(); return result; }
    result["engaged"] = combat_ready;
    result["speed"] = speed; result["travel"] = recovery;
    // Direct separation, not accumulated path length: circling/shaking inside
    // the recovery radius never rearms. A slow withdrawal may prepare a strike,
    // but only a sufficiently fast subsequent segment can attack. Use its start
    // as well as its end so an inward swing from the radius boundary qualifies.
    if (combat_ready && std::max(start_recovery, recovery) + 1e-6 >= recovery_required && speed + 1e-6 >= speed_required) {
        result["hit"] = true;
        last_strike = position;
    }
    return result;
}
