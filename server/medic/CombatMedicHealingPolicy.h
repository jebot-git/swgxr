#pragma once
#include "CoreCuPolicy.h"
#include <string>
namespace corecu { namespace combatmedichealing {
struct Stim {int tier;bool area;};
inline Stim stim(const std::string& path){
 const std::string prefix="object/tangible/medicine/crafted/medpack_grenade_";
 for(int i=0;i<5;++i)if(path==prefix+"damage_"+char('a'+i)+".iff")return {i,false};
 for(int i=0;i<3;++i)if(path==prefix+"area_"+char('a'+i)+".iff")return {i,true};
 return {-1,false};
}
inline double proficiency(double skill){return .75+.25*clamp(skill/100.,0,1);}
inline double quality(Stim pack,double power){
 if(pack.tier<0 || pack.tier>(pack.area?2:4))return 0;
 const double low[]={75,75,100,150,200},high[]={150,300,500,700,1000};
 return pack.area?clamp((power-100.)/(200.+200.*pack.tier),0,1):clamp((power-low[pack.tier])/(high[pack.tier]-low[pack.tier]),0,1);
}
inline double fraction(Stim pack,double power,double skill){
 if(pack.tier<0 || pack.tier>(pack.area?2:4))return 0;
 double base=pack.area?.06+.02*pack.tier:.10+.03*pack.tier;
 return (base+(pack.area?.02:.04)*quality(pack,power))*proficiency(skill);
}
inline int heal(int maximum,Stim pack,double power,double skill){return int(std::round(std::max(1,maximum)*fraction(pack,power,skill)+1e-8));}
inline int mindCapacity(int maximum,double skill){return int(std::round(std::max(1,maximum)*(.12+.10*clamp(skill/100.,0,1))));}
inline int transferLimit(int capacity,int missing,int healerMind){return std::max(0,std::min({capacity,missing,healerMind-1}));}
// Native healing spice rounds 1.5x; choose an input whose final output fits the
// transfer cap and available Mind, including a one-point remainder.
inline int transferInput(int limit,bool boosted){return boosted?int(std::floor(std::max(0,limit)/1.5)):std::max(0,limit);}
constexpr int AreaTargetCap=5;
} }
