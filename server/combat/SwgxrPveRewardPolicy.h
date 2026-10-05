#ifndef SWGXR_PVE_REWARD_POLICY_H
#define SWGXR_PVE_REWARD_POLICY_H
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <limits>
// Pure arithmetic shared by all native ground-PvE damage/death paths.
// Threat/aggro alone, forecast DOT damage and overkill are not contributions.
namespace SwgxrPveRewardPolicy {
inline std::uint32_t hamDamage(int current, double requested, bool available, bool destroy, bool avoidIncapacitation, bool secondary) {
 if (!available || current<=0 || !std::isfinite(requested) || requested<=0) return 0;
 auto debit=std::int64_t(std::min(std::floor(requested),double(std::numeric_limits<int>::max())));
 auto after=std::int64_t(current)-debit;
 if ((!destroy || avoidIncapacitation) && after<=0) after=1;
 if (secondary && after<0) after=0;
 return std::uint32_t(std::max<std::int64_t>(0,std::int64_t(current)-std::max<std::int64_t>(0,after)));
}
inline std::uint32_t conditionDamage(int condition,int maximum,double requested,bool destroy) {
 if (maximum<=0 || condition>=maximum || !std::isfinite(requested) || requested<=0) return 0;
 double ceiling=destroy?maximum:maximum-1;
 double after=std::min(ceiling,double(condition)+requested);
 return std::uint32_t(std::max(0.0,std::floor(after)-condition));
}
inline std::uint64_t accumulate(std::uint64_t previous,std::uint64_t damage) {
 return damage>std::numeric_limits<std::uint64_t>::max()-previous?std::numeric_limits<std::uint64_t>::max():previous+damage;
}
inline double fraction(std::uint64_t credited,std::uint64_t allActualDamage) {
 return allActualDamage?std::min(1.0,double(credited)/double(allActualDamage)):0.0;
}
inline double cappedShare(double fullReward,double fullKillCap,std::uint64_t credited,std::uint64_t allActualDamage) {
 return std::max(0.0,std::min(fullReward,fullKillCap))*fraction(credited,allActualDamage);
}
inline std::uint64_t lootOwner(std::uint64_t playerKiller,std::uint64_t petOwner,std::uint64_t victim) {
 // A NPC/environment kill is owned by its corpse, never owner0/public/group0.
 return playerKiller?playerKiller:petOwner?petOwner:victim;
}
}
#endif
