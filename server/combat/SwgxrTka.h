#pragma once
#include "VolleyFirePolicy.h"
#include "TkaPolicy.h"
#include "SwgxrForceOfWill.h"
#include <vector>
#include "CoreCuCombat.h"
#include "CombatQueueCommand.h"
#include "server/zone/managers/collision/CollisionManager.h"
#include "server/zone/objects/tangible/threat/ThreatMap.h"
class SwgxrTkaStrike : public CombatQueueCommand {
public:
 bool usesPhysicalContactAccuracy() const override {return true;}
 SwgxrTkaStrike(const CombatQueueCommand& source,double multiplier):CombatQueueCommand(source) {
  setDamageMultiplier(multiplier);setAreaAction(false);setConeAction(false);setPoolsToDamage(1);
  setHealthCostMultiplier(0);setActionCostMultiplier(0);setMindCostMultiplier(0);setForceCostMultiplier(0);
 }
 int doQueueCommand(CreatureObject* c,const uint64& target,const UnicodeString& args) const override {return doCombatAction(c,target,args);}
};
class SwgxrTka {
 using Json=JSONSerializationType;
 static bool eligible(CreatureObject* c,AiAgent* a,const corecu::warcry::Vec& feet,const corecu::warcry::Vec& direction,const corecu::tka::Attack& spec) {
  if(!a || a->getZone()!=c->getZone() || a->isDead() || a->isIncapacitated() || a->isPet() || !a->isAttackableBy(c))return false;
  if(corecu::volley::guaranteed(c->getObjectID(),a->getObjectID()))return corecu::volley::inRange(c->getDistanceTo(a),spec.range);
  auto p=a->getWorldPosition();return corecu::tka::inCone(feet,direction,{{p.getX(),p.getZ(),p.getY()}},spec) && CollisionManager::checkLineOfSight(c,a);
 }
public:
 static bool unarmed(CreatureObject* c){return c->getWeapon() && c->getWeapon()->isUnarmedWeapon() && c->getWeapon()->isCertifiedFor(c);}
 static bool learned(CreatureObject* c,const std::string& id) {
  auto p=c->getPlayerObject();if(!p || !c->hasSkill("combat_unarmed_novice"))return false;
  if(id=="indomitable_focus")return c->hasSkill("combat_unarmed_master");
  if(id=="tka_sweep" || id=="challenging_strike")return true;
  if(id=="tka_half_spin")return p->hasAbility("unarmedspinattack2");
  return id=="tka_volley" && p->hasAbility("unarmedcombo1");
 }
 static double cooldown(CreatureObject* c,const std::string& id){auto t=c->getCooldownTime(String(("corecu_tka_"+id).c_str()));return t?std::max(0.,-t->miliDifference()/1000.):0.;}
 static void refresh(CreatureObject* c){if(c->hasBuff(STRING_HASHCODE("swgxr_indomitable_focus")) && (!unarmed(c) || !learned(c,"indomitable_focus") || c->isDead() || c->isIncapacitated()))c->removeBuff(STRING_HASHCODE("swgxr_indomitable_focus"));}
 static bool conditions(CreatureObject* c,const std::string& id){return unarmed(c) && !c->isDead() && !c->isIncapacitated() && !c->isRidingMount() && c->getPosture()==0 && (id!="indomitable_focus" || !CoreCuCombat::tkaFocus(c));}
 static Json snapshot(CreatureObject* c) {
  refresh(c);Json out=Json::object();
  for(auto id:{"tka_sweep","tka_half_spin","tka_volley","indomitable_focus"}) {
   bool focus=std::string(id)=="indomitable_focus";auto a=corecu::tka::attack(id);
   out[id]={{"learned",learned(c,id)},{"conditions_met",conditions(c,id)},{"cooldown_remaining_seconds",cooldown(c,id)},{"cooldown_seconds",focus?corecu::tka::FocusCooldown:a.cooldown},{"interval_seconds",focus?1.:a.interval},{"action_cost",focus?corecu::tka::FocusAction:a.action},{"mind_cost",focus?corecu::tka::FocusMind:a.mind},{"active",focus && CoreCuCombat::tkaFocus(c)}};
   if(focus){auto buff=c->getBuff(STRING_HASHCODE("swgxr_indomitable_focus"));out[id]["active_remaining_seconds"]=buff?std::max(0.f,buff->getTimeLeft()):0.;}
  }return out;
 }
 static Json abilities(CreatureObject* c) {
  Json out=Json::array();if(!unarmed(c))return out;auto state=snapshot(c);
  for(auto id:{"tka_sweep","tka_half_spin","tka_volley","indomitable_focus"}) {
   if(!learned(c,id))continue;auto row=state[id];std::string name=id;bool focus=name=="indomitable_focus";
   row["id"]=id;row["ultimate"]=focus;row["activation"]="tka_gesture";
   row["label"]=focus?"Indomitable Focus":name=="tka_sweep"?"Sweeping Punch":name=="tka_half_spin"?"Two-Handed Half-Spin":"Rapid Punch Volley";
   row["description"]=focus?"For 12 seconds, amplify trained or active CoB efficacy by 50%, capped at 100, add up to 20 status resistance rating and generate 50% extra damage threat. Requires Master Teras Kasi. Does not refresh CoB.":"A bounded area attack with increased threat on damage dealt. Native hit, armour and line-of-sight rules apply. No stun or knockdown.";
   row["trigger_description"]=focus?"Bring both fists together in front of your chest, release both triggers, then press both triggers together.":name=="tka_sweep"?"With triggers released and fists clenched, sweep one fist horizontally across your front.":name=="tka_half_spin"?"With triggers released and fists clenched, sweep both arms together from one side across your front. No full body rotation required.":"With triggers released and fists clenched, throw three rapid alternating forward punches.";
   row["weapon_requirement"]="Unarmed family only. Hold grip with triggers released for area gestures; ordinary punches still use trigger.";
   row["sac_policy"]="fixed";row["base_sac"]={{"health",0},{"action",row["action_cost"]},{"mind",row["mind_cost"]}};
   if(focus){row["self_only"]=true;row["required_profession_skill"]="combat_unarmed_master";row["profession_requirement"]="Master Teras Kasi Artist";}
   else {auto a=corecu::tka::attack(id);row["category"]="gesture";row["max_range_m"]=a.range;row["max_targets"]=a.targets;row["blows"]=a.blows;}
   out.push_back(row);
  }
  if(SwgxrForceOfWill::learned(c)){
   auto row=SwgxrForceOfWill::snapshot(c);
   row["id"]="force_of_will";row["label"]="Force of Will";row["category"]="gesture";row["activation"]="life_recovery";row["ultimate"]=false;row["self_only"]=true;
   row["description"]="Recover early from incapacitation with at least 15% of effective maximum Health. Ten-minute cooldown persists across relogs. Wounds, fatigue, incapacitation count, threat and Action/Mind remain unchanged. Cannot resurrect.";
   row["trigger_description"]="While incapacitated, release then hold the offhand stick. Normal recovery starts after 1 second; keep holding for 3 seconds total for Force of Will.";
   row["weapon_requirement"]="Certified unarmed family only.";row["required_profession_skill"]="combat_unarmed_accuracy_04";row["profession_requirement"]="Teras Kasi, Master Meditative Techniques";
   row["sac_policy"]="fixed";row["base_sac"]={{"health",0},{"action",0},{"mind",0}};out.push_back(row);
  }return out;
 }
 static void threat(CreatureObject* c,AiAgent* target,int damage,bool challenge=false){if(target && !target->isDead() && target->getThreatMap() && damage>0)target->getThreatMap()->addAggro(c,corecu::tka::threat(damage,challenge));}
 static Json run(CreatureObject* c,const Json& request) {
  auto id=request.at("ability_id").get<std::string>();refresh(c);
  if(!learned(c,id) || !conditions(c,id) || std::to_string(c->getWeapon()->getObjectID())!=request.at("item_id").get<std::string>())throw std::runtime_error("native_tka_unavailable");
  if(cooldown(c,id)>0)throw std::runtime_error("native_tka_cooldown");
  auto p=c->getWorldPosition();corecu::warcry::Vec feet{{p.getX(),p.getZ(),p.getY()}},o{},d{};
  for(auto key:{"origin","direction"}){const auto& v=request.at(key);if(!v.is_array() || v.size()!=3)throw std::runtime_error("invalid_tka_pose");for(int i=0;i<3;++i)if(!v[i].is_number())throw std::runtime_error("invalid_tka_pose");}
  for(int i=0;i<3;++i){o[i]=request["origin"][i].get<double>();d[i]=request["direction"][i].get<double>();}
  if(!corecu::warcry::validPose(o,d,feet))throw std::runtime_error("invalid_tka_pose");
  auto spec=corecu::tka::attack(id);bool focus=id=="indomitable_focus";
  if(!focus && !spec.targets)throw std::runtime_error("unknown_tka_ability");
  int action=focus?corecu::tka::FocusAction:spec.action,mind=focus?corecu::tka::FocusMind:spec.mind;
  if(c->getHAM(3)<=action || c->getHAM(6)<=mind)throw std::runtime_error("native_tka_insufficient_sac");
  std::vector<ManagedReference<AiAgent*>> targets;
  const CombatQueueCommand* source=nullptr;
  if(!focus) {
   source=dynamic_cast<const CombatQueueCommand*>(c->getZoneServer()->getObjectController()->getQueueCommand("attack"));
   if(!source || !source->checkStateMask(c) || !source->checkInvalidLocomotions(c))throw std::runtime_error("native_tka_attack_unavailable");
   SortedVector<TreeEntry*> nearby(32,32);c->getZone()->getInRangeObjects(p.getX(),p.getZ(),p.getY(),spec.range,&nearby,true);
   for(int i=0;i<nearby.size();++i){auto obj=static_cast<SceneObject*>(nearby.get(i));if(!obj->isAiAgent())continue;auto a=obj->asAiAgent();Locker lock(a,c);if(eligible(c,a,feet,d,spec))targets.push_back(a);}
   std::sort(targets.begin(),targets.end(),[&](const ManagedReference<AiAgent*>& a,const ManagedReference<AiAgent*>& b){bool av=corecu::volley::guaranteed(c->getObjectID(),a->getObjectID()),bv=corecu::volley::guaranteed(c->getObjectID(),b->getObjectID());if(av!=bv)return av;double x=c->getDistanceTo(a),y=c->getDistanceTo(b);return x==y?a->getObjectID()<b->getObjectID():x<y;});
   if(targets.empty())throw std::runtime_error("no_eligible_tka_target");
  }
  c->inflictDamage(c,3,action,false,true,false);c->inflictDamage(c,6,mind,false,true,false);
  c->addCooldown(String(("corecu_tka_"+id).c_str()),int((focus?corecu::tka::FocusCooldown:spec.cooldown)*1000));
  Json out={{"success",true},{"shot_id",request.at("shot_id")},{"ability_id",id},{"interval_seconds",focus?1.:spec.interval},{"affected",0},{"damage",0},{"targets",Json::array()}};
  if(focus){ManagedReference<Buff*> buff=new Buff(c,STRING_HASHCODE("swgxr_indomitable_focus"),corecu::tka::FocusSeconds,BuffType::SKILL);Locker lock(buff,c);c->addBuff(buff);return out;}
  SwgxrTkaStrike strike(*source,spec.multiplier);strike.setRange(int(spec.range));int attempted=0,total=0,affected=0;
  for(auto a:targets){if(attempted>=spec.targets)break;Locker lock(a,c);if(!eligible(c,a,feet,d,spec))continue;++attempted;int dealt=0;
   for(int blow=0;blow<spec.blows;++blow){if(!eligible(c,a,feet,d,spec))break;int before=a->getHAM(0);c->setTargetID(0,true);strike.doCombatAction(c,a->getObjectID(),"",c->getWeapon());c->setTargetID(0,true);dealt+=std::max(0,before-a->getHAM(0));}
   threat(c,a,dealt);if(dealt>0)++affected;total+=dealt;out["targets"].push_back({{"id",std::to_string(a->getObjectID())},{"damage",dealt}});
  }
  out["affected"]=affected;out["attempted"]=attempted;out["damage"]=total;return out;
 }
};
