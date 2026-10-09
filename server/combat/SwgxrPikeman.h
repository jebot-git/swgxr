#pragma once
#include "VolleyFirePolicy.h"
#include "PikemanPolicy.h"
#include "SwgxrTka.h"
#include "MeleePolicy.h"
class SwgxrPikeman {
 using Json=JSONSerializationType;
 static bool eligible(CreatureObject* c,AiAgent* a,const corecu::warcry::Vec& feet,const corecu::warcry::Vec& d,double range,double cosine){
  corecu::tka::Attack shape{range,cosine,0,0,0,1,1,0,0};
  if(!a || a->getZone()!=c->getZone() || a->isPet() || a->isDead() || a->isIncapacitated() || !a->isAttackableBy(c))return false;
  if(corecu::volley::guaranteed(c->getObjectID(),a->getObjectID()))return corecu::volley::inRange(c->getDistanceTo(a),range);
  auto p=a->getWorldPosition();return corecu::tka::inCone(feet,d,{{p.getX(),p.getZ(),p.getY()}},shape) && CollisionManager::checkLineOfSight(c,a);
 }
 static bool targetReady(AiAgent* a,const std::string& id){auto spec=corecu::pikeman::ability(id);return corecu::pikeman::ready(spec,a->checkCooldownRecovery("corecu_control_recovery")) && (!corecu::pikeman::targeted(spec) || spec.effect!=corecu::pikeman::Knockdown || (a->checkKnockdownRecovery() && !a->isKnockedDown()));}
 static void effects(CreatureObject* c,AiAgent* a,const std::string& id,int damage){
  if(damage<=0 || a->isDead() || a->isIncapacitated())return;
  auto spec=corecu::pikeman::ability(id);using namespace corecu::pikeman;
  const bool kd=spec.effect==Knockdown,stun=spec.effect==Stun,slow=spec.effect==Slow;
  int effect=kd?CommandEffect::KNOCKDOWN:stun?CommandEffect::STUN:CommandEffect::NEXTATTACKDELAY;
  if(a->hasEffectImmunity(effect) || (hard(spec) && !a->checkCooldownRecovery("corecu_control_recovery")))return;
  if(kd && (!a->checkKnockdownRecovery() || a->isKnockedDown()))return;
  if(hard(spec))a->addCooldown("corecu_control_recovery",8000);
  int status=kd?corecu::Knockdown:stun?corecu::Stun:corecu::Snare;
  double rating=CoreCuCombat::rating(a,status,a->getSkillMod(kd?"knockdown_defense":stun?"stun_defense":slow?"resistance_states":"warcry_defense"));
  if(System::random(99)>=chance(rating,progression(c)))return;
  int seconds=corecu::statusDuration(spec.duration,rating);
  if(kd){
   a->setPosture(CreaturePosture::KNOCKEDDOWN,false,true);a->addCooldown("knockdownRecovery",8000);a->setPostureChangeDelay(seconds*1000);
   a->removeBuff(STRING_HASHCODE("burstrun"));a->removeBuff(STRING_HASHCODE("retreat"));
   ManagedReference<AiAgent*> target=a;
   Core::getTaskManager()->scheduleTask([target](){Locker lock(target);if(!target->isDead() && !target->isIncapacitated() && target->isKnockedDown() && !target->hasPostureChangeDelay())target->setPosture(CreaturePosture::UPRIGHT,false,true);},"SwgxrPikemanStand",seconds*1000+1);
  }else if(stun)a->setStunnedState(seconds);
  else if(slow){
   auto key=id=="pinning_strike"?STRING_HASHCODE("swgxr_pinning_strike"):STRING_HASHCODE("swgxr_driving_jabs");
   ManagedReference<Buff*> buff=new Buff(a,key,seconds,BuffType::STATE);Locker lock(buff,a);buff->setSkillModifier(id=="pinning_strike"?"private_pikeman_pin":"private_pikeman_drive",spec.slow);a->addBuff(buff);
  }else a->setNextAttackDelay(c,"swgxr_disrupting_jab",0,seconds);
 }
public:
 static bool compatible(CreatureObject* c){auto w=c->getWeapon();return w && w->isPolearmWeaponObject() && !w->isJediPolearmWeapon() && w->isCertifiedFor(c) && !w->isBroken();}
 static bool learned(CreatureObject* c,const std::string& id){auto a=corecu::pikeman::ability(id);return *a.skill && c->hasSkill("combat_polearm_novice") && c->hasSkill(a.skill);}
 static double progression(CreatureObject* c){Vector<String> skills;c->getSkillList()->getStringList(skills);double sum=0;for(int i=0;i<skills.size();++i)sum+=corecu::progressWeight("combat_polearm",skills.get(i).toCharArray());return corecu::clamp(sum,0,1);}
 static bool conditions(CreatureObject* c){return compatible(c) && c->getPosture()==0 && !c->isDead() && !c->isIncapacitated() && !c->isRidingMount();}
 static double cooldown(CreatureObject* c,const std::string& id){auto t=c->getCooldownTime(String(corecu::pikeman::cooldownKey(id).c_str()));return t?std::max(0.,-t->miliDifference()/1000.):0.;}
 static double interval(CreatureObject* c,const corecu::pikeman::Ability& a){return std::max(a.recovery,double(CombatManager::instance()->calculateWeaponAttackSpeed(c,c->getWeapon(),1)));}
 static Json snapshot(CreatureObject* c){Json out=Json::object();for(auto id:{"knockdown_strike","polearm_stun","pinning_strike","disrupting_jab","overhead_whirl","sweeping_trip","driving_jabs","whirlwind"}){auto a=corecu::pikeman::ability(id);out[id]={{"learned",learned(c,id)},{"conditions_met",conditions(c)},{"cooldown_remaining_seconds",cooldown(c,id)},{"cooldown_seconds",a.cooldown},{"action_cost",a.action},{"mind_cost",a.mind},{"interval_seconds",c->getWeapon()?interval(c,a):a.recovery}};}return out;}
 static Json abilities(CreatureObject* c){Json out=Json::array();if(!compatible(c))return out;auto state=snapshot(c);
  for(auto id:{"knockdown_strike","polearm_stun","pinning_strike","disrupting_jab","overhead_whirl","sweeping_trip","driving_jabs","whirlwind"}){if(!learned(c,id))continue;auto a=corecu::pikeman::ability(id);auto row=state[id];std::string key=id;
   row["id"]=id;row["label"]=a.label;row["native_family"]="pikeman";row["activation"]=(a.gesture || a.ultimate)?"pikeman_gesture":"native_melee";row["ultimate"]=a.ultimate;row["sac_policy"]="fixed";row["base_sac"]={{"health",0},{"action",a.action},{"mind",a.mind}};row["damage_multiplier"]=a.damage;row["max_range_m"]=corecu::melee::reach(c->getWeapon()->getMaxRange(),false);row["requires_control_available"]=corecu::pikeman::hard(a);row["target_cap"]=a.targets;row["requires_knockdown_available"]=a.effect==corecu::pikeman::Knockdown;
   row["description"]=key=="knockdown_strike"?"Moderate hit and up to 2 seconds of resisted knockdown. Upgrades the existing shared Knockdown Strike slot and cooldown.":key=="polearm_stun"?"Moderate hit and up to 4 seconds of native Stun, reducing combat effectiveness. Upgrades Polearm Stun's shared slot and cooldown.":key=="pinning_strike"?"Light hit and a resisted 40% slow for up to 5 seconds. Strongest active slow wins.":key=="disrupting_jab"?"Light hit and up to 2 seconds of resisted attack delay.":key=="overhead_whirl"?"Circular moderate damage against up to four enemies, with up to 2 seconds of resisted Stun.":key=="sweeping_trip"?"Light damage in a wide forward arc against up to three enemies; individually attempts up to 2 seconds of knockdown.":key=="driving_jabs"?"Two light thrusts in a narrow cone against up to two fixed enemies. Once per enemy, attempts a 30% slow for up to 3 seconds.":"Circular moderate damage against up to six enemies, attempting up to 3 seconds of resisted knockdown. Control recovery and immunities remain.";
   row["weapon_requirement"]="Certified polearm; Pikeman training required.";
   if(a.gesture){row["category"]="gesture";row["trigger_description"]=key=="overhead_whirl"?"Hold the polearm with both hands, triggers released. From neutral, trace a controlled overhead circle.":key=="sweeping_trip"?"Hold with both hands, triggers released. From neutral, make a committed low horizontal sweep across the front.":"Hold with both hands, triggers released. Make two quick forward thrusts, retracting between them.";}
   if(a.ultimate){row["required_profession_skill"]="combat_polearm_master";row["profession_requirement"]="Master Pikeman";row["trigger_description"]="Support the polearm with both hands, release both triggers, then press both together. No body spin required.";}
   out.push_back(row);
  }return out;
 }
 static Json run(CreatureObject* c,const Json& request){
  auto id=request.at("ability_id").get<std::string>();auto spec=corecu::pikeman::ability(id);auto w=c->getWeapon();
  if(!learned(c,id) || !conditions(c) || std::to_string(w->getObjectID())!=request.at("item_id").get<std::string>() || !w->isASubChildOf(c))throw std::runtime_error("native_pikeman_unavailable");
  if(cooldown(c,id)>0)throw std::runtime_error("native_pikeman_cooldown");
  auto source=dynamic_cast<const CombatQueueCommand*>(c->getZoneServer()->getObjectController()->getQueueCommand("attack"));
  if(!source || !source->checkStateMask(c) || !source->checkInvalidLocomotions(c))throw std::runtime_error("native_pikeman_attack_unavailable");
  auto p=c->getWorldPosition();corecu::warcry::Vec feet{{p.getX(),p.getZ(),p.getY()}},o{},d{};
  for(auto key:{"origin","direction"}){const auto& v=request.at(key);if(!v.is_array() || v.size()!=3)throw std::runtime_error("invalid_pikeman_pose");for(int i=0;i<3;++i)if(!v[i].is_number())throw std::runtime_error("invalid_pikeman_pose");}
  for(int i=0;i<3;++i){o[i]=request["origin"][i].get<double>();d[i]=request["direction"][i].get<double>();}
  if(!corecu::warcry::validPose(o,d,feet))throw std::runtime_error("invalid_pikeman_pose");
  const std::string bound=request.value("target_id",std::string());if((spec.gesture || spec.ultimate)?!bound.empty():bound.empty())throw std::runtime_error("invalid_pikeman_target");
  double range=corecu::melee::reach(w->getMaxRange(),false);
  std::vector<ManagedReference<AiAgent*>> targets;
  {SortedVector<TreeEntry*> nearby(32,32);c->getZone()->getInRangeObjects(p.getX(),p.getZ(),p.getY(),range,&nearby,true);
   for(int i=0;i<nearby.size();++i){auto obj=static_cast<SceneObject*>(nearby.get(i));if(!obj->isAiAgent())continue;auto a=obj->asAiAgent();Locker lock(a,c);
    if(!bound.empty() && std::to_string(a->getObjectID())!=bound)continue;
    if(eligible(c,a,feet,d,range,spec.cosine) && targetReady(a,id))targets.push_back(a);
   }
   std::sort(targets.begin(),targets.end(),[&](const ManagedReference<AiAgent*>& a,const ManagedReference<AiAgent*>& b){bool av=corecu::volley::guaranteed(c->getObjectID(),a->getObjectID()),bv=corecu::volley::guaranteed(c->getObjectID(),b->getObjectID());if(av!=bv)return av;double x=c->getDistanceTo(a),y=c->getDistanceTo(b);return x==y?a->getObjectID()<b->getObjectID():x<y;});
   if(targets.empty())throw std::runtime_error("native_pikeman_target_unavailable");
  }
  auto primary=targets.front();Locker primaryLock(primary,c);
  if(!eligible(c,primary,feet,d,range,spec.cosine) || !targetReady(primary,id) || c->getWeapon()!=w)throw std::runtime_error("native_pikeman_target_unavailable");
  if(c->getHAM(3)<=spec.action || c->getHAM(6)<=spec.mind)throw std::runtime_error("native_pikeman_insufficient_sac");
  c->inflictDamage(c,3,spec.action,false,true,false);c->inflictDamage(c,6,spec.mind,false,true,false);c->addCooldown(String(corecu::pikeman::cooldownKey(id).c_str()),int(spec.cooldown*1000));
  primaryLock.release();
  Json out={{"success",true},{"shot_id",request.at("shot_id")},{"ability_id",id},{"interval_seconds",interval(c,spec)},{"hit",false},{"damage",0},{"targets",Json::array()}};
  int total=0,count=0;
  for(auto a:targets){if(count>=spec.targets)break;Locker lock(a,c);
   if(!eligible(c,a,feet,d,range,spec.cosine) || !targetReady(a,id))continue;
   ++count;int dealt=0;
   for(int blow=0;blow<spec.blows;++blow){if(!eligible(c,a,feet,d,range,spec.cosine))break;
    SwgxrTkaStrike strike(*source,spec.damage);strike.setRange(int(std::ceil(range)));int before=a->getHAM(0);c->setTargetID(0,true);int code=strike.doCombatAction(c,a->getObjectID(),"",w);c->setTargetID(0,true);if(code==QueueCommand::SUCCESS)dealt+=std::max(0,before-a->getHAM(0));
   }
   effects(c,a,id,dealt);total+=dealt;out["targets"].push_back({{"id",std::to_string(a->getObjectID())},{"damage",dealt}});
  }
  out["hit"]=total>0;out["damage"]=total;return out;
 }
};
