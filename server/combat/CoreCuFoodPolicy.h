#pragma once
#include <algorithm>
#include <cmath>
// Local CU-inspired food balance. Preserve crafted quality and native duration/filling.
namespace corecu { namespace food {
inline int attribute(int base,double legacy){return int(std::round(std::max(1,base)*std::max(-.10,std::min(.10,legacy/10000.))));}
inline int skill(double legacy){return int(std::round(std::max(-20.,std::min(20.,legacy))));}
inline double instant(double legacy){return std::max(0.,std::min(20.,legacy));}
inline int restore(int maximum,double legacy){return std::max(0,int(std::round(std::max(1,maximum)*std::max(0.,std::min(.15,legacy/4000.)))));}
inline bool withinBudget(int base,int existing,int added){return added<=0 || existing+added<=int(std::floor(std::max(1,base)*.20));}
constexpr int RESTORE_RECOVERY_MS=30000;
}}
