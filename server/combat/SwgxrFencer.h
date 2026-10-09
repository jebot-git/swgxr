#pragma once
#include "VolleyFirePolicy.h"
#include "FencerPolicy.h"
#include "SwgxrTka.h"
#include "MeleePolicy.h"
class SwgxrFencer {
 using Json=JSONSerializationType;
 static bool eligible(CreatureObject* c,AiAgent* a,const corecu::warcry::Vec& feet,const corecu::warcry::Vec& d,double range,double cosine){
  corecu::tka::Attack shape{range,cosine,0,0,0,1,1,0,0};
  if(!a || a->getZone()!=c->getZone() || a->isPet() || a->isDead() || a->isIncapacitated() || !a->isAttackableBy(c))return false;
  if(corecu::volley::guaranteed(c->getObjectID(),a->getObjectID()))return corecu::volley::inRange(c->getDistanceTo(a),range);
  auto p=a->getWorldPosition();return corecu::tka::inCone(feet,d,{{p.getX(),p.getZ(),p.getY()}},shape) && CollisionManager::checkLineOfSight(c,a);
 }
 static bool targetReady(AiAgent* a,const std::string& id){return !corecu::fencer::ability(id).control || a->checkCooldownRecovery("corecu_control_recovery");}
 static void addBuff(CreatureObject* c,uint32 key,int duration,const char* mod="",int value=0){ManagedReference<Buff*> buff=new Buff(c,key,duration,BuffType::STATE);Locker lock(buff,c);if(value)buff->setSkillModifier(mod,value);c->addBuff(buff);}
 static void effects(CreatureObject* c,AiAgent* a,const std::string& id,int damage){
  if(damage<=0)return;
  if(id=="probing_jabs"){addBuff(c,STRING_HASHCODE("swgxr_fencer_precision"),corecu::fencer::PrecisionSeconds);return;}
  if(a->isDead() || a->isIncapacitated())return;
  const bool precision=c->hasBuff(STRING_HASHCODE("swgxr_fencer_precision")),ultimate=flawless(c);
  if(precision)c->removeBuff(STRING_HASHCODE("swgxr_fencer_precision")); // One landed effect attempt, including immunity/resistance.
  double progress=progression(c);
  bool bleed=id=="arterial_cut" || id=="raking_slash";
  int effect=id=="disorienting_thrust"?CommandEffect::BLIND:id=="guard_bash"?CommandEffect::NEXTATTACKDELAY:CommandEffect::INTIMIDATE;
  if(bleed?(a->isDroidObject() || a->hasDotImmunity(CreatureState::BLEEDING)):a->hasEffectImmunity(effect))return;
  auto spec=corecu::fencer::ability(id);
  if(spec.control)a->addCooldown("corecu_control_recovery",8000);
  int status=bleed?corecu::Bleed:id=="disorienting_thrust"?corecu::Blind:id=="guard_bash"?corecu::Snare:corecu::Intimidate;
  int existing=a->getSkillMod(bleed?"bleeding_defense":id=="disorienting_thrust"?"blind_defense":id=="guard_bash"?"warcry_defense":"intimidate_defense");
  double rating=CoreCuCombat::rating(a,status,existing);
  if(System::random(99)>=corecu::fencer::chance(rating,progress,precision,ultimate))return;
  if(bleed){
   int budget=int(damage*corecu::fencer::bleedScale(progress,ultimate));
   // Potency -1 skips only the application roll already made above. Native duration resistance, cures and absorption remain.
   if(budget>0)a->addDotState(c,CreatureState::BLEEDING,STRING_HASHCODE("swgxr_fencer_bleed"),budget,0,corecu::fencer::BleedDuration,-1,existing);
  }else if(id=="disorienting_thrust")a->setBlindedState(corecu::statusDuration(4,rating));
  else if(id=="guard_bash")a->setNextAttackDelay(c,"swgxr_guard_bash",0,corecu::statusDuration(2,rating));
  else if(id=="nerve_strike")addBuff(a,STRING_HASHCODE("swgxr_nerve_strike"),corecu::statusDuration(corecu::fencer::softDuration(6,progress),rating),"private_fencer_nerve",15);
  else if(id=="exposing_thrust")addBuff(a,STRING_HASHCODE("swgxr_exposed_thrust"),corecu::statusDuration(corecu::fencer::softDuration(8,progress),rating));
 }
public:
 static bool compatible(CreatureObject* c){auto w=c->getWeapon();return w && w->isOneHandMeleeWeapon() && !w->isJediOneHandedWeapon() && w->isCertifiedFor(c) && !w->isBroken();}
 static bool learned(CreatureObject* c,const std::string& id){auto a=corecu::fencer::ability(id);return *a.skill && c->hasSkill("combat_1hsword_novice") && c->hasSkill(a.skill);}
 static bool flawless(CreatureObject* c){return compatible(c) && c->hasSkill("combat_1hsword_master") && !c->isDead() && !c->isIncapacitated() && c->hasBuff(STRING_HASHCODE("swgxr_flawless_assault"));}
 static void refresh(CreatureObject* c){if(!compatible(c) || !c->hasSkill("combat_1hsword_novice") || c->isDead() || c->isIncapacitated()){c->removeBuff(STRING_HASHCODE("swgxr_fencer_precision"));c->removeBuff(STRING_HASHCODE("swgxr_flawless_assault"));}else if(!c->hasSkill("combat_1hsword_master"))c->removeBuff(STRING_HASHCODE("swgxr_flawless_assault"));}
 static double progression(CreatureObject* c){Vector<String> skills;c->getSkillList()->getStringList(skills);double sum=0;for(int i=0;i<skills.size();++i)sum+=corecu::progressWeight("combat_1hsword",skills.get(i).toCharArray());return corecu::fencer::progression(sum);}
 static bool conditions(CreatureObject* c,const std::string& id){return compatible(c) && c->getPosture()==0 && !c->isDead() && !c->isIncapacitated() && !c->isRidingMount() && (id!="flawless_assault" || !flawless(c));}
 static double cooldown(CreatureObject* c,const std::string& id){auto t=c->getCooldownTime(String(("corecu_fencer_"+id).c_str()));return t?std::max(0.,-t->miliDifference()/1000.):0.;}
 static double interval(CreatureObject* c,const corecu::fencer::Ability& a){return std::max(a.recovery,double(CombatManager::instance()->calculateWeaponAttackSpeed(c,c->getWeapon(),1)));}
 static Json snapshot(CreatureObject* c){refresh(c);Json out=Json::object();for(auto id:{"arterial_cut","nerve_strike","disorienting_thrust","exposing_thrust","probing_jabs","raking_slash","guard_bash","flawless_assault"}){auto a=corecu::fencer::ability(id);out[id]={{"learned",learned(c,id)},{"conditions_met",conditions(c,id)},{"cooldown_remaining_seconds",cooldown(c,id)},{"cooldown_seconds",a.cooldown},{"action_cost",a.action},{"mind_cost",a.mind},{"interval_seconds",c->getWeapon()?interval(c,a):a.recovery}};
   if(a.ultimate){auto buff=c->getBuff(STRING_HASHCODE("swgxr_flawless_assault"));out[id]["active"]=flawless(c);out[id]["active_remaining_seconds"]=buff?std::max(0.f,buff->getTimeLeft()):0.;}
  }return out;}
 static Json abilities(CreatureObject* c){Json out=Json::array();if(!compatible(c))return out;auto state=snapshot(c);
  for(auto id:{"arterial_cut","nerve_strike","disorienting_thrust","exposing_thrust","probing_jabs","raking_slash","guard_bash","flawless_assault"}){if(!learned(c,id))continue;auto a=corecu::fencer::ability(id);auto row=state[id];std::string key=id;
   row["id"]=id;row["label"]=a.label;row["activation"]=(a.gesture || a.ultimate)?"fencer_gesture":"native_melee";row["ultimate"]=a.ultimate;row["sac_policy"]="fixed";row["base_sac"]={{"health",0},{"action",a.action},{"mind",a.mind}};row["damage_multiplier"]=a.damage;row["max_range_m"]=corecu::melee::reach(c->getWeapon()->getMaxRange(),false);row["requires_control_available"]=a.control;
   row["description"]=key=="arterial_cut"?"Moderate hit and the strongest Fencer bleed. One shared remaining damage budget; ticks every 3 seconds for at most 12 seconds.":key=="nerve_strike"?"Light hit and 15% damage suppression. Stronger existing suppression takes precedence.":key=="disorienting_thrust"?"Light hit and native Blind, up to 4 seconds before resistance. Shared control recovery applies.":key=="exposing_thrust"?"Light hit and -20 resistance against bleed, blind, intimidate and snares. Allies benefit; immunities remain.":key=="probing_jabs"?"Two light hits. A landed hit grants Precision: +5 chance points before resistance for the next Fencer effect attempt within 6 seconds.":key=="raking_slash"?"Moderate hit and a smaller bleed sharing Arterial Cut's single budget.":key=="guard_bash"?"Light hit and resisted attack delay of up to 2 seconds. Shared control recovery applies.":"For 12 seconds, Fencer bleed budgets reach 100% of landed damage and effect application gains +10 chance points before resistance instead of Precision. No retroactive bleed increase.";
   row["weapon_requirement"]="Certified one-handed melee weapon; Fencer training required.";
   row["fencer_progress"]=progression(c);row["bleed_budget_fraction"]=corecu::fencer::bleedScale(progression(c),flawless(c));
   if(a.gesture){row["category"]="gesture";row["trigger_description"]=key=="probing_jabs"?"Hold grip with trigger released. Make two quick forward weapon-hand jabs, retracting between them.":key=="raking_slash"?"Hold grip with trigger released. From an upper corner, make a committed diagonal slash across your body.":"Hold grip with trigger released. Establish a weapon guard briefly, then drive the hilt forward in a short thrust.";}
   if(a.ultimate){row["self_only"]=true;row["required_profession_skill"]="combat_1hsword_master";row["profession_requirement"]="Master Fencer";row["trigger_description"]="Support the weapon with the offhand, release both triggers, then press both together.";}
   out.push_back(row);
  }return out;
 }
 static Json run(CreatureObject* c,const Json& request){
  auto id=request.at("ability_id").get<std::string>();auto spec=corecu::fencer::ability(id);refresh(c);auto w=c->getWeapon();
  if(!learned(c,id) || !conditions(c,id) || std::to_string(w->getObjectID())!=request.at("item_id").get<std::string>() || !w->isASubChildOf(c))throw std::runtime_error("native_fencer_unavailable");
  if(cooldown(c,id)>0)throw std::runtime_error("native_fencer_cooldown");
  auto source=dynamic_cast<const CombatQueueCommand*>(c->getZoneServer()->getObjectController()->getQueueCommand("attack"));
  if(!source || !source->checkStateMask(c) || !source->checkInvalidLocomotions(c))throw std::runtime_error("native_fencer_attack_unavailable");
  auto p=c->getWorldPosition();corecu::warcry::Vec feet{{p.getX(),p.getZ(),p.getY()}},o{},d{};
  for(auto key:{"origin","direction"}){const auto& v=request.at(key);if(!v.is_array() || v.size()!=3)throw std::runtime_error("invalid_fencer_pose");for(int i=0;i<3;++i)if(!v[i].is_number())throw std::runtime_error("invalid_fencer_pose");}
  for(int i=0;i<3;++i){o[i]=request["origin"][i].get<double>();d[i]=request["direction"][i].get<double>();}
  if(!corecu::warcry::validPose(o,d,feet))throw std::runtime_error("invalid_fencer_pose");
  const std::string bound=request.value("target_id",std::string());if((spec.gesture || spec.ultimate)?!bound.empty():bound.empty())throw std::runtime_error("invalid_fencer_target");
  double range=corecu::melee::reach(w->getMaxRange(),false);
  std::vector<ManagedReference<AiAgent*>> targets;
  if(!spec.ultimate){SortedVector<TreeEntry*> nearby(32,32);c->getZone()->getInRangeObjects(p.getX(),p.getZ(),p.getY(),range,&nearby,true);
   for(int i=0;i<nearby.size();++i){auto obj=static_cast<SceneObject*>(nearby.get(i));if(!obj->isAiAgent())continue;auto a=obj->asAiAgent();Locker lock(a,c);
    if(!bound.empty() && std::to_string(a->getObjectID())!=bound)continue;
    if(eligible(c,a,feet,d,range,spec.gesture?.866025403784:.5) && targetReady(a,id))targets.push_back(a);
   }
   std::sort(targets.begin(),targets.end(),[&](const ManagedReference<AiAgent*>& a,const ManagedReference<AiAgent*>& b){bool av=corecu::volley::guaranteed(c->getObjectID(),a->getObjectID()),bv=corecu::volley::guaranteed(c->getObjectID(),b->getObjectID());if(av!=bv)return av;double x=c->getDistanceTo(a),y=c->getDistanceTo(b);return x==y?a->getObjectID()<b->getObjectID():x<y;});
   if(targets.empty())throw std::runtime_error("native_fencer_target_unavailable");
  }
  auto pay=[&](){if(c->getHAM(3)<=spec.action || c->getHAM(6)<=spec.mind)throw std::runtime_error("native_fencer_insufficient_sac");c->inflictDamage(c,3,spec.action,false,true,false);c->inflictDamage(c,6,spec.mind,false,true,false);c->addCooldown(String(("corecu_fencer_"+id).c_str()),int(spec.cooldown*1000));};
  Json out={{"success",true},{"shot_id",request.at("shot_id")},{"ability_id",id},{"interval_seconds",interval(c,spec)},{"hit",false},{"damage",0}};
  if(spec.ultimate){pay();addBuff(c,STRING_HASHCODE("swgxr_flawless_assault"),corecu::fencer::UltimateSeconds);return out;}
  auto a=targets.front();Locker lock(a,c);
  if(!eligible(c,a,feet,d,range,spec.gesture?.866025403784:.5) || !targetReady(a,id) || c->getWeapon()!=w)throw std::runtime_error("native_fencer_target_unavailable");
  pay();int total=0;
  for(int blow=0;blow<spec.blows;++blow){if(!eligible(c,a,feet,d,range,spec.gesture?.866025403784:.5))break;
   SwgxrTkaStrike strike(*source,spec.damage);strike.setRange(int(std::ceil(range)));int before=a->getHAM(0);c->setTargetID(0,true);int code=strike.doCombatAction(c,a->getObjectID(),"",w);c->setTargetID(0,true);if(code==QueueCommand::SUCCESS)total+=std::max(0,before-a->getHAM(0));
  }
  effects(c,a,id,total);out["target_id"]=std::to_string(a->getObjectID());out["hit"]=total>0;out["damage"]=total;return out;
 }
};
