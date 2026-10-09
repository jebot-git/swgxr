#pragma once
#include <algorithm>
#include <cmath>
#include <string>
#include "CoreCuPolicy.h"
namespace corecu { namespace grenade {
constexpr int TargetCap=6;
constexpr double FuseSeconds=2., AggregateMultiplier=2.5, Range=32.;
enum Control { None, Slow, Restrain };
struct Spec { const char* kind; double radius, damage, familyCooldown; Control control; int duration; double qualityLow,qualityHigh; };
inline Spec spec(const std::string& path){
 const std::string root="object/weapon/ranged/grenade/grenade_";
 if(path==root+"fragmentation_light.iff")return {"fragmentation_light",4,180,0,None,0,175,465};
 if(path==root+"fragmentation.iff")return {"fragmentation",5,360,0,None,0,300,873};
 if(path==root+"cryoban.iff")return {"cryoban",5,270,0,Slow,3,255,460};
 if(path==root+"glop.iff")return {"glop",4,240,0,Restrain,2,330,1060};
 if(path==root+"imperial_detonator.iff")return {"imperial",6,360,12,None,0,972.5,1494.5};
 if(path==root+"thermal_detonator.iff")return {"thermal",7,360,18,None,0,952,1280};
 if(path==root+"proton.iff")return {"proton",8,360,24,None,0,1611.5,2217};
 return {"",0,0,0,None,0,0,1};
}
inline bool supported(const std::string& path){return spec(path).radius>0;}
inline double progress(int thrownSpeed){return corecu::clamp(thrownSpeed/40.,0.,1.);}
inline double recovery(int thrownSpeed){return 12.-3.*progress(thrownSpeed);}
inline double potency(int thrownSpeed){return 80.+25.*progress(thrownSpeed);}
inline double chance(int thrownSpeed,double resistance){return corecu::learnedStatusChance(80, potency(thrownSpeed)-80, resistance);}
// Source recipe means map the complete crafting band to the same 140/245..1
// quality range as the equivalent T21. Original template defaults may fall
// below the recipe band; exceptional components cannot exceed its ceiling.
constexpr double MinimumQuality=140./245.;
inline double quality(const Spec& s,double minimum,double maximum){return MinimumQuality+(1.-MinimumQuality)*corecu::clamp(((minimum+maximum)*.5-s.qualityLow)/(s.qualityHigh-s.qualityLow),0,1);}
inline double packet(const Spec& s,int thrownSpeed,double q){return s.damage*(.8+.2*progress(thrownSpeed))*corecu::clamp(q,MinimumQuality,1.);}
inline double falloff(double distance,double radius){return radius>0 && distance>=0 && distance<=radius ? 1.-.65*distance/radius : 0.;}
inline double aggregateScale(double weights){return weights>AggregateMultiplier?AggregateMultiplier/weights:1.;}
inline bool due(long long now,long long at){return now>=at;}
inline bool expired(long long now,long long at){return now-at>10000;}
}}
