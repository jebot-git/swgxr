#pragma once
#include <algorithm>
#include <cmath>
#include <string>
#include "DoctorPolicy.h"
// First CU-inspired medical/resource pass; explicit local tuning, not SOE formulas.
namespace corecu {
namespace medicine {
struct Ability { double action, mind; int recovery; const char* group; };
inline Ability ability(const std::string& name) {
 if(name=="healdamage")return {.06,.08,6000,"injury"};
 if(name=="healpet" || name=="healdroiddamage")return {.02,.03,6000,"injury"};
 if(name=="tenddamage")return {.04,.06,8000,"injury"};
 if(name=="quickheal")return {.10,.15,30000,"emergency"};
 if(name=="healmind")return {.06,.10,15000,"resource"};
 if(name=="healwound" || name=="healdroidwound")return {.02,.04,5000,"wound"};
 // Wounds are treated by an explicitly selected Wound Medpack, not Tend Wound.
 if(name=="firstaid")return {.01,.01,4000,"bleed"};
 if(name=="healenhance")return {.03,.05,5000,"enhance"};
 if(name=="reviveplayer")return {.08,.12,60000,"revive"};
 if(name=="healstate" || name=="curepoison" || name=="curedisease" || name=="extinguishfire")return {.02,.03,6000,"cure"};
 return {0,0,0,""};
}
inline bool retired(const std::string& name){return name=="diagnose" || name=="healwound" || name=="tendwound" || name=="healWound" || name=="tendWound";}
// Retain template registration for saved objects, but retire obsolete supplies and recipes.
inline bool retiredMedicalTemplate(const std::string& path){
 if(corecu::doctor::retiredRecipe(path))return true;
 auto pos=path.rfind('/');auto name=path.substr(pos==std::string::npos?0:pos+1);
 if(name.compare(0,7,"shared_")==0)name=name.substr(7);
 // Empty legacy droid medicine placeholders; working repair kits and pet vitality packs remain.
 for(auto dummy:{"droid_stimpack_a","droid_stimpack_b","droid_stimpack_c","droid_stimpack_d","droid_vitapack_a","droid_vitapack_b","droid_vitapack_c"})if(name==std::string(dummy)+".iff")return true;
 if(path.find("draft_schematic/chemistry/")!=std::string::npos){
  for(auto dummy:{"antidote_sm_s1","med_stimpack_state_blinded_b","med_stimpack_state_dizzy_b","med_stimpack_state_intimidated_b","med_stimpack_state_stunned_b","medic_damage","medikit_advanced","medikit_basic","medpack_damage","medpack_sm_s1","medpack_wound","medpack_wound_health","stimpack_sm_s1"})if(name==std::string(dummy)+".iff")return true;
 }
 for(auto family:{"medpack_wound_","medpack_poison_","medpack_disease_"}){
  std::string prefix=family;if(name.compare(0,prefix.size(),prefix)!=0)continue;
  auto stat=name.substr(prefix.size());if(stat.compare(0,5,"area_")==0)stat=stat.substr(5);
  auto end=stat.find_first_of("_.");stat=stat.substr(0,end);
  return stat!=(prefix=="medpack_disease_"?"action":"health");
 }
 return false;
}
inline int revive(int maximum,int power){return std::max(1,int(std::round(std::max(1,maximum)*std::max(.10,std::min(.25,power/4000.)))));}
inline bool woundAttribute(bool player,int attribute){return !player || attribute==0;}
inline int diseaseDrain(int base,int requested){return std::max(0,std::min(requested,std::max(1,base/20)));}
inline double fraction(double skill){return std::max(0.,std::min(1.,skill/100.));}
inline int cost(int base,double rate){return rate<=0?0:std::max(1,int(std::ceil(std::max(1,base)*rate)));}
inline int injury(int maximum,double skill,double quality){return std::max(1,int(std::round(std::max(1,maximum)*(.12+.10*fraction(skill))*std::max(.75,std::min(1.25,quality)))));}
inline int tend(int maximum,double skill){return std::max(1,int(std::round(std::max(1,maximum)*(.04+.03*fraction(skill)))));}
inline int emergency(int maximum,double skill){return std::max(1,int(std::round(std::max(1,maximum)*(.30+.10*fraction(skill)))));}
inline int enhancement(int base,int requested){return std::max(0,std::min(requested,int(std::floor(std::max(1,base)*.15))));}
inline int wound(int base,int requested){return std::max(0,std::min(requested,std::max(1,base/10)));}
inline int recovery(int base,double speed){return int(std::ceil(base*(1.-.25*fraction(speed))));}
inline double regeneration(double secondary,double base){return 1.+std::max(-.25,std::min(.25,secondary/std::max(1.,base)-1.));}
inline int woundPack(int base,double skill,double quality){return std::max(1,int(std::round(std::max(1,base)*std::min(.10,(.03+.05*fraction(skill))*std::max(.75,std::min(1.25,quality))))));}
inline int spiceHam(int base,int legacy){return int(std::round(std::max(1,base)*std::max(-.25,std::min(.25,legacy/4000.))));}
inline int spiceHealing(int amount){return amount<=0?amount:int(std::min(1073741823.,std::round(amount*1.5)));}
inline double costAdjustment(double secondary,double base){return base<=0?0:base*(1.-.25*std::max(0.,std::min(1.,(secondary-300.)/300.)));}
}
}
