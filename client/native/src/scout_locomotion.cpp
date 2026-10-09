#include "scout_locomotion.h"
#include <godot_cpp/core/class_db.hpp>
#include <algorithm>
#include <cmath>
using namespace godot;
void SwgScoutLocomotion::_bind_methods() {
    ClassDB::bind_static_method("SwgScoutLocomotion", D_METHOD("source_movement", "profile", "current_speed", "input_magnitude", "walking", "environment", "delta"), &SwgScoutLocomotion::source_movement);
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

Dictionary SwgScoutLocomotion::source_movement(const Dictionary &profile, double current,
        double input, bool walking, const Dictionary &environment, double delta) {
    Dictionary out; out["valid"] = false;
    // Original CreatureObject movement scale/percent are separate native fields.
    // BurstRun, posture and private-speed changes are already in those fields.
    const char *fields[] = {"run_speed", "walk_speed", "run_acceleration", "walk_acceleration",
        "speed_multiplier_base", "speed_multiplier_mod", "acceleration_multiplier_base",
        "acceleration_multiplier_mod", "slope_mod_angle_radians", "slope_mod_percent",
        "water_mod_percent", "server_max_speed"};
    for (const char *field : fields) {
        if (!profile.has(field)) return out;
        const Variant value = profile[field];
        if (value.get_type() != Variant::FLOAT && value.get_type() != Variant::INT) return out;
        const double number = value;
        if (!std::isfinite(number) || number < 0) return out;
    }
    if (!profile.has("movement_allowed") || !profile.has("frozen") ||
        !std::isfinite(current) || current < 0 || !std::isfinite(input) ||
        !std::isfinite(delta) || delta < 0) return out;
    const double native_slope_angle = profile["slope_mod_angle_radians"];
    const double slope_percent = profile["slope_mod_percent"];
    // Core3 serializes a float; its representation of pi/2 is slightly above
    // the double constant. Accept that rounding without accepting bad angles.
    if (native_slope_angle > 1.570797 || slope_percent > 1 ||
        profile["movement_allowed"].get_type() != Variant::BOOL ||
        profile["frozen"].get_type() != Variant::BOOL) return out;
    const double slope_angle = std::min(native_slope_angle, 1.5707963267948966);
    const double scale = double(profile["speed_multiplier_base"]) * double(profile["speed_multiplier_mod"]);
    const double run = double(profile["run_speed"]) * scale;
    const double walk = double(profile["walk_speed"]) * scale;
    double modifier = 1.0;
    // PlayerCreatureController::computeTerrainMovementModifier: authored floors
    // bypass terrain penalties, swimming bypasses wading/slope, no hard slope cutoff.
    if (bool(environment.get("terrain", false)) && !bool(environment.get("swimming", false))) {
        if (bool(environment.get("below_water", false))) modifier = profile["water_mod_percent"];
        else {
            const double slope = environment.get("normal_dot_forward", 0.0);
            if (!std::isfinite(slope)) return out;
            const double threshold = -std::sin(slope_angle);
            if (slope < threshold && threshold > -1.0) {
                const double ratio = (std::clamp(slope, -1.0, 1.0) - threshold) / (-1.0 - threshold);
                modifier = 1.0 + (slope_percent - 1.0) * ratio;
            }
        }
    }
    double voluntary = 1.0;
    if (profile.has("controls")) {
        const Variant value = profile["controls"];
        if (value.get_type() != Variant::DICTIONARY) return out;
        const Dictionary controls = value;
        const Variant factor = controls.get("voluntary_scale", Variant());
        const Variant rooted = controls.get("rooted", Variant());
        if ((factor.get_type() != Variant::FLOAT && factor.get_type() != Variant::INT) || rooted.get_type() != Variant::BOOL) return out;
        voluntary = factor;
        if (!std::isfinite(voluntary) || voluntary < 0 || voluntary > 1) return out;
        if (bool(rooted)) voluntary = 0;
    }
    // Control effects affect intentional locomotion only. HMD/controller poses,
    // room-scale tracking, gravity and collision correction never enter this policy.
    const double desired = voluntary * (walking || run <= 0 ? walk : run) * std::clamp(input, 0.0, 1.0) * modifier;
    // CreatureObject::getMaximumAcceleration switches at effective walk speed.
    const double acceleration = double(profile[current <= walk ? "walk_acceleration" : "run_acceleration"])
        * double(profile["acceleration_multiplier_base"]) * double(profile["acceleration_multiplier_mod"]);
    if (!std::isfinite(desired) || !std::isfinite(acceleration)) return out;
    double speed = current < desired ? std::min(desired, current + acceleration * delta)
                                    : std::max(desired, current - acceleration * delta);
    const double server_cap = double(profile["server_max_speed"]) * voluntary;
    if (current < desired && server_cap > 0) speed = std::min(speed, server_cap);
    if (voluntary < 1.0) speed = std::min(speed, std::min((walking || run <= 0 ? walk : run) * voluntary, server_cap));
    if (!bool(profile["movement_allowed"]) || bool(profile["frozen"])) speed = 0;
    out["valid"] = true; out["speed"] = speed; out["desired_speed"] = desired;
    out["acceleration"] = acceleration; out["terrain_modifier"] = modifier;
    return out;
}
