#pragma once
#include <algorithm>
#include <string>
namespace corecu { namespace rifleman {
struct Ability {const char* label;const char* grant;double damage;int action,mind,cooldown;bool gesture,ultimate;};
inline Ability ability(const std::string& id){
 if(id=="lethal_shot")return {"Head Shot","headShot2",4.,110,40,30,false,false};
 if(id=="piercing_shot")return {"Piercing Shot","mindShot2",2.,75,30,18,false,false};
 if(id=="flurry_shot")return {"Flurry Shot","flurryShot1",.8,100,35,18,false,false};
 if(id=="surprise_shot")return {"Surprise Shot","surpriseShot",2.,80,35,24,false,false};
 if(id=="sniper_shot")return {"Sniper Shot","sniperShot",6.,150,90,120,false,true};
 if(id=="rifleman_focus")return {"Rifleman's Focus","",0,50,25,60,true,false};
 return {"","",0,0,0,0,false,false};
}
inline bool contains(const std::string& id){return *ability(id).label;}
inline double damage(const std::string& id,bool improved){return id=="lethal_shot" && improved?4.25:id=="flurry_shot" && improved?.9:ability(id).damage;}
inline double surprise(int health,int effectiveMaximum){return effectiveMaximum>0 && double(health)>=.8*effectiveMaximum?1.5:1.;}
// Called after ordinary body resistance/debuff resolution. Shield and elemental
// channels are deliberately excluded, and no state is installed on the victim.
inline double bodyResistance(double resistance,int channel,bool piercing){return piercing && (channel==1 || channel==2)?resistance*.5:resistance;}
constexpr int FocusSeconds=8;
constexpr double FocusMultiplier=1.2;
}}
