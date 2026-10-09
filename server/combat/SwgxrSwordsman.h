#pragma once
#include "VolleyFirePolicy.h"
#include "SwordsmanPolicy.h"
#include "SwgxrTka.h"
#include "MeleePolicy.h"
class SwgxrSwordsman {
 using Json=JSONSerializationType;
 static bool eligible(CreatureObject* c,AiAgent* a,const corecu::warcry::Vec& feet,const corecu::warcry::Vec& d,double range,double cosine){
  corecu::tka::Attack shape{range,cosine,0,0,0,1,1,0,0};
  if(!a || a->getZone()!=c->getZone() || a->isPet() || a->isDead() || a->isIncapacitated() || !a->isAttackableBy(c))return false;
  if(corecu::volley::guaranteed(c->getObjectID(),a->getObjectID()))return corecu::volley::inRange(c->getDistanceTo(a),range);
  auto p=a->getWorldPosition();return corecu::tka::inCone(feet,d,{{p.getX(),p.getZ(),p.getY()}},shape) && CollisionManager::checkLineOfSight(c,a);
 }
 static bool targetReady(AiAgent* a,const std::string& id){
  if(id=="decisive_strike")return corecu::swordsman::executeReady(a->getHAM(0),a->getMaxHAM(0)-a->getWounds(0),a->getLevel(),CoreCuCombat::boss(a));
  if(id=="armour_break")return !a->hasBuff(STRING_HASHCODE("swgxr_fractured_armour"));
  return !corecu::swordsman::ability(id).control || a->checkCooldownRecovery("corecu_control_recovery");
 }
 static void effects(CreatureObject* c,AiAgent* a,const std::string& id,int damage){
  if(damage<=0 || a->isDead() || a->isIncapacitated())return;
  if(id=="armour_break"){
   // Target is locked; do not refresh or stack another Swordsman's opening.
   if(a->hasBuff(STRING_HASHCODE("swgxr_fractured_armour")))return;
   ManagedReference<Buff*> buff=new Buff(a,STRING_HASHCODE("swgxr_fractured_armour"),corecu::swordsman::FractureSeconds,BuffType::STATE);Locker lock(buff,a);a->addBuff(buff);
  }else if(id=="rending_cut"){
   int strength=corecu::dotTickBudget(damage,1,20,20,damage*.4);
   if(strength>0)a->addDotState(c,CreatureState::BLEEDING,STRING_HASHCODE("swgxr_rending_cut"),strength,0,20,95,a->getSkillMod("bleeding_defense"));
  }else if(corecu::swordsman::ability(id).control){
   a->addCooldown("corecu_control_recovery",8000);
   double rating=CoreCuCombat::rating(a,corecu::Snare,a->getSkillMod(id=="disrupting_blow"?"warcry_defense":"resistance_states"));
   if(System::random(99)>=corecu::statusChance(95,rating))return;
   if(id=="disrupting_blow")a->setNextAttackDelay(c,"swgxr_disrupting_blow",0,corecu::statusDuration(3,rating));
   else{ManagedReference<Buff*> buff=new Buff(a,STRING_HASHCODE("swgxr_hamstring"),corecu::statusDuration(5,rating),BuffType::STATE);Locker lock(buff,a);buff->setSkillModifier("private_swgxr_hamstring",30);a->addBuff(buff);}
  }
 }
public:
 static bool compatible(CreatureObject* c){auto w=c->getWeapon();return w && w->isTwoHandMeleeWeapon() && !w->isJediTwoHandedWeapon() && w->isCertifiedFor(c) && !w->isBroken();}
 static bool learned(CreatureObject* c,const std::string& id){auto a=corecu::swordsman::ability(id);return a.damage>0 && c->hasSkill("combat_2hsword_novice") && c->hasSkill(a.skill);}
 static bool conditions(CreatureObject* c){return compatible(c) && c->getPosture()==0 && !c->isDead() && !c->isIncapacitated() && !c->isRidingMount();}
 static double cooldown(CreatureObject* c,const std::string& id){auto t=c->getCooldownTime(String(("corecu_swordsman_"+id).c_str()));return t?std::max(0.,-t->miliDifference()/1000.):0.;}
 static double interval(CreatureObject* c,const corecu::swordsman::Ability& a){return std::max(a.recovery,double(CombatManager::instance()->calculateWeaponAttackSpeed(c,c->getWeapon(),1)));}
 static Json snapshot(CreatureObject* c){Json out=Json::object();for(auto id:{"rending_cut","disrupting_blow","hamstring","decisive_strike","overhead_cleave","ground_slam","armour_break"}){auto a=corecu::swordsman::ability(id);out[id]={{"learned",learned(c,id)},{"conditions_met",conditions(c)},{"cooldown_remaining_seconds",cooldown(c,id)},{"cooldown_seconds",a.cooldown},{"action_cost",a.action},{"mind_cost",a.mind},{"interval_seconds",c->getWeapon()?interval(c,a):a.recovery}};}return out;}
 static Json abilities(CreatureObject* c){Json out=Json::array();if(!compatible(c))return out;auto state=snapshot(c);
  for(auto id:{"rending_cut","disrupting_blow","hamstring","decisive_strike","overhead_cleave","ground_slam","armour_break"}){if(!learned(c,id))continue;auto a=corecu::swordsman::ability(id);auto row=state[id];std::string key=id;
   row["id"]=id;row["label"]=a.label;row["activation"]=a.gesture?"swordsman_gesture":"native_melee";row["ultimate"]=a.ultimate;row["sac_policy"]="fixed";row["base_sac"]={{"health",0},{"action",a.action},{"mind",a.mind}};row["damage_multiplier"]=a.damage;row["max_range_m"]=corecu::melee::reach(c->getWeapon()->getMaxRange(),false);row["requires_control_available"]=a.control;
   row["description"]=key=="rending_cut"?"Strong hit and a non-stacking Health bleed, budgeted from landed damage.":key=="disrupting_blow"?"Moderate damage and a resisted brief attack delay; shared control recovery applies.":key=="hamstring"?"Moderate damage and a resisted brief movement slow; shared control recovery applies.":key=="decisive_strike"?"Finisher below 30% Health. Damage tapers from 3x at combat level 30 or below to 1.25x at 150. Ineffective against bosses.":key=="overhead_cleave"?"Heavy single-target strike. Uses native weapon recovery, with a 2-second minimum.":key=="ground_slam"?"Strong primary hit and weak collateral on up to two nearby enemies. No bonus threat or hard control.":"Heavy hit opens an 8-second window of 50% lower Kinetic/Energy armour scores. Allies benefit. Cannot stack or refresh an active opening.";
   row["weapon_requirement"]="Certified two-handed melee weapon; Swordsman training required.";
   if(a.gesture){row["category"]="gesture";row["trigger_description"]=key=="overhead_cleave"?"Hold with both hands, release triggers, raise above your head and make a committed downward strike.":"Hold with both hands and triggers released. From a lower ready position, drive down toward the virtual ground point ahead; stop above the physical floor.";}
   if(a.ultimate){row["required_profession_skill"]="combat_2hsword_master";row["profession_requirement"]="Master Swordsman";row["trigger_description"]="Hold the weapon with both hands, aim at the enemy, release both triggers, then press both together.";}
   if(key=="decisive_strike"){row["target_health_below"]=.3;row["excludes_bosses"]=true;}
   out.push_back(row);
  }return out;
 }
 static Json run(CreatureObject* c,const Json& request){
  auto id=request.at("ability_id").get<std::string>();auto spec=corecu::swordsman::ability(id);auto w=c->getWeapon();
  if(!learned(c,id) || !conditions(c) || std::to_string(w->getObjectID())!=request.at("item_id").get<std::string>() || !w->isASubChildOf(c))throw std::runtime_error("native_swordsman_unavailable");
  if(cooldown(c,id)>0)throw std::runtime_error("native_swordsman_cooldown");
  auto source=dynamic_cast<const CombatQueueCommand*>(c->getZoneServer()->getObjectController()->getQueueCommand("attack"));
  if(!source || !source->checkStateMask(c) || !source->checkInvalidLocomotions(c))throw std::runtime_error("native_swordsman_attack_unavailable");
  auto p=c->getWorldPosition();corecu::warcry::Vec feet{{p.getX(),p.getZ(),p.getY()}},o{},d{};
  for(auto key:{"origin","direction"}){const auto& v=request.at(key);if(!v.is_array() || v.size()!=3)throw std::runtime_error("invalid_swordsman_pose");for(int i=0;i<3;++i)if(!v[i].is_number())throw std::runtime_error("invalid_swordsman_pose");}
  for(int i=0;i<3;++i){o[i]=request["origin"][i].get<double>();d[i]=request["direction"][i].get<double>();}
  if(!corecu::warcry::validPose(o,d,feet))throw std::runtime_error("invalid_swordsman_pose");
  const std::string bound=request.value("target_id",std::string());if(spec.gesture?!bound.empty():bound.empty())throw std::runtime_error("invalid_swordsman_target");
  double range=corecu::melee::reach(w->getMaxRange(),false);if(id=="ground_slam")range=std::min(range,2.5);
  std::vector<ManagedReference<AiAgent*>> targets;SortedVector<TreeEntry*> nearby(32,32);c->getZone()->getInRangeObjects(p.getX(),p.getZ(),p.getY(),range,&nearby,true);
  for(int i=0;i<nearby.size();++i){auto obj=static_cast<SceneObject*>(nearby.get(i));if(!obj->isAiAgent())continue;auto a=obj->asAiAgent();Locker lock(a,c);
   if(!bound.empty() && std::to_string(a->getObjectID())!=bound)continue;
   if(eligible(c,a,feet,d,range,spec.gesture?.866025403784:.5) && targetReady(a,id))targets.push_back(a);
  }
  std::sort(targets.begin(),targets.end(),[&](const ManagedReference<AiAgent*>& a,const ManagedReference<AiAgent*>& b){bool av=corecu::volley::guaranteed(c->getObjectID(),a->getObjectID()),bv=corecu::volley::guaranteed(c->getObjectID(),b->getObjectID());if(av!=bv)return av;double x=c->getDistanceTo(a),y=c->getDistanceTo(b);return x==y?a->getObjectID()<b->getObjectID():x<y;});
  if(targets.empty())throw std::runtime_error("native_swordsman_target_unavailable");
  // Hold the primary lock through validation and spending; changed boss/Health/buff gates cannot consume SAC.
  auto primary=targets.front();Locker primaryLock(primary,c);
  if(!eligible(c,primary,feet,d,range,spec.gesture?.866025403784:.5) || !targetReady(primary,id) || c->getWeapon()!=w)throw std::runtime_error("native_swordsman_target_unavailable");
  if(c->getHAM(3)<=spec.action || c->getHAM(6)<=spec.mind)throw std::runtime_error("native_swordsman_insufficient_sac");
  c->inflictDamage(c,3,spec.action,false,true,false);c->inflictDamage(c,6,spec.mind,false,true,false);c->addCooldown(String(("corecu_swordsman_"+id).c_str()),int(spec.cooldown*1000));
  Json out={{"success",true},{"shot_id",request.at("shot_id")},{"ability_id",id},{"interval_seconds",interval(c,spec)},{"hit",false},{"damage",0},{"targets",Json::array()}};
  int total=0;auto hit=[&](AiAgent* a,double multiplier){
   SwgxrTkaStrike strike(*source,multiplier);strike.setRange(int(std::ceil(range)));int before=a->getHAM(0);c->setTargetID(0,true);int code=strike.doCombatAction(c,a->getObjectID(),"",w);c->setTargetID(0,true);int damage=std::max(0,before-a->getHAM(0));
   if(code==QueueCommand::SUCCESS)effects(c,a,id,damage);total+=damage;out["targets"].push_back({{"id",std::to_string(a->getObjectID())},{"damage",damage},{"native_result",code}});
  };
  hit(primary,id=="decisive_strike"?corecu::swordsman::executionMultiplier(primary->getLevel(),CoreCuCombat::boss(primary)):spec.damage);
  primaryLock.release();
  if(id=="ground_slam"){int count=1;for(auto a:targets){if(a==primary)continue;if(count>=3)break;Locker lock(a,c);
   if(!eligible(c,a,feet,d,range,.866025403784))continue;hit(a,.35);++count;
  }}
  out["hit"]=total>0;out["damage"]=total;return out;
 }
};
