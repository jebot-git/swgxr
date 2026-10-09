#pragma once
#include <algorithm>
#include <cmath>
#include <string>
// SWGXR Doctor care tuning. Tier quality uses original crafted power intervals.
namespace corecu { namespace doctorcare {
inline int stage(int value){return std::max(0,std::min(6,value));}
inline double multiplier(int value){return 1.+.05*stage(value);}
inline double emergencyMultiplier(int value){return 1.+.025*stage(value);}
inline double woundMultiplier(int value){return 1.+.10*std::min(5,stage(value));}
inline int scaled(int amount,double factor){return amount<=0?amount:int(std::min(1073741823.,std::round(amount*factor)));}
inline int potency(int amount,int value){return scaled(amount,multiplier(value));}
inline int emergencyPotency(int amount,int value){return scaled(amount,emergencyMultiplier(value));}
inline int woundPotency(int amount,int value){return scaled(amount,woundMultiplier(value));}
inline int stimTier(const std::string& path){
 static const char* paths[]={"object/tangible/medicine/crafted/crafted_stimpack_sm_s1_a.iff","object/tangible/medicine/crafted/crafted_stimpack_sm_s1_b.iff","object/tangible/medicine/crafted/crafted_stimpack_sm_s1_c.iff","object/tangible/medicine/crafted/crafted_stimpack_sm_s1_d.iff","object/tangible/medicine/crafted/crafted_stimpack_sm_s1_e.iff"};
 for(int i=0;i<5;++i)if(path==paths[i])return i;
 return -1; // Legacy non-tier supplies retain explicit normalized-injury fallback.
}
inline double stimQuality(int tier,double effectiveness){
 if(tier<0 || tier>4 || !std::isfinite(effectiveness))return 0.;
 static const double low[]={75,75,100,150,200},high[]={100,200,400,700,1000};
 return std::max(0.,std::min(1.,(effectiveness-low[tier])/(high[tier]-low[tier])));
}
inline int stim(int maximum,int tier,double effectiveness,double proficiency){
 if(tier<0 || tier>4)return 0;
 double quality=stimQuality(tier,effectiveness),skill=std::isfinite(proficiency)?std::max(0.,std::min(1.,proficiency/100.)):0.;
 return std::max(1,int(std::round(std::max(1,maximum)*(.10+.03*tier+.04*quality)*(.75+.25*skill))));
}
inline int grogginess(int base){return -std::max(1,int(std::round(std::max(1,base)*.05)));}
} }
