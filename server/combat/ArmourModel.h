#pragma once
#include <algorithm>
#include <cmath>

// Pure, versioned SWGXR arithmetic. Inputs are immutable native item statistics.
namespace swgxr { namespace armour {
constexpr int VERSION = 1;
enum Channel { Kinetic=1, Energy=2, Blast=4, Stun=8, Saber=16,
               Heat=32, Cold=64, Acid=128, Electricity=256 };
inline double bound(double v, double lo, double hi) {
    return std::isfinite(v) ? std::max(lo, std::min(hi, v)) : lo;
}
inline double quality(double raw, double low, double high) {
    return high > low ? bound((raw-low)/(high-low), 0, 1) : 0.5;
}
inline double reduction(double score) { // 2000/4000/6000 -> 1.25/1.5/1.75 EHP
    const double multiplier = 1 + bound(score, 0, 8000)/8000;
    return 1-1/multiplier;
}
struct ArmourReference {
    const char* path;
    int kind; // 0 Battle, 1 Recon, 2 Assault; independent of original AR.
    double minimum, maximum, specialMinimum, specialMaximum;
    double encumbranceBest, encumbranceWorst;
};
inline double baseScore(const ArmourReference& ref, double raw, double fallback) {
    if (raw <= 0) return 1000+5000*bound(fallback/80, 0, 1);
    // Exceptional components retain bounded credit above ordinary recipe bounds.
    const double excess = std::max(0.0,raw-ref.maximum)*40;
    return std::min(7000.0,1000+5000*quality(raw,ref.minimum,ref.maximum)+excess);
}
inline int canonical(int type) {
    return type==Blast ? Kinetic : (type==Stun || type==Saber) ? Energy : type;
}
inline double score(const ArmourReference& ref, int channel, double base,
                    double specialDelta, double layer, double slice) {
    channel=canonical(channel);
    double bias=0;
    if (ref.kind && (channel==Kinetic || channel==Energy))
        bias=((channel==Energy)==(ref.kind==1))?1000:-1000;
    return bound((base+bias+bound(specialDelta,-1000,1000)+bound(layer*40,-1500,1500))
                 *bound(slice,1,2),0,8000);
}
struct WeaponProfile {
    int base=Kinetic, element=Heat;
    double fraction=0, bypass=0, damageScale=1;
};
inline WeaponProfile weapon(int originalType, int ap, bool broken=false) {
    WeaponProfile out;
    const double budgets[]={0,.05,.10,.20};
    const double budget=budgets[int(bound(broken?0:ap,0,3))];
    out.base=canonical(originalType);
    if (originalType==Heat || originalType==Cold || originalType==Acid || originalType==Electricity) {
        out.base=(originalType==Cold || originalType==Acid)?Kinetic:Energy;
        out.element=originalType; out.fraction=.20;
    } else if (originalType==Blast || originalType==Stun || originalType==Saber) {
        out.element=originalType==Stun?Electricity:Heat; out.fraction=.20;
    } else if (budget>0) {
        out.element=originalType==Kinetic?Electricity:Heat;
        out.fraction=std::min(.10,budget*.5);
    }
    out.bypass=out.fraction>0?budget*.5:budget;
    // Worst case: 50% base resistance, no elemental resistance. Split and
    // bypass together cannot exceed this grade's original proposed budget.
    out.damageScale=std::min(1.0,(1+budget)/(1+out.fraction+out.bypass*(1-out.fraction)));
    return out;
}
inline double remaining(double resistance, double bypass) {
    return 1-bound(resistance,0,.5)*(1-bound(bypass,0,.2));
}
struct Damage {
    WeaponProfile profile;
    double base, element;
    Damage(double raw, WeaponProfile p):profile(p),base(raw*p.damageScale*(1-p.fraction)),element(raw*p.damageScale*p.fraction) {}
    double total() const {return base+element;}
    void mitigate(double baseResistance, double elementResistance) {
        base*=remaining(baseResistance,profile.bypass);
        element*=remaining(elementResistance,profile.bypass);
    }
};
struct Penalties {double movement=1, output=1, recovery=1;};
inline Penalties penalties(int kind,double base,double encumbranceQuality,double training) {
    const double tier=bound(base/6000,0,1);
    const double qualityScale=1-.25*bound(encumbranceQuality,0,1);
    // Training mitigates half, preserving a cost even at mastery.
    const double scale=tier*qualityScale*(1-.5*bound(training,0,1));
    return {1-(kind==1?.06:kind==2?.18:.12)*scale,
            1-(kind==1?.18:kind==2?.06:.12)*scale,
            1-.12*scale};
}
} }
