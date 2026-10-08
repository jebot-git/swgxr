#ifndef SWGXR_SAMPLING_POLICY_H
#define SWGXR_SAMPLING_POLICY_H
#include <algorithm>
#include <cstdint>
#include <string>

// Pure native policy, shared by Core3 settlement and deterministic offline tests.
// The caller supplies ResourceContainer::MAXSIZE and the original RNG.
namespace swgxr_sampling {
struct Result { int units = 0; int xp = 0; };

template<class Json>
void pause(Json& dep, const char* reason) {
    dep["state"] = reason;
    dep["sample_status"] = reason;
    dep["settlement_pending"] = false;
    dep["last_sample_units"] = 0;
}

template<class Json, class Random>
Result advance(Json& dep, int64_t now, int64_t expires, int capacity,
               int& budget, Random random) {
    Result result;
    const int64_t quantity = dep.value("quantity", int64_t(0));
    // Legacy excess remains recoverable; it never grants additional output/XP.
    if (quantity >= capacity) { pause(dep, "full"); return result; }
    const int64_t end = std::min(now, expires);
    int64_t next = dep.at("next_sample_at_unix").template get<int64_t>();
    const float density = dep.at("density").template get<float>();
    const int skill = dep.at("surveying_skill").template get<int>();
    while (next <= end && budget > 0 && quantity + result.units < capacity) {
        --budget;
        next += 25;
        dep["cycles"] = dep.value("cycles", int64_t(0)) + 1;
        dep["last_sample_units"] = 0;
        dep["last_sample_at_unix"] = next - 25;
        if (density < .10f || density * 100 < (32 - (skill / 20) * 6)) {
            dep["sample_status"] = "density_below_threshold"; continue;
        }
        const float rate = skill * density + random(100) + dep.template value<int>("sample_rate_modifier", 0);
        if (rate < 40) { dep["sample_status"] = "sample_failed"; continue; }
        const int maximum = int(density * (25 + random(3)));
        const float city = 1.f + dep.template value<int>("sample_size_modifier", 0) / 100.f;
        const int rolled = maximum * (float(skill) / 100.f) * city;
        if (rolled < 2) { dep["sample_status"] = "trace_amount"; continue; }
        const int units = int(std::min<int64_t>(rolled, capacity - quantity - result.units));
        dep["last_sample_units"] = units;
        dep["sample_status"] = "sample_located";
        result.units += units;
        result.xp += int(float(units) / float(maximum) * 40);
        dep["successful_cycles"] = dep.value("successful_cycles", int64_t(0)) + 1;
    }
    dep["next_sample_at_unix"] = next;
    dep["quantity"] = quantity + result.units;
    dep["awarded_xp"] = dep.value("awarded_xp", int64_t(0)) + result.xp;
    if (quantity + result.units >= capacity) {
        // Keep the final accepted yield visible, with no outstanding catch-up.
        dep["state"] = "full";
        dep["sample_status"] = "full";
        dep["settlement_pending"] = false;
    } else {
        const bool pending = next <= end;
        dep["settlement_pending"] = pending;
        dep["state"] = pending ? "settling" : now >= expires ? "expired" : "sampling";
    }
    return result;
}
}
#endif
