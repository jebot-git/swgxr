#ifndef SWGXR_SPICE_H
#define SWGXR_SPICE_H
#include "engine/util/JSONSerializationType.h"
#include "server/zone/objects/creature/CreatureObject.h"
#include "server/zone/objects/creature/buffs/Buff.h"
#include "server/zone/objects/player/PlayerObject.h"
// Native persistent buffs are the sole phase clock. The original consumable
// templates continue to own HAM modifiers and active durations.
class SwgxrSpice {
 static int& damageDepth(){static thread_local int value=0;return value;}
 static int& adjustmentDepth(){static thread_local int value=0;return value;}
public:
 // Scoped native HAM bookkeeping is not combat/environmental damage.
 struct HamAdjustment {HamAdjustment(){++adjustmentDepth();}~HamAdjustment(){--adjustmentDepth();}};
 struct DamageAction {DamageAction(){++damageDepth();}~DamageAction(){--damageDepth();}};
 static bool damageAction(){return damageDepth()>0;}
 static bool hamAdjustment(){return adjustmentDepth()>0;}
 using Json=JSONSerializationType;
 static Buff* buff(CreatureObject* c,const char* name,bool down=false){if(!c)return nullptr;return c->getBuff(String((std::string("spice.")+name+(down?".down":".up")).c_str()).hashCode());}
 static bool active(CreatureObject* c,const char* name){return buff(c,name)!=nullptr;}
 static bool withdrawing(CreatureObject* c,const char* name){return buff(c,name,true)!=nullptr;}
 static float scale(CreatureObject* c,const char* name,float up,float down){return active(c,name)?up:withdrawing(c,name)?down:1.f;}
 static float cooldownScale(CreatureObject* c){return active(c,"grey_gabaki")?.9f:1.f;}
 static float regenScale(CreatureObject* c,int pool){return scale(c,pool==0?"scramjet":pool==3?"shadowpaw":"thruster_head",1.2f,.8f);}
 static float meleePowerScale(CreatureObject* c){return scale(c,"droid_lube",1.2f,.5f);}
 static float meleeRecoveryScale(CreatureObject* c){return scale(c,"droid_lube",1.2f,.5f);}
 static float rangedCapacityScale(CreatureObject* c){return scale(c,"gunjack",1.2f,.5f);}
 static float rangedRpmScale(CreatureObject* c){return scale(c,"gunjack",1.2f,.5f);}
 static float meleeDamageScale(CreatureObject* c){return active(c,"pyrepenol")?1.25f:1.f;}
 static int withdrawalDuration(const String& name){if(name=="grey_gabaki")return 0;if(name=="sweetblossom" || name=="droid_lube" || name=="gunjack")return 180;if(name=="yarrock")return 900;if(name=="pyrepenol" || name=="crash_n_burn" || name=="sedative_h4b" || name=="booster_blue")return 300;if(name=="neutron_pixey")return 600;if(name=="muon_gold")return 3600;return 120;}
 static bool quietWithdrawal(const String& name){return name=="crash_n_burn";}
 static bool pinnedHam(CreatureObject* c){return withdrawing(c,"sedative_h4b") && !c->isDead();}
 static void pinHam(CreatureObject* c){if(pinnedHam(c))for(int pool:{0,3,6})if(c->getHAM(pool)!=1)c->setHAM(pool,1,true);}
 // Return 1 for the first instantaneous recovery, 2 for the forced second death.
 static int sweetIncapacitation(CreatureObject* c){auto b=buff(c,"sweetblossom");if(!b || !c->isPlayerCreature())return 0;auto ghost=c->getPlayerObject();auto episode=String::valueOf(b->_getObjectID());auto used=ghost->getScreenPlayData("swgxr_spice","sweetblossom_recovered");if(used==episode)return 2;ghost->setScreenPlayData("swgxr_spice","sweetblossom_recovered",episode);ghost->updateToDatabase();return 1;}
 static Json snapshot(CreatureObject* c){
  Json out={{"revision",0},{"effects",Json::array()},{"modifiers",{{"cooldown_scale",cooldownScale(c)},{"health_regen_scale",regenScale(c,0)},{"action_regen_scale",regenScale(c,3)},{"mind_regen_scale",regenScale(c,6)},{"melee_power_scale",meleePowerScale(c)},{"melee_recovery_scale",meleeRecoveryScale(c)},{"ranged_capacity_scale",rangedCapacityScale(c)},{"ranged_rpm_scale",rangedRpmScale(c)},{"melee_damage_scale",meleeDamageScale(c)}}},{"autoaim",active(c,"booster_blue")},{"melee_cone_degrees",active(c,"pyrepenol")?180:0}};
  for(auto name:{"grey_gabaki","sweetblossom","scramjet","shadowpaw","thruster_head","giggledust","yarrock","droid_lube","gunjack","pyrepenol","crash_n_burn","sedative_h4b","neutron_pixey","muon_gold","booster_blue","kliknik_boost","kwi_boost"}){
   bool down=false;auto b=buff(c,name);if(!b){b=buff(c,name,true);down=true;}if(!b)continue;double remaining=std::max(0.f,b->getTimeLeft()),duration=b->getBuffDuration();out["revision"]=b->_getObjectID();out["effects"].push_back({{"episode_id",std::to_string(b->_getObjectID())},{"spice_id",name},{"phase",down?"withdrawal":"active"},{"elapsed_seconds",std::max(0.0,duration-remaining)},{"remaining_seconds",remaining},{"duration_seconds",duration}});
  }return out;
 }
};
#endif
