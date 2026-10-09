#pragma once
#include "CoreCuPolicy.h"
#include "PistoleerPolicy.h"
namespace corecu { namespace carbineer {
enum Effect { None, Slow, Stun, Knockdown };
struct Ability {const char* label;const char* grant;double damage,range,cosine,recovery;int action,mind,cooldown,targets,duration,slow;Effect effect;bool gesture,ultimate;};
inline Ability ability(const std::string& id){
 if(id=="crippling_shot")return {"Crippling Shot","cripplingShot",.6,0,1,0,55,20,16,1,6,40,Slow,false,false};
 if(id=="wild_shot")return {"Wild Shot","wildShot1",.7,0,1,0,60,25,18,1,3,0,Stun,false,false};
 if(id=="charge_shot")return {"Charge Shot","chargeShot1",.8,0,1,0,75,30,24,1,2,0,Knockdown,false,false};
 if(id=="full_auto_sweep")return {"Full Auto Sweep","fullAutoArea1",.5,18,.793353340291,1.5,90,30,20,5,4,35,Slow,true,false};
 if(id=="tactical_brace")return {"Tactical Brace","",0,0,1,.25,50,25,60,0,8,0,None,true,false};
 if(id=="charge_blast")return {"Charge Blast","",.75,20,.707106781187,2,150,80,120,6,3,0,Knockdown,false,true};
 return {"","",0,0,1,0,0,0,0,0,0,0,None,false,false};
}
inline bool contains(const std::string& id){return *ability(id).label;}
inline bool area(const Ability& a){return a.targets>1;}
inline bool hard(const Ability& a){return a.effect==Stun || a.effect==Knockdown;}
inline double chance(double rating,bool brace,bool wildRank2=false){return learnedStatusChance(wildRank2?90:85,brace?10:0,rating);}
inline double range(const Ability& a,double supported){return std::max(0.,a.range>0?std::min(a.range,supported):supported);}
inline int strongestSlow(int existing,int crippling,int sweep){return std::min(100,std::max({0,existing,crippling,sweep}));}
constexpr int BuffSeconds=8, BraceBonus=10;
}}
