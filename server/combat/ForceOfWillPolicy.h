#pragma once
#include <algorithm>
#include <cstdint>
namespace corecu { namespace forceofwill {
constexpr int CooldownSeconds=600;
constexpr double HealthFraction=.15;
inline int recoveredHealth(int current,int maximum,int wounds) {
 const int effective=std::max(1,maximum-std::max(0,wounds));
 const int floor=int((int64_t(effective)*15+99)/100);
 return std::min(effective,std::max(current,floor));
}
inline bool eligible(bool learned,bool unarmed,bool incapacitated,bool dead,bool feigning,bool cloning,bool pinned,bool recoveryPending) {
 return learned && unarmed && incapacitated && !dead && !feigning && !cloning && !pinned && recoveryPending;
}
inline double remaining(uint64_t deadline,uint64_t now){return deadline>now?(deadline-now)/1000.:0.;}
}}
