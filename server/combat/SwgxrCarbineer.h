#pragma once
#include "VolleyFirePolicy.h"
#include "CarbineerPolicy.h"
#include "SwgxrTka.h"
#include "ProjectileContactPolicy.h"
class SwgxrCarbineer {
 using Json=JSONSerializationType;
 static double targetDistance(AiAgent* a,const corecu::warcry::Vec& origin){auto p=a->getWorldPosition();double x=p.getX()-origin[0],y=p.getZ()-origin[1]+std::max(.25,std::min(1.,double(a->getHeight(false))*.65)),z=p.getY()-origin[2];return std::sqrt(x*x+y*y+z*z);}
 static bool eligible(CreatureObject* c,AiAgent* a,const corecu::warcry::Vec& origin,const corecu::warcry::Vec& direction,double range,double cosine){
  if(!targetReady(a) || a->getZone()!=c->getZone() || !a->isAttackableBy(c))return false;
  if(corecu::volley::guaranteed(c->getObjectID(),a->getObjectID()))return corecu::volley::inRange(c->getDistanceTo(a),range);
  auto p=a->getWorldPosition();double dx=p.getX()-origin[0],dy=p.getZ()-origin[1]+std::max(.25,std::min(1.,double(a->getHeight(false))*.65)),dz=p.getY()-origin[2],distance=targetDistance(a,origin);
  return distance<=range && (distance<.001 || (dx*direction[0]+dy*direction[1]+dz*direction[2])/distance>=cosine) && CollisionManager::checkLineOfSight(c,a);
 }
public:
 static bool compatible(CreatureObject* c){auto w=c->getWeapon();return w && w->isCarbineWeapon() && w->isCertifiedFor(c) && !w->isBroken();}
 static bool suppressionTrained(CreatureObject* c){return c->hasSkill("combat_carbine_novice") && c->getPlayerObject() && c->getPlayerObject()->hasAbility("suppressionFire2");}
 static bool learned(CreatureObject* c,const std::string& id){
  if(!corecu::carbineer::contains(id) || !c->hasSkill("combat_carbine_novice") || !c->getPlayerObject())return false;
  if(id=="tactical_brace")return c->hasSkill("combat_carbine_ability_02");if(id=="charge_blast")return c->hasSkill("combat_carbine_master");
  return c->getPlayerObject()->hasAbility(corecu::carbineer::ability(id).grant) || (id=="wild_shot" && c->getPlayerObject()->hasAbility("wildShot2")) || (id=="charge_shot" && c->getPlayerObject()->hasAbility("chargeShot2")) || (id=="full_auto_sweep" && c->getPlayerObject()->hasAbility("fullAutoArea2"));
 }
 static bool targetReady(CreatureObject* a){return a && a->isAiAgent() && !a->asAiAgent()->isPet() && !a->isDead() && !a->isIncapacitated();}
 static bool active(CreatureObject* c){return compatible(c) && learned(c,"tactical_brace") && !c->isDead() && !c->isIncapacitated() && c->hasBuff(STRING_HASHCODE("swgxr_tactical_brace"));}
 static void refresh(CreatureObject* c){if(!compatible(c) || !learned(c,"tactical_brace") || c->isDead() || c->isIncapacitated())c->removeBuff(STRING_HASHCODE("swgxr_tactical_brace"));}
 static double chance(CreatureObject* c,double rating,bool wildRank2=false){return corecu::carbineer::chance(rating,active(c),wildRank2);}
 static bool conditions(CreatureObject* c,const std::string& id){return compatible(c) && !c->isDead() && !c->isIncapacitated() && !c->isRidingMount() && (id!="tactical_brace" || !active(c));}
 static double cooldown(CreatureObject* c,const std::string& id){auto t=c->getCooldownTime(String(("swgxr_smuggler_"+id).c_str()));return t?std::max(0.,-t->miliDifference()/1000.):0.;}
 static double interval(CreatureObject* c,const std::string& id){return id=="tactical_brace"?.25:std::max(corecu::carbineer::ability(id).recovery,c->getWeapon()?double(CombatManager::instance()->calculateWeaponAttackSpeed(c,c->getWeapon(),1)):1.5);}
 static void effects(CreatureObject* c,CreatureObject* a,const std::string& id,int damage){
  using namespace corecu::carbineer;auto spec=ability(id);if(damage<=0 || !targetReady(a) || spec.effect==None)return;
  const bool kd=spec.effect==Knockdown,stun=spec.effect==Stun;int immunity=kd?CommandEffect::KNOCKDOWN:stun?CommandEffect::STUN:CommandEffect::NEXTATTACKDELAY;
  if(a->hasEffectImmunity(immunity) || (hard(spec) && !a->checkCooldownRecovery("corecu_control_recovery")) || (kd && (!a->checkKnockdownRecovery() || a->isKnockedDown())))return;
  if(hard(spec))a->addCooldown("corecu_control_recovery",8000);
  double rating=CoreCuCombat::rating(a,kd?corecu::Knockdown:stun?corecu::Stun:corecu::Snare,a->getSkillMod(kd?"knockdown_defense":stun?"stun_defense":"resistance_states"));
  if(System::random(99)>=chance(c,rating,id=="wild_shot" && c->getPlayerObject() && c->getPlayerObject()->hasAbility("wildShot2")))return;
  int seconds=corecu::statusDuration(spec.duration,rating);
  if(kd){a->setPosture(CreaturePosture::KNOCKEDDOWN,false,true);a->addCooldown("knockdownRecovery",8000);a->setPostureChangeDelay(seconds*1000);a->removeBuff(STRING_HASHCODE("burstrun"));a->removeBuff(STRING_HASHCODE("retreat"));ManagedReference<AiAgent*> target=a->asAiAgent();
   Core::getTaskManager()->scheduleTask([target](){Locker lock(target);if(!target->isDead() && !target->isIncapacitated() && target->isKnockedDown() && !target->hasPostureChangeDelay())target->setPosture(CreaturePosture::UPRIGHT,false,true);},"SwgxrCarbineerStand",seconds*1000+1);
  }else if(stun)a->setStunnedState(seconds);
  else {const bool sweep=id=="full_auto_sweep";ManagedReference<Buff*> buff=new Buff(a,sweep?STRING_HASHCODE("swgxr_full_auto_sweep"):STRING_HASHCODE("swgxr_crippling_shot"),seconds,BuffType::STATE);Locker lock(buff,a);buff->setSkillModifier(sweep?"private_carbineer_sweep":"private_carbineer_crippling",spec.slow);a->addBuff(buff);}
 }
 static Json snapshot(CreatureObject* c){refresh(c);Json out=Json::object();for(auto id:{"crippling_shot","wild_shot","charge_shot","full_auto_sweep","tactical_brace","charge_blast"}){auto a=corecu::carbineer::ability(id);out[id]={{"learned",learned(c,id)},{"conditions_met",conditions(c,id)},{"cooldown_remaining_seconds",cooldown(c,id)},{"cooldown_seconds",a.cooldown},{"action_cost",a.action},{"mind_cost",a.mind},{"interval_seconds",interval(c,id)}};}
  auto buff=c->getBuff(STRING_HASHCODE("swgxr_tactical_brace"));auto& row=out["tactical_brace"];row["active"]=active(c);row["active_remaining_seconds"]=active(c) && buff?std::max(0.f,buff->getTimeLeft()):0.;row["duration_seconds"]=corecu::carbineer::BuffSeconds;row["control_chance_bonus"]=corecu::carbineer::BraceBonus;return out;
 }
 static Json abilities(CreatureObject* c){Json out=Json::array();if(!compatible(c))return out;auto state=snapshot(c);auto w=c->getWeapon();
  for(auto id:{"crippling_shot","wild_shot","charge_shot","full_auto_sweep","tactical_brace","charge_blast"}){if(!learned(c,id))continue;auto a=corecu::carbineer::ability(id);auto row=state[id];std::string key=id;
   row["id"]=id;row["label"]=a.label;row["activation"]=a.gesture?"carbineer_gesture":a.ultimate?"carbineer_ultimate":"native_ranged";row["ultimate"]=a.ultimate;row["native_authority"]=true;row["source_command"]="attack";row["sac_policy"]="fixed";row["base_sac"]={{"health",0},{"action",a.action},{"mind",a.mind}};row["damage_multiplier"]=a.damage;row["hit_count"]=1;row["max_range_m"]=corecu::carbineer::range(a,w->getMaxRange());row["min_range_m"]=0;row["target_cap"]=a.targets;row["ammo_cost"]=corecu::carbineer::area(a)?3:key=="tactical_brace"?0:1;row["control_chance_bonus"]=active(c)?10:0;
   row["weapon_requirement"]="Certified carbine and corresponding Carbineer training. Movement spread remains unchanged.";
   row["description"]=key=="crippling_shot"?"Light hit and a resisted 40% movement slow for up to 6 seconds. Strongest active slow wins.":key=="wild_shot"?"Moderate hit and resisted native Stun for up to 3 seconds; reduces combat effectiveness, without freezing movement. Wild Shot II improves application chance.":key=="charge_shot"?"Moderate hit and resisted knockdown for up to 2 seconds; shared control recovery applies.":key=="full_auto_sweep"?"A 75-degree muzzle cone, up to 18 metres and five nearest enemies with line of sight. One 0.5x hit each and a resisted 35% movement slow for up to 4 seconds; strongest slow wins.":key=="tactical_brace"?"For 8 seconds, carbine crowd-control application gains 10 chance points before target resistance, capped at 95%. Durations, immunities and recovery are unchanged.":"A 90-degree muzzle cone, up to 20 metres and six nearest enemies with line of sight. One 0.75x hit each and resisted knockdown for up to 3 seconds; shared control recovery applies.";
   if(a.gesture){row["category"]="gesture";row["trigger_description"]=key=="full_auto_sweep"?"Support the carbine with both grips and release both triggers. Sweep horizontally, reverse, return forward, then briefly settle.":"Support with both grips and release both triggers. From level, cant into a chest-height ready pose, hold for 0.8 seconds, then return level.";}
   if(key=="tactical_brace"){row["self_only"]=true;row["required_profession_skill"]="combat_carbine_ability_02";}
   if(a.ultimate){row["required_profession_skill"]="combat_carbine_master";row["profession_requirement"]="Master Carbineer";row["trigger_description"]="Support the carbine, release both triggers, then press both together. The blast follows the actual muzzle direction.";}
   out.push_back(row);
  }return out;
 }
 static Json run(CreatureObject* c,const Json& request){
  auto id=request.at("ability_id").get<std::string>();auto spec=corecu::carbineer::ability(id);refresh(c);auto w=c->getWeapon();
  if((!spec.gesture && !spec.ultimate) || !learned(c,id) || !conditions(c,id) || std::to_string(w->getObjectID())!=request.at("item_id").get<std::string>() || !w->isASubChildOf(c))throw std::runtime_error("native_carbineer_unavailable");
  if(!request.contains("two_hands") || !request["two_hands"].is_boolean() || !request["two_hands"].get<bool>())throw std::runtime_error("native_carbineer_requires_support");
  if(cooldown(c,id)>0)throw std::runtime_error("native_carbineer_cooldown");
  auto source=dynamic_cast<const CombatQueueCommand*>(c->getZoneServer()->getObjectController()->getQueueCommand("attack"));if(!source || !source->checkStateMask(c) || !source->checkInvalidLocomotions(c))throw std::runtime_error("native_carbineer_attack_unavailable");
  auto p=c->getWorldPosition();corecu::warcry::Vec feet{{p.getX(),p.getZ(),p.getY()}},o{},d{};
  for(auto key:{"origin","direction"}){const auto& v=request.at(key);if(!v.is_array() || v.size()!=3)throw std::runtime_error("invalid_carbineer_pose");for(int i=0;i<3;++i)if(!v[i].is_number())throw std::runtime_error("invalid_carbineer_pose");}
  for(int i=0;i<3;++i){o[i]=request["origin"][i].get<double>();d[i]=request["direction"][i].get<double>();}if(!corecu::pistoleer::validPose(o,d,feet))throw std::runtime_error("invalid_carbineer_pose");double length=std::sqrt(d[0]*d[0]+d[1]*d[1]+d[2]*d[2]);for(auto& axis:d)axis/=length;
  if(!request.value("target_id",std::string()).empty())throw std::runtime_error("invalid_carbineer_target");
  const double range=corecu::carbineer::range(spec,w->getMaxRange()*corecu::projectile::rangeScale(false,true));std::vector<ManagedReference<AiAgent*>> targets;
  if(corecu::carbineer::area(spec)){SortedVector<TreeEntry*> nearby(32,32);c->getZone()->getInRangeObjects(p.getX(),p.getZ(),p.getY(),range+3,&nearby,true);for(int i=0;i<nearby.size();++i){auto obj=static_cast<SceneObject*>(nearby.get(i));if(!obj->isAiAgent())continue;auto a=obj->asAiAgent();Locker lock(a,c);if(eligible(c,a,o,d,range,spec.cosine))targets.push_back(a);}
   std::sort(targets.begin(),targets.end(),[&](const ManagedReference<AiAgent*>& a,const ManagedReference<AiAgent*>& b){bool av=corecu::volley::guaranteed(c->getObjectID(),a->getObjectID()),bv=corecu::volley::guaranteed(c->getObjectID(),b->getObjectID());if(av!=bv)return av;double ad=targetDistance(a,o),bd=targetDistance(b,o);return ad==bd?a->getObjectID()<b->getObjectID():ad<bd;});}
  if(c->getWeapon()!=w || !conditions(c,id))throw std::runtime_error("native_carbineer_unavailable");
  if(c->getHAM(3)<=spec.action || c->getHAM(6)<=spec.mind)throw std::runtime_error("native_carbineer_insufficient_sac");c->inflictDamage(c,3,spec.action,false,true,false);c->inflictDamage(c,6,spec.mind,false,true,false);c->addCooldown(String(("swgxr_smuggler_"+id).c_str()),spec.cooldown*1000);
  Json out={{"success",true},{"operation","carbineer"},{"shot_id",request.at("shot_id")},{"ability_id",id},{"interval_seconds",interval(c,id)},{"ham_cost_committed",true},{"hit",false},{"damage",0},{"targets",Json::array()}};
  if(id=="tactical_brace"){ManagedReference<Buff*> buff=new Buff(c,STRING_HASHCODE("swgxr_tactical_brace"),corecu::carbineer::BuffSeconds,BuffType::STATE);Locker lock(buff,c);c->addBuff(buff);return out;}
  int total=0,count=0;for(auto& a:targets){if(count>=spec.targets)break;Locker lock(a,c);if(c->getWeapon()!=w || !eligible(c,a,o,d,range,spec.cosine))continue;SwgxrTkaStrike strike(*source,spec.damage);strike.setRange(int(std::ceil(range+3)));int before=a->getHAM(0);c->setTargetID(0,true);int code=strike.doCombatAction(c,a->getObjectID(),"",w);c->setTargetID(0,true);int damage=code==QueueCommand::SUCCESS?std::max(0,before-a->getHAM(0)):0;effects(c,a,id,damage);total+=damage;++count;out["targets"].push_back({{"target_id",std::to_string(a->getObjectID())},{"damage",damage},{"native_result",code}});}
  out["hit"]=total>0;out["damage"]=total;return out;
 }
};
