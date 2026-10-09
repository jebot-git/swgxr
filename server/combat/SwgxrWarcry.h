#pragma once
#include "WarcryPolicy.h"
#include <vector>
#include <algorithm>
#include "CoreCuCombat.h"
#include "server/zone/managers/collision/CollisionManager.h"
// One Brawler ability: fear-driven attack delay plus bounded damage suppression.
class SwgxrWarcry {
 using Json=JSONSerializationType;
 static bool eligible(CreatureObject* c,AiAgent* a,const corecu::warcry::Vec& feet,const corecu::warcry::Vec& direction){
  if(!a || a->getZone()!=c->getZone() || a->isDead() || a->isIncapacitated() || a->isPet() || !a->isAttackableBy(c) || !a->checkCooldownRecovery("corecu_control_recovery"))return false;
  auto p=a->getWorldPosition();return corecu::warcry::inCone(feet,direction,{{p.getX(),p.getZ(),p.getY()}}) && CollisionManager::checkLineOfSight(c,a);
 }
public:
 static bool learned(CreatureObject* c){auto p=c->getPlayerObject();return p && c->hasSkill("combat_brawler_novice") && p->hasAbility("warcry1") && p->hasAbility("intimidate1");}
 static bool weapon(CreatureObject* c){auto w=c->getWeapon();return w && !w->isUnarmedWeapon() && (w->isMeleeWeapon() || w->isRangedWeapon()) && w->isCertifiedFor(c);}
 static double cooldown(CreatureObject* c){auto t=c->getCooldownTime("corecu_warcry");return t?std::max(0.,-t->miliDifference()/1000.):0.;}
 static Json snapshot(CreatureObject* c){return {{"learned",learned(c)},{"conditions_met",weapon(c) && !c->isDead() && !c->isIncapacitated() && !c->isRidingMount() && c->getPosture()==0},{"cooldown_remaining_seconds",cooldown(c)},{"action_cost",corecu::warcry::ActionCost},{"mind_cost",corecu::warcry::MindCost},{"interval_seconds",1.}};}
 static Json ability(CreatureObject* c){auto row=snapshot(c);row["id"]="warcry";row["label"]="Warcry";row["description"]="Raise your held weapon above your head, lower it slightly and pump it upward. Delays attacks and reduces enemy damage in a forward cone. Replaces Warcry and Intimidate.";row["activation"]="overhead_weapon_pump";row["category"]="gesture";row["trigger_description"]="Hold grip with both triggers released. Raise the weapon above your head, lower it slightly, then pump upward while facing enemies.";row["weapon_requirement"]="A certified held melee or ranged weapon; unavailable unarmed.";row["ultimate"]=false;row["cooldown_seconds"]=corecu::warcry::Cooldown;row["max_range_m"]=corecu::warcry::Range;row["base_sac"]={{"health",0},{"action",corecu::warcry::ActionCost},{"mind",corecu::warcry::MindCost}};return row;}
 static Json run(CreatureObject* c,const Json& request){
  if(!learned(c))throw std::runtime_error("native_warcry_not_learned");
  if(!snapshot(c).at("conditions_met").get<bool>() || std::to_string(c->getWeapon()->getObjectID())!=request.at("item_id").get<std::string>())throw std::runtime_error("native_warcry_unavailable");
  if(cooldown(c)>0)throw std::runtime_error("native_warcry_cooldown");
  corecu::warcry::Vec o{},d{};auto p=c->getWorldPosition();corecu::warcry::Vec feet{{p.getX(),p.getZ(),p.getY()}};
  for(auto key:{"origin","direction"}){const auto& v=request.at(key);if(!v.is_array() || v.size()!=3)throw std::runtime_error("invalid_warcry_pose");for(int i=0;i<3;++i)if(!v[i].is_number())throw std::runtime_error("invalid_warcry_pose");}
  for(int i=0;i<3;++i){o[i]=request["origin"][i].get<double>();d[i]=request["direction"][i].get<double>();}
  if(!corecu::warcry::validPose(o,d,feet))throw std::runtime_error("invalid_warcry_pose");
  if(c->getHAM(3)<=corecu::warcry::ActionCost || c->getHAM(6)<=corecu::warcry::MindCost)throw std::runtime_error("native_warcry_insufficient_sac");
  SortedVector<TreeEntry*> nearby(64,64);c->getZone()->getInRangeObjects(p.getX(),p.getZ(),p.getY(),corecu::warcry::Range,&nearby,true);
  std::vector<ManagedReference<AiAgent*>> targets;
  for(int i=0;i<nearby.size();++i){auto obj=static_cast<SceneObject*>(nearby.get(i));if(!obj->isAiAgent())continue;auto a=obj->asAiAgent();Locker lock(a,c);if(eligible(c,a,feet,d))targets.push_back(a);}
  std::sort(targets.begin(),targets.end(),[&](const ManagedReference<AiAgent*>& a,const ManagedReference<AiAgent*>& b){return c->getDistanceTo(a)<c->getDistanceTo(b);});
  if(targets.empty())throw std::runtime_error("no_eligible_warcry_target");
  c->inflictDamage(c,3,corecu::warcry::ActionCost,false,true,false);c->inflictDamage(c,6,corecu::warcry::MindCost,false,true,false);c->addCooldown("corecu_warcry",int(corecu::warcry::Cooldown*1000));
  bool master=c->hasSkill("combat_brawler_master");int affected=0,attempted=0;
  for(auto a:targets){if(attempted>=corecu::warcry::MaxTargets)break;Locker lock(a,c);if(!eligible(c,a,feet,d))continue;++attempted;
   CombatManager::instance()->startCombat(a,c);
   double resistance=CoreCuCombat::rating(a,corecu::Intimidate,a->getSkillMod("intimidate_defense"));
   if(System::random(99)>=corecu::statusChance(100,resistance))continue;
   bool applied=false;
   if(a->getSkillMod("private_damage_divisor_intimidate")<=0){ManagedReference<Buff*> buff=new Buff(a,STRING_HASHCODE("swgxr_warcry"),corecu::statusDuration(corecu::warcry::duration(master),resistance),BuffType::STATE);Locker lockBuff(buff,a);buff->setSkillModifier("private_damage_divisor_intimidate",corecu::warcry::Reduction);a->addBuff(buff);applied=true;}
   double delayResistance=CoreCuCombat::rating(a,corecu::Snare,a->getSkillMod("warcry_defense"));
   if(System::random(99)<corecu::statusChance(100,delayResistance))applied=a->setNextAttackDelay(c,"swgxr_warcry",0,corecu::statusDuration(corecu::warcry::delay(master),delayResistance)) || applied;
   if(applied){a->addCooldown("corecu_control_recovery",8000);++affected;}
  }
  return {{"success",true},{"shot_id",request.at("shot_id")},{"affected",affected},{"attempted",attempted},{"interval_seconds",1.}};
 }
};
