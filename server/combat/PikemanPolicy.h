#pragma once
#include "CoreCuPolicy.h"
#include "TkaPolicy.h"
namespace corecu { namespace pikeman {
enum Effect { Knockdown, Stun, Slow, Delay };
struct Ability {const char* label;const char* skill;double damage,cooldown,recovery,cosine;int action,mind,targets,blows,duration,slow;Effect effect;bool gesture,ultimate;};
inline Ability ability(const std::string& id){
 if(id=="knockdown_strike")return {"Unbalancing Thrust","combat_polearm_novice",.9,20,1.5,.5,70,30,1,1,2,0,Knockdown,false,false};
 if(id=="polearm_stun")return {"Concussive Strike","combat_polearm_accuracy_01",.9,18,1.5,.5,65,30,1,1,4,0,Stun,false,false};
 if(id=="pinning_strike")return {"Pinning Strike","combat_polearm_speed_01",.6,16,1.5,.5,60,25,1,1,5,40,Slow,false,false};
 if(id=="disrupting_jab")return {"Disrupting Jab","combat_polearm_support_01",.6,15,1.5,.5,60,30,1,1,2,0,Delay,false,false};
 if(id=="overhead_whirl")return {"Overhead Whirl","combat_polearm_novice",.75,16,1.75,-1,90,35,4,1,2,0,Stun,true,false};
 if(id=="sweeping_trip")return {"Sweeping Trip","combat_polearm_ability_01",.5,22,1.75,0,95,40,3,1,2,0,Knockdown,true,false};
 if(id=="driving_jabs")return {"Driving Jabs","combat_polearm_novice",.35,10,1.5,.939692620786,65,25,2,2,3,30,Slow,true,false};
 if(id=="whirlwind")return {"Whirlwind","combat_polearm_master",1,120,2,-1,150,80,6,1,3,0,Knockdown,false,true};
 return {"","",0,0,0,1,0,0,0,0,0,0,Slow,false,false};
}
inline bool hard(const Ability& a){return a.effect!=Slow;}
inline bool targeted(const Ability& a){return !a.gesture && !a.ultimate;}
inline bool ready(const Ability& a,bool recovery){return !targeted(a) || !hard(a) || recovery;}
inline double chance(double rating,double trained){return learnedStatusChance(90,5+5*clamp((trained-.1)/.9,0,1),rating);}
inline int strongestSlow(int a,int b,int c,int d){return std::min(100,std::max(0,std::max(std::max(a,b),std::max(c,d))));}
inline std::string cooldownKey(const std::string& id){return ((id=="knockdown_strike" || id=="polearm_stun")?"corecu_brawler_":"corecu_pikeman_")+id;}
}}
