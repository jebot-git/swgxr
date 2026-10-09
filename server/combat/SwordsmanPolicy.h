#pragma once
#include "CoreCuPolicy.h"
#include <string>
namespace corecu { namespace swordsman {
struct Ability {const char* label;const char* skill;double damage,cooldown,recovery;int action,mind;bool gesture,ultimate,control;};
inline Ability ability(const std::string& id){
 if(id=="rending_cut")return {"Rending Cut","combat_2hsword_novice",1.15,12,1.5,70,25,false,false,false};
 if(id=="disrupting_blow")return {"Disrupting Blow","combat_2hsword_ability_02",.9,18,1.5,65,30,false,false,true};
 if(id=="hamstring")return {"Hamstring","combat_2hsword_speed_02",.9,16,1.5,60,25,false,false,true};
 if(id=="decisive_strike")return {"Decisive Strike","combat_2hsword_accuracy_04",3,20,2,100,40,false,false,false};
 if(id=="overhead_cleave")return {"Overhead Cleave","combat_2hsword_novice",2,10,2,100,35,true,false,false};
 if(id=="ground_slam")return {"Ground Slam","combat_2hsword_support_03",1.25,18,2.25,100,40,true,false,false};
 if(id=="armour_break")return {"Armour Break","combat_2hsword_master",1.75,120,2,140,80,false,true,false};
 return {"","",0,0,0,0,0,false,false,false};
}
// Explicit original named encounter leaders below the generic boss level band.
// Wild queen/king species are tagged by their lair role, not by substring matching.
inline bool namedBoss(const std::string& name){
 for(auto id:{"lord_nyax","tusken_king","tusken_king_quest","warren_agro_droid_boss","flail_boss","gungan_boss","rebel_gungan_boss","kobola_pitboss","kobola_underboss","neo_cobral_boss","neo_cobral_overlord","rorgungan_boss","alkhara_bandit_king"})if(name==id)return true;
 return false;
}
inline bool boss(int level,bool tagged){return tagged || level>150;}
inline bool executeReady(int health,int maximum,int level,bool tagged){return maximum>0 && health>0 && double(health)<.30*maximum && !boss(level,tagged);}
// Target level only; no player level or relative-level gate. Bosses cannot execute.
inline double executionMultiplier(int level,bool tagged){return boss(level,tagged)?0.:3.-1.75*clamp((level-30.)/120.,0,1);}
inline double fracturedResistance(double resistance,int channel,bool active){
 if(!active || (channel!=1 && channel!=2))return resistance;
 const double r=clamp(resistance,0,.5);
 // score=8000*r/(1-r); halve that score, then reapply score/(8000+score).
 return r/(2-r);
}
constexpr int FractureSeconds=8;
}}
