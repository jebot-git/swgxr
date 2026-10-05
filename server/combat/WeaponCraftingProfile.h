#pragma once
#include <algorithm>
#include <cmath>

// SWGXR crafting conversion. Pure calculation: no persistence, skill modifiers,
// slicing, powerups, condition penalties or ammunition refill side effects.
namespace swgxr {
struct Reference {
    const char* id;
    const char* templateName;
    double rpm;
    int capacity;
    double delay;
    double health, action, mind;
    bool melee = false;
    double stanceRecovery = 0, power = 0;
};
struct Profile {
    bool valid = false;
    double rpm = 0, rpmModifier = 0, capacityModifier = 0;
    int capacity = 0;
    double stanceRecovery = 0, power = 0;
};
inline Profile resolve(const Reference& ref, double delay, double health, double action,
                       double mind, double rpmMin, double rpmMax, double capMin, double capMax) {
    Profile result;
    const double total = health + action + mind;
    const double referenceCost = ref.health + ref.action + ref.mind;
    if (!std::isfinite(delay) || delay <= 0 || !std::isfinite(total) ||
        health < 0 || action < 0 || mind < 0 || ref.delay <= 0 ||
        referenceCost <= 0 || (ref.melee ? (ref.stanceRecovery <= 0 || ref.power <= 0) : (ref.rpm <= 0 || ref.capacity < 1)))
        return result;
    result.rpmModifier = std::max(rpmMin, std::min(rpmMax, ref.delay / delay));
    result.capacityModifier = total == 0 ? capMax : std::max(capMin, std::min(capMax, referenceCost / total));
    result.stanceRecovery = ref.stanceRecovery * result.rpmModifier;
    result.power = ref.power * result.capacityModifier;
    result.rpm = ref.rpm * result.rpmModifier;
    result.capacity = ref.melee ? 0 : std::max(1, static_cast<int>(std::floor(ref.capacity * result.capacityModifier + 0.5)));
    result.valid = true;
    return result;
}
}
