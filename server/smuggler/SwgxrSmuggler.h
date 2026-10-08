#include "CoreCuCombat.h"
#include "SwgxrSpice.h"
#ifndef SWGXR_SMUGGLER_H
#define SWGXR_SMUGGLER_H
#include "SwgxrSlicingStats.h"
#include "CombatQueueCommand.h"
#include <algorithm>
#include "SwgxrSmugglerPolicy.h"
class SwgxrPreparedRangedCommand : public CombatQueueCommand {
public:
 explicit SwgxrPreparedRangedCommand(const CombatQueueCommand& source):CombatQueueCommand(source){}
 int doQueueCommand(CreatureObject* creature,const uint64& target,const UnicodeString& arguments) const override {return doCombatAction(creature,target,arguments);}
};
class SwgxrSmuggler {
 using Json=JSONSerializationType;
public:
 static bool feigning(CreatureObject* c){return !c->isDead() && (c->isFeigningDeath() || c->hasBuff(STRING_HASHCODE("private_feign_buff")));}
 static bool feignAvailable(CreatureObject* c){return c->getPlayerObject()!=nullptr && c->getPlayerObject()->hasAbility("feigndeath");}
 static void pose(CreatureObject* c,const Json& p){
  if(!p.value("tracked",false))return;
  if(p.value("upright",false) && feigning(c)){
   if(c->isFeigningDeath())c->removeFeignedDeath();else c->removeBuff(STRING_HASHCODE("private_feign_buff"));return;
  }
  if(!p.value("feign",false) || feigning(c) || !feignAvailable(c) || c->isDead() || c->isIncapacitated() || c->isRidingMount())return;
  auto command=c->getZoneServer()->getObjectController()->getQueueCommand("feigndeath");
  if(command==nullptr || command->doQueueCommand(c,0,UnicodeString(""))!=QueueCommand::SUCCESS)throw std::runtime_error("native_feign_rejected");
 }
 static std::string commandName(const std::string& ability){
  if(ability=="lethal_shot")return "overchargeshot2";if(ability=="last_ditch")return "lastditch";if(ability=="low_blow")return "lowblow";
  if(ability=="restraining_shot" || ability=="concussion_shot_improved" || ability.empty())return "attack";
  throw std::runtime_error("unsupported_native_ability");
 }
 static const CombatQueueCommand* command(CreatureObject* c,const std::string& ability){
  auto name=commandName(ability);auto cmd=dynamic_cast<const CombatQueueCommand*>(c->getZoneServer()->getObjectController()->getQueueCommand(String(name.c_str())));
  if(!cmd)throw std::runtime_error("native_ability_unavailable");return cmd;
 }
 static bool learned(CreatureObject* c,const std::string& ability){
  if(ability.empty())return true;
  if(ability=="lethal_shot")return c->hasSkill("combat_marksman_master");
  if(ability=="restraining_shot")return c->hasSkill("combat_smuggler_novice");
  if(ability=="concussion_shot_improved")return c->hasSkill("combat_smuggler_master");
  auto cmd=command(c,ability);return c->hasSkill("combat_smuggler_novice") && !cmd->getCharacterAbility().isEmpty() && c->getPlayerObject()->hasAbility(cmd->getCharacterAbility());
 }
 static double range(CreatureObject* c,const CombatQueueCommand* cmd){auto w=c->getWeapon();return w?std::min(double(w->getMaxRange()),cmd->getRange()<0?double(w->getMaxRange()):double(cmd->getRange())):0;}
 static double multiplier(CreatureObject* c){return SwgxrSmugglerPolicy::lastDitch(c->getHAM(0),c->getMaxHAM(0)-c->getWounds(0),c->getHAM(3),c->getMaxHAM(3)-c->getWounds(3),c->getHAM(6),c->getMaxHAM(6)-c->getWounds(6));}
 static double cooldown(CreatureObject* c,const std::string& ability){auto t=c->getCooldownTime(String(("swgxr_smuggler_"+ability).c_str()));return t?std::max(0.0,-t->miliDifference()/1000.0):0;}
 static void effects(CreatureObject* attacker,CreatureObject* target,const std::string& ability){
  if(!target || target->isDead() || target->isIncapacitated())return;
  const double resistance=CoreCuCombat::rating(target,corecu::Snare,target->getSkillMod("resistance_states"));
  if((ability=="restraining_shot" || ability=="concussion_shot_improved") && System::random(100)>=corecu::statusChance(100,resistance))return;
  const int snareDuration=corecu::statusDuration(SwgxrSmugglerPolicy::snareSeconds,resistance);
  const int concussionDuration=corecu::statusDuration(SwgxrSmugglerPolicy::concussionSeconds,resistance);
  if(ability=="concussion_shot_improved" && !target->checkCooldownRecovery("corecu_control_recovery"))return;
  if(ability=="restraining_shot"){
   ManagedReference<Buff*> buff=new Buff(target,STRING_HASHCODE("swgxr_restraining_shot"),snareDuration,BuffType::STATE);Locker lock(buff,target);buff->setSkillModifier("private_swgxr_snare",SwgxrSmugglerPolicy::snarePercent);target->addBuff(buff);
  }else if(ability=="concussion_shot_improved"){
   target->addCooldown("corecu_control_recovery",8000);
   ManagedReference<Buff*> buff=new Buff(target,STRING_HASHCODE("swgxr_concussion"),concussionDuration,BuffType::STATE);Locker lock(buff,target);
   if(!target->isRooted()){target->setRootedState(concussionDuration);buff->setSkillModifier("private_swgxr_concussion_root",1);}
   if(!target->isDizzied()){target->setDizziedState(concussionDuration);buff->setSkillModifier("private_swgxr_concussion_daze",1);}
   if(target->setNextAttackDelay(attacker,"swgxr_concussion",0,concussionDuration))buff->setSkillModifier("private_swgxr_concussion_delay",1);
   target->addBuff(buff);
  }
 }
 static Json abilities(CreatureObject* c){
  Json out=Json::array();auto w=c->getWeapon();if(!w || !w->isRangedWeapon())return out;
  for(auto ability:{"lethal_shot","last_ditch","low_blow","restraining_shot","concussion_shot_improved"}){
   if(!learned(c,ability))continue;auto cmd=command(c,ability);if(!(cmd->getWeaponType() & w->getWeaponBitmask()))continue;
   bool last=std::string(ability)=="last_ditch";std::string label=std::string(ability)=="lethal_shot"?"Lethal Shot":last?"Last Ditch":std::string(ability)=="low_blow"?"Low Blow":std::string(ability)=="restraining_shot"?"Restraining Shot":"Concussion Shot Improved";
   float h=w->getHealthAttackCost()*cmd->getHealthCostMultiplier()*SwgxrSlicingStats::costScale(c,0),a=w->getActionAttackCost()*cmd->getActionCostMultiplier()*SwgxrSlicingStats::costScale(c,3),m=w->getMindAttackCost()*cmd->getMindCostMultiplier()*SwgxrSlicingStats::costScale(c,6);
   out.push_back({{"max_range_m",range(c,cmd)},{"min_range_m",0},{"conditions_met",cmd->checkStateMask(c) && cmd->checkInvalidLocomotions(c)},{"ultimate",last},{"sac_action_strength_share",a+h>0?h/(a+h):0},{"sac_policy","corecu_cu_v2"},{"id",ability},{"label",label},{"source_command",commandName(ability)},{"damage_multiplier",last?multiplier(c):std::string(ability)=="concussion_shot_improved"?SwgxrSmugglerPolicy::concussionDamage:cmd->getDamageMultiplier()},{"base_sac",{{"health",0},{"action",last?0:a+h},{"mind",last?0:m*.5f}}},{"cooldown_seconds",30.0*SwgxrSpice::cooldownScale(c)},{"cooldown_remaining_seconds",cooldown(c,ability)},{"native_authority",true},{"activation","native_ranged"}});
  }return out;
 }
};
#endif
