#include "WeaponCraftingReferences.h"
#include <cassert>
#include <iostream>
#include <limits>

int main() {
    int checks = 0;
    for (const auto& ref : swgxr::REFERENCES) {
        const auto normal = swgxr::resolve(ref, ref.delay, ref.health, ref.action, ref.mind);
        assert(normal.valid && normal.rpm == ref.rpm && normal.capacity == ref.capacity && normal.stanceRecovery == ref.stanceRecovery && normal.power == ref.power); ++checks;
        double previousRpm = 0, previousRecovery = 0, previousPower = 0;
        for (int quality = 0; quality <= 100; ++quality) {
            const double factor = 1.5 - quality * 0.01;
            auto value = swgxr::resolve(ref, ref.delay * factor, ref.health * factor, ref.action * factor, ref.mind * factor);
            assert(value.valid && value.rpm >= previousRpm && value.stanceRecovery >= previousRecovery && value.power >= previousPower);
            assert(value.stanceRecovery <= ref.stanceRecovery*1.5 && value.power <= ref.power*2);
            assert(!ref.melee || (value.rpm == 0 && value.capacity == 0 && value.stanceRecovery > 0 && value.power > 0));
            assert(value.rpm <= ref.rpm * 1.5 && value.capacity <= ref.capacity * 2);
            previousRpm = value.rpm; previousRecovery = value.stanceRecovery; previousPower = value.power; ++checks;
        }
        for (double bad : {0.0, -1.0, std::numeric_limits<double>::infinity(), std::numeric_limits<double>::quiet_NaN()}) {
            assert(!swgxr::resolve(ref,bad,1,1,1).valid); ++checks;
        }
        assert(!swgxr::resolve(ref,ref.delay,-1,1,1).valid); ++checks;
        assert(swgxr::resolve(ref,ref.delay,0,0,0).capacity == ref.capacity*2);
        assert(swgxr::resolve(ref,ref.delay,0,0,0).power == ref.power*2); ++checks;
        assert(!swgxr::resolve(ref,ref.delay,std::numeric_limits<double>::quiet_NaN(),1,1).valid); ++checks;
    }
    const auto& cdef = swgxr::REFERENCES[0];
    const auto good = swgxr::resolve(cdef,3.2,7,15,7);
    const auto poor = swgxr::resolve(cdef,4.6,10,22,10);
    assert(std::abs(good.rpm-262.5)<0.0001 && good.capacity==14);
    assert(std::abs(poor.rpm-182.60869565)<0.0001 && poor.capacity==10);
    // A speed-affecting component must not alter capacity, or vice versa.
    assert(swgxr::resolve(cdef,3.0,10,15,10).capacity==12);
    assert(swgxr::resolve(cdef,3.5,5,10,5).rpm==240);
    std::cout << "CRAFTING_PROFILE_PASS " << checks+4 << " checks\n";
}
