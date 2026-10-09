#pragma once
#include "CoreCuPolicy.h"

// Authored CoreCU supply effects. Legacy item values are quality inputs, not
// unbounded damage, duration or application chances.
namespace corecu { namespace combatmedic {
inline double skill(double value){return clamp(value/100.,0,1);}
inline double progress(double value){return clamp((value-5.)/95.,0,1);}
inline double applicationQuality(double potency){return clamp((potency-25.)/125.,0,1);}
inline double strengthQuality(double power,bool disease){return .8+.2*clamp(power/(disease?60.:300.),0,1);}
inline double rawPotency(double effectiveness,double quality){return 95+20*skill(effectiveness)+10*clamp(quality,0,1);}
inline double chance(double raw,double rating){return learnedStatusChance(95,clamp(raw-95,0,30),rating);}
inline double durationQuality(bool disease,double rawDuration){return .75+.25*clamp(rawDuration/(disease?1000.:240.),0,1);}
inline int duration(bool disease,double effectiveness,double rawDuration){return int(std::ceil((disease?18:16)*durationQuality(disease,rawDuration)*(1+.30*progress(effectiveness))));}
inline int interval(bool disease){return disease?3:4;}
inline int pulseCount(int seconds,int period){return std::max(1,int(std::ceil((std::max(1,seconds)-1.5)/std::max(1,period))));}
inline int pulse(int budget,int seconds,int period){return std::max(1,int(std::ceil(double(std::max(1,budget))/pulseCount(seconds,period))));}
inline int poisonBudget(int targetHealth,int healerHealth,double effectiveness,double power,bool area,double rawDuration=240){
 const double basis=std::max(1.,std::min(double(targetHealth),4.*std::max(1,healerHealth)));
 return std::max(1,int(std::floor(basis*(.08+.04*progress(effectiveness))*strengthQuality(power,false)*durationQuality(false,rawDuration)*(area?.75:1.))));
}
inline int diseasePulse(int targetAction,double effectiveness,double power,bool area){return std::max(1,int(std::floor(std::max(1,targetAction)*(.03+.02*progress(effectiveness))*strengthQuality(power,true)*(area?.75:1.))));}
inline double range(double raw,double rangeSkill){return clamp(raw,0,40)+14*skill(rangeSkill);}
inline double radius(double raw){return clamp(raw,0,8);}
inline int recovery(double speed,double food=0,double spice=1){return int(std::ceil((8000-2000*progress(speed))*(1-clamp(food,0,20)/100.)*clamp(spice,.5,2)));}
inline int cost(int base,double fraction){return std::max(1,int(std::ceil(std::max(1,base)*fraction)));}
constexpr int TargetCap=6;
}}
