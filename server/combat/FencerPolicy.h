#pragma once
#include "CoreCuPolicy.h"
namespace corecu { namespace fencer {
struct Ability {const char* label;const char* skill;double damage,cooldown,recovery;int action,mind,blows;bool gesture,ultimate,control;};
inline Ability ability(const std::string& id){
 if(id=="arterial_cut")return {"Arterial Cut","combat_1hsword_novice",1,12,1.2,65,25,1,false,false,false};
 if(id=="nerve_strike")return {"Nerve Strike","combat_1hsword_ability_02",.65,15,1.2,55,25,1,false,false,false};
 if(id=="disorienting_thrust")return {"Disorienting Thrust","combat_1hsword_ability_03",.6,18,1.2,60,30,1,false,false,true};
 if(id=="exposing_thrust")return {"Exposing Thrust","combat_1hsword_support_04",.6,16,1.2,65,35,1,false,false,false};
 if(id=="probing_jabs")return {"Probing Jabs","combat_1hsword_novice",.35,8,1.2,45,15,2,true,false,false};
 if(id=="raking_slash")return {"Raking Slash","combat_1hsword_support_02",.7,10,1.2,55,20,1,true,false,false};
 if(id=="guard_bash")return {"Guard Bash","combat_1hsword_speed_02",.4,14,1.2,50,25,1,true,false,true};
 if(id=="flawless_assault")return {"Flawless Assault","combat_1hsword_master",0,120,1,120,80,0,false,true,false};
 return {"","",0,0,0,0,0,0,false,false,false};
}
inline double progression(double trained){return clamp((trained-.1)/.9,0,1);}
inline double bleedScale(double progress,bool flawless){return flawless?1.:.5+.3*clamp(progress,0,1);}
inline double chance(double rating,double progress,bool precision,bool flawless){return learnedStatusChance(95,5+5*clamp(progress,0,1)+(flawless?10:precision?5:0),rating);}
inline int softDuration(int base,double progress){return int(std::ceil(base*(1+.25*clamp(progress,0,1))));}
inline double exposed(double rating,int status,bool active){return active && (status==Bleed || status==Blind || status==Intimidate || status==Snare)?std::max(0.,rating-20):rating;}
inline int refreshBudget(int remaining,int incoming){return std::max(std::max(0,remaining),std::max(0,incoming));}
inline int spendTick(int& remaining,int strength){int spent=std::min(std::max(0,remaining),std::max(0,strength));remaining-=spent;return spent;}
constexpr int BleedDuration=12, BleedInterval=3, PrecisionSeconds=6, UltimateSeconds=12;
}}
