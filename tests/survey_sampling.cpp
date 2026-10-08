#include "../vendor/Core3/MMOCoreORB/utils/engine3/MMOEngine/src/engine/util/json.hpp"
#include "../server/gathering/SwgxrSamplingPolicy.h"
#include <cassert>
#include <iostream>
using Json = nlohmann::json;
static Json fresh() {
    return {{"quantity",0},{"next_sample_at_unix",1003},{"density",1.0},
            {"surveying_skill",100},{"sample_rate_modifier",0},{"sample_size_modifier",0}};
}
int main() {
    auto rng=[](int maximum){return maximum;};
    const int capacity=100000;
    int budget=1024;
    auto online=fresh();
    assert(swgxr_sampling::advance(online,1002,999999,capacity,budget,rng).units==0);
    assert(swgxr_sampling::advance(online,1003,999999,capacity,budget,rng).units==28);
    assert(swgxr_sampling::advance(online,1027,999999,capacity,budget,rng).units==0);
    assert(swgxr_sampling::advance(online,1028,999999,capacity,budget,rng).units==28);

    // The actual settlement routine gives identical results across a serialized
    // offline/restart gap and regular online polling, including original expiry.
    online=fresh();
    for(int64_t now=1000;now<=51000;++now) {
        budget=1024; swgxr_sampling::advance(online,now,50000,capacity,budget,rng);
    }
    auto offline=Json::parse(fresh().dump());
    do { budget=1024;swgxr_sampling::advance(offline,51000,50000,capacity,budget,rng);
         offline=Json::parse(offline.dump());
    } while(offline["settlement_pending"].get<bool>());
    assert(offline["quantity"]==online["quantity"]);
    assert(offline["cycles"]==online["cycles"]);
    assert(offline["awarded_xp"]==online["awarded_xp"]);
    assert(offline["state"]=="expired");

    // One free unit accepts precisely one, even though a normal successful
    // roll needs at least two. XP and depletion reflect accepted output only.
    auto final=fresh();final["quantity"]=capacity-1;budget=1024;
    auto accepted=swgxr_sampling::advance(final,999999,999999,capacity,budget,rng);
    assert(accepted.units==1 && accepted.xp==1 && budget==1023);
    assert(final["quantity"]==capacity && final["state"]=="full");
    assert(final["settlement_pending"]==false && final["last_sample_units"]==1);
    auto saved=Json::parse(final.dump());int calls=0;budget=1024;
    accepted=swgxr_sampling::advance(saved,9999999,999999,capacity,budget,[&](int){++calls;return 0;});
    assert(accepted.units==0 && accepted.xp==0 && calls==0 && budget==1024);
    assert(saved["quantity"]==capacity && saved["state"]=="full");
    assert(saved["cycles"]==final["cycles"] && saved["awarded_xp"]==final["awarded_xp"]);

    auto longOffline=fresh();
    do {budget=1024;swgxr_sampling::advance(longOffline,9999999,9999999,capacity,budget,rng);}
    while(longOffline["settlement_pending"].get<bool>());
    assert(longOffline["quantity"]==capacity && longOffline["state"]=="full");
    assert(longOffline["cycles"]==3572);
    auto legacy=fresh();legacy["quantity"]=capacity+50;budget=1024;
    accepted=swgxr_sampling::advance(legacy,999999,999999,capacity,budget,rng);
    assert(legacy["quantity"]==capacity+50 && accepted.units==0 && legacy["state"]=="full");
    auto poor=fresh();poor["density"]=.01;budget=1024;
    accepted=swgxr_sampling::advance(poor,999999,999999,capacity,budget,rng);
    assert(accepted.units==0 && accepted.xp==0 && poor["cycles"]==1024);
    assert(poor["settlement_pending"]==true && budget==0);
    swgxr_sampling::pause(poor,"duplicate_type");
    assert(poor["settlement_pending"]==false && poor["state"]=="duplicate_type");
    std::cout << "Survey sampling: cadence, offline serialization, expiry, bounded catch-up, exact cap, XP and legacy recovery passed\n";
}
