#pragma once
#include <algorithm>
#include <string>
namespace corecu { namespace marksman {
struct Ability {const char* label;const char* skill;const char* weapon;double damage;int action,mind,cooldown,blows;bool control;};
inline Ability ability(const std::string& id){
 if(id=="suppression_fire")return {"Suppression Fire","combat_marksman_support_04","ranged",.5,45,15,18,1,true};
 if(id=="warning_shot")return {"Warning Shot","combat_marksman_support_01","ranged",.25,35,15,20,1,true};
 if(id=="controlled_burst")return {"Controlled Burst","combat_marksman_carbine_02","carbine",.65,75,20,12,3,false};
 if(id=="bleeding_shot")return {"Bleeding Shot","combat_marksman_pistol_04","pistol",.8,50,20,16,1,false};
 return {"","","",0,0,0,0,0,false};
}
inline bool contains(const std::string& id){return *ability(id).skill;}
inline bool compatible(const std::string& id,bool ranged,bool pistol,bool carbine){auto a=ability(id);return contains(id) && ranged && (std::string(a.weapon)=="ranged" || (std::string(a.weapon)=="pistol"?pistol:carbine));}
inline int bleedBudget(int damage,bool improved=false){return int(std::max(0,damage)*(improved?.40:.30));}
inline int hesitationSeconds(bool improved){return improved?3:2;}
constexpr int SuppressionSeconds=6, AccuracyPenalty=20, BleedSeconds=12;
}}
