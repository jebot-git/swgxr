#include "scout_locomotion.h"
#include <godot_cpp/core/class_db.hpp>
#include <algorithm>
#include <cmath>
using namespace godot;
void SwgScoutLocomotion::_bind_methods() {
    ClassDB::bind_static_method("SwgScoutLocomotion", D_METHOD("terrain_factor", "angle_degrees", "uphill", "negotiation"), &SwgScoutLocomotion::terrain_factor);
    ClassDB::bind_static_method("SwgScoutLocomotion", D_METHOD("speed_factor", "angle_degrees", "uphill", "negotiation", "burst_active", "burst_remaining", "snapshot_age"), &SwgScoutLocomotion::speed_factor);
}
double SwgScoutLocomotion::terrain_factor(double angle, double uphill, double negotiation) {
    if (!std::isfinite(angle) || !std::isfinite(uphill) || !std::isfinite(negotiation)) return 1.0;
    return 1.0 - 0.5 * std::clamp(angle / 45.0, 0.0, 1.0) * std::clamp(uphill, 0.0, 1.0) * (1.0 - std::clamp(negotiation, 0.0, 1.0));
}
double SwgScoutLocomotion::speed_factor(double angle, double uphill, double negotiation,
                                      bool burst, double remaining, double age) {
    if (!std::isfinite(age) || age < 0 || age > 12) return 1.0;
    const bool confirmed_burst = burst && std::isfinite(remaining) && age < remaining;
    return terrain_factor(angle, uphill, negotiation) * (confirmed_burst ? 1.822 : 1.0);
}
