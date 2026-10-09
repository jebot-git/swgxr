#pragma once
#include "CombatQueueCommand.h"
#include "CoreCuCombat.h"
#include "SwgxrSlicingStats.h"
#include "MeleePolicy.h"
// Original Brawler grants and effects, bounded for physical combat.
class SwgxrBrawler {
 using Json=JSONSerializationType;
public:
 static std::string family(CreatureObject* c){auto w=c->getWeapon();if(!w || w->isJediOneHandedWeapon() || w->isJediTwoHandedWeapon() || w->isJediPolearmWeapon())return "";if(w->isUnarmedWeapon())return "unarmed";if(w->isOneHandMeleeWeapon())return "onehandmelee";if(w->isTwoHandMeleeWeapon())return "twohandmelee";if(w->isPolearmWeaponObject())return "polearm";return "";}
 static std::string source(CreatureObject* c,const std::string& id){auto f=family(c);if(f.empty())return "";
  if(id=="challenging_strike" && f=="unarmed" && c->hasSkill("combat_unarmed_novice"))return "attack";
  if(id=="knockdown_strike" && f=="unarmed" && c->hasSkill("combat_unarmed_novice")){for(auto name:{"unarmedknockdown2","unarmedknockdown1"})if(c->getPlayerObject()->hasAbility(name))return name;}
  if(id=="knockdown_strike")return f=="unarmed"?"unarmedlunge2":f=="onehandmelee"?"melee1hlunge2":f=="twohandmelee"?"melee2hlunge2":"polearmlunge2";
  if(id=="unarmed_stun" && f=="unarmed")return "unarmedstun1";
  if(id=="unarmed_blind" && f=="unarmed")return "unarmedblind1";
  if(id=="polearm_stun" && f=="polearm")return "polearmstun1";
  return "";
 }
 static bool learned(CreatureObject* c,const std::string& id){auto name=source(c,id);return !name.empty() && c->getPlayerObject() && (id=="challenging_strike" || c->getPlayerObject()->hasAbility(String(name.c_str())));}
 static bool control(const std::string& id){return !id.empty() && id!="challenging_strike";}
 static const CombatQueueCommand* command(CreatureObject* c,const std::string& id){auto name=source(c,id);return name.empty()?nullptr:dynamic_cast<const CombatQueueCommand*>(c->getZoneServer()->getObjectController()->getQueueCommand(String(name.c_str())));}
 static double cooldown(CreatureObject* c,const std::string& id){auto t=c->getCooldownTime(String(("corecu_brawler_"+id).c_str()));return t?std::max(0.,-t->miliDifference()/1000.):0.;}
 static bool facing(const corecu::melee::Vec& origin,const corecu::melee::Vec& direction,const corecu::melee::Vec& feet){double dot=0,length=0;for(int i=0;i<3;++i){double v=feet[i]+(i==1?1.:0.)-origin[i];dot+=v*direction[i];length+=v*v;}return length<.01 || dot/std::sqrt(length)>=.5;}
 static double recovery(const std::string& id){return id=="knockdown_strike"?20.:15.;}
 static Json abilities(CreatureObject* c){Json out=Json::array();auto w=c->getWeapon();if(!w || family(c).empty())return out;
  for(auto id:{"knockdown_strike","unarmed_stun","unarmed_blind","polearm_stun","challenging_strike"}){auto cmd=command(c,id);if(!cmd || !learned(c,id))continue;
   float h=w->getHealthAttackCost()*cmd->getHealthCostMultiplier()*SwgxrSlicingStats::costScale(c,0),a=w->getActionAttackCost()*cmd->getActionCostMultiplier()*SwgxrSlicingStats::costScale(c,3),m=w->getMindAttackCost()*cmd->getMindCostMultiplier()*SwgxrSlicingStats::costScale(c,6);
   std::string label=std::string(id)=="knockdown_strike"?"Knockdown Strike":std::string(id)=="unarmed_blind"?"Blinding Attack":std::string(id)=="unarmed_stun"?"Stunning Attack":"Polearm Stun";
   out.push_back({{"id",id},{"label",label},{"activation","native_melee"},{"ultimate",false},{"source_command",source(c,id)},{"description","Hold trigger and punch toward the body marker, or strike it with a qualified swing. Weapon range, native resistance and control recovery apply."},{"damage_multiplier",cmd->getDamageMultiplier()},{"max_range_m",corecu::melee::reach(w->getMaxRange(),w->isUnarmedWeapon())},{"interval_seconds",CombatManager::instance()->calculateWeaponAttackSpeed(c,w,cmd->getSpeedMultiplier())},{"cooldown_seconds",recovery(id)},{"cooldown_remaining_seconds",cooldown(c,id)},{"conditions_met",w->isCertifiedFor(c) && cmd->checkStateMask(c) && cmd->checkInvalidLocomotions(c)},{"base_sac",{{"health",0},{"action",a+h},{"mind",m*.5f}}},{"sac_policy","corecu_cu_v2"},{"sac_action_strength_share",a+h>0?h/(a+h):0}});
   auto& row=out.back();row["requires_control_available"]=control(id);
   if(std::string(id)=="challenging_strike"){row["label"]="Challenging Strike";row["description"]="Strike the chest marker for modest damage and increased single-target threat. Requires Teras Kasi and unarmed combat.";row["damage_multiplier"]=.75;row["base_sac"]={{"health",0},{"action",40},{"mind",20}};row["sac_policy"]="fixed";row["sac_action_strength_share"]=0;}
   if(std::string(id)=="knockdown_strike" && c->hasSkill("combat_unarmed_novice") && family(c)=="unarmed")row["label"]="Unbalancing Strike";
  }return out;
 }
 static void boundEffects(CombatQueueCommand& cmd){auto effects=*cmd.getStateEffects();for(int i=0;i<effects.size();++i){auto& effect=effects.elementAt(i).getValue();if(effect.getStateLength()>0)effect.setStateLength(4);auto timers=effect.getDefenderExclusionTimers();timers.add("corecu_control_recovery");effect.setDefenderExclusionTimers(timers);}cmd.setStateEffects(effects);}
 static bool buffLearned(CreatureObject* c,const std::string& id){auto p=c->getPlayerObject();return p && c->hasSkill("combat_brawler_novice") && (id=="center_of_being"?p->hasAbility("centerofbeing"):id=="berserk" && p->hasAbility("berserk1"));}
 static void refreshBuffs(CreatureObject* c){for(auto id:{"center_of_being","berserk"}){auto saved=c->getPlayerObject()->getScreenPlayData("swgxr_brawler_buff",id);if(!saved.isEmpty() && (family(c).empty() || saved!=String(family(c).c_str()))){if(std::string(id)=="center_of_being")c->removeBuff(STRING_HASHCODE("centerofbeing"));else c->removeBuff(Long::hashCode(CreatureState::BERSERK));c->getPlayerObject()->setScreenPlayData("swgxr_brawler_buff",id,"");}}}
 static bool active(CreatureObject* c,const std::string& id){return id=="center_of_being"?c->hasBuff(STRING_HASHCODE("centerofbeing")):c->isBerserked();}
 static bool buffConditions(CreatureObject* c,const std::string& id){auto f=family(c);if(f.empty() || !c->getWeapon()->isCertifiedFor(c) || c->isDead() || c->isIncapacitated() || c->isRidingMount() || c->getPosture()!=0 || active(c,id))return false;
  if(id=="center_of_being" && (c->getSkillMod(String(("center_of_being_duration_"+f).c_str()))<=0 || c->getSkillMod(String((f+"_center_of_being_efficacy").c_str()))<=0))return false;
  return true;
 }
 static Json buffs(CreatureObject* c){refreshBuffs(c);Json out=Json::object();for(auto id:{"center_of_being","berserk"})out[id]={{"learned",buffLearned(c,id)},{"conditions_met",buffConditions(c,id)},{"active",active(c,id)},{"cooldown_remaining_seconds",cooldown(c,id)},{"action_cost",std::string(id)=="berserk"?80:40},{"mind_cost",40}};return out;}
 static Json buffAbilities(CreatureObject* c){Json out=Json::array();if(family(c).empty())return out;auto state=buffs(c);for(auto id:{"center_of_being","berserk"}){if(!buffLearned(c,id))continue;auto row=state[id];bool center=std::string(id)=="center_of_being";row["id"]=id;row["label"]=center?"Center of Being":"Berserk";row["category"]="gesture";row["ultimate"]=false;row["activation"]="brawler_pose";row["description"]=center?"Temporary defensive focus, using the trained weapon family's native Center of Being efficacy and duration.":"Native melee damage and accuracy buff with a defence penalty. Lasts 20 seconds, or 40 at Master Brawler.";row["trigger_description"]=center?"Hold your free offhand upright and open in front of your torso for 0.8 seconds, like a meditation sign. Keep the weapon hand lowered and triggers released.":"Spread both arms outward at shoulder height, clench both fists and hold for 0.8 seconds. Keep triggers released; no microphone or actual yell is needed.";row["weapon_requirement"]="Unarmed, one-handed melee, two-handed melee or polearm. Skill, resources and 60-second cooldown apply.";row["cooldown_seconds"]=60;out.push_back(row);}return out;}
 static Json buff(CreatureObject* c,const Json& request){auto id=request.at("ability_id").get<std::string>();if(id!="center_of_being" && id!="berserk")throw std::runtime_error("unknown_brawler_buff");refreshBuffs(c);
  if(!buffLearned(c,id) || !buffConditions(c,id) || std::to_string(c->getWeapon()->getObjectID())!=request.at("item_id").get<std::string>())throw std::runtime_error("native_brawler_buff_unavailable");
  if(cooldown(c,id)>0)throw std::runtime_error("native_brawler_buff_cooldown");int action=id=="berserk"?80:40;
  if(c->getHAM(3)<=action || c->getHAM(6)<=40)throw std::runtime_error("native_brawler_buff_insufficient_sac");
  if(id=="center_of_being"){auto cmd=c->getZoneServer()->getObjectController()->getQueueCommand("centerofbeing");if(!cmd || cmd->doQueueCommand(c,0,UnicodeString())!=QueueCommand::SUCCESS)throw std::runtime_error("native_center_of_being_rejected");}
  else c->setBerserkedState(c->hasSkill("combat_brawler_master")?40:20);
  c->inflictDamage(c,3,action,false,true,false);c->inflictDamage(c,6,40,false,true,false);c->addCooldown(String(("corecu_brawler_"+id).c_str()),60000);c->getPlayerObject()->setScreenPlayData("swgxr_brawler_buff",String(id.c_str()),String(family(c).c_str()));
  return {{"success",true},{"shot_id",request.at("shot_id")},{"ability_id",id},{"interval_seconds",1.}};
 }
};
