#pragma once
#include "VolleyFirePolicy.h"
#include "PistoleerPolicy.h"
#include "CommandoPolicy.h"
#include "SwgxrTka.h"
#include "ProjectileContactPolicy.h"
class SwgxrPistoleer {
 using Json=JSONSerializationType;
 static bool eligible(CreatureObject* c,AiAgent* a,const corecu::warcry::Vec& origin,const corecu::warcry::Vec& direction,double range){
  if(!a || a->getZone()!=c->getZone() || !targetReady(a) || !a->isAttackableBy(c))return false;
  if(corecu::volley::guaranteed(c->getObjectID(),a->getObjectID()))return corecu::volley::inRange(c->getDistanceTo(a),range);
  auto p=a->getWorldPosition();double dx=p.getX()-origin[0],dy=p.getZ()-origin[1],dz=p.getY()-origin[2];
  // Target body centre keeps muzzle-height fanning usable against human-sized enemies.
  dy+=std::max(.25,std::min(1.,double(a->getHeight(false))*.65));double distance=std::sqrt(dx*dx+dy*dy+dz*dz);
  return distance<=range && (distance<.001 || (dx*direction[0]+dy*direction[1]+dz*direction[2])/distance>=.866025403784) && CollisionManager::checkLineOfSight(c,a);
 }
public:
 static bool compatible(CreatureObject* c){auto w=c->getWeapon();return w && w->isPistolWeapon() && corecu::commando::classify(w->getObjectTemplate()->getFullTemplateString().toCharArray())==corecu::commando::None && w->isCertifiedFor(c) && !w->isBroken();}
 static bool learned(CreatureObject* c,const std::string& id){
  if(!corecu::pistoleer::contains(id) || !c->hasSkill("combat_pistol_novice") || !c->getPlayerObject())return false;
  if(id=="run_and_gun")return c->hasSkill("combat_pistol_support_02");if(id=="showdown")return c->hasSkill("combat_pistol_master");
  return c->getPlayerObject()->hasAbility(corecu::pistoleer::ability(id).grant) || (id=="disarming_shot" && c->getPlayerObject()->hasAbility("disarmingShot2"));
 }
 static bool targetReady(CreatureObject* a){return a && a->isAiAgent() && !a->asAiAgent()->isPet() && !a->isDead() && !a->isIncapacitated();}
 static bool active(CreatureObject* c){return compatible(c) && learned(c,"run_and_gun") && !c->isDead() && !c->isIncapacitated() && c->hasBuff(STRING_HASHCODE("swgxr_run_and_gun"));}
 static void refresh(CreatureObject* c){if(!compatible(c) || !learned(c,"run_and_gun") || c->isDead() || c->isIncapacitated())c->removeBuff(STRING_HASHCODE("swgxr_run_and_gun"));}
 static bool conditions(CreatureObject* c,const std::string& id){return compatible(c) && !c->isDead() && !c->isIncapacitated() && !c->isRidingMount() && (id!="run_and_gun" || !active(c));}
 static double cooldown(CreatureObject* c,const std::string& id){auto t=c->getCooldownTime(String(("swgxr_smuggler_"+id).c_str()));return t?std::max(0.,-t->miliDifference()/1000.):0.;}
 static double interval(CreatureObject* c,const std::string& id){double native=c->getWeapon()?double(CombatManager::instance()->calculateWeaponAttackSpeed(c,c->getWeapon(),1)):1.5;return id=="run_and_gun"?.25:corecu::pistoleer::ability(id).gesture?std::max(native,1.5):corecu::pistoleer::fireInterval(native,active(c),id);}
 static double costScale(CreatureObject* c,const std::string& id){return corecu::pistoleer::costScale(active(c),id);}
 static void effects(CreatureObject* c,CreatureObject* a,const std::string& id,int damage){
  if(damage<=0 || !targetReady(a) || (id!="disarming_shot" && id!="showdown") || a->hasEffectImmunity(CommandEffect::INTIMIDATE))return;
  double rating=CoreCuCombat::rating(a,corecu::Intimidate,a->getSkillMod("intimidate_defense"));if(System::random(99)>=corecu::statusChance(85,rating))return;
  const bool ultimate=id=="showdown";
  ManagedReference<Buff*> buff=new Buff(a,ultimate?STRING_HASHCODE("swgxr_showdown"):STRING_HASHCODE("swgxr_disarming_shot"),corecu::statusDuration(ultimate?5:6,rating),BuffType::STATE);Locker lock(buff,a);
  buff->setSkillModifier(ultimate?"private_pistoleer_showdown":"private_pistoleer_disarming",ultimate?30:20);a->addBuff(buff);
 }
 static Json snapshot(CreatureObject* c){refresh(c);Json out=Json::object();for(auto id:{"double_tap","disarming_shot","fan_shot","run_and_gun","showdown"}){auto a=corecu::pistoleer::ability(id);out[id]={{"learned",learned(c,id)},{"conditions_met",conditions(c,id)},{"cooldown_remaining_seconds",cooldown(c,id)},{"cooldown_seconds",a.cooldown},{"action_cost",corecu::pistoleer::cost(a.action,active(c),id)},{"mind_cost",corecu::pistoleer::cost(a.mind,active(c),id)},{"interval_seconds",interval(c,id)}};}
  auto buff=c->getBuff(STRING_HASHCODE("swgxr_run_and_gun"));auto& row=out["run_and_gun"];row["active"]=active(c);row["active_remaining_seconds"]=active(c) && buff?std::max(0.f,buff->getTimeLeft()):0.;row["duration_seconds"]=corecu::pistoleer::BuffSeconds;row["ordinary_fire_rate_multiplier"]=1.25;row["special_cost_multiplier"]=.75;return out;
 }
 static Json abilities(CreatureObject* c){Json out=Json::array();if(!compatible(c))return out;auto state=snapshot(c);auto w=c->getWeapon();
  for(auto id:{"double_tap","disarming_shot","fan_shot","run_and_gun","showdown"}){if(!learned(c,id))continue;auto a=corecu::pistoleer::ability(id);auto row=state[id];std::string key=id;
   row["id"]=id;row["label"]=a.label;row["activation"]=a.gesture?"pistoleer_gesture":"native_ranged";row["ultimate"]=a.ultimate;row["native_authority"]=true;row["source_command"]="attack";row["sac_policy"]="fixed";row["base_sac"]={{"health",0},{"action",row["action_cost"]},{"mind",row["mind_cost"]}};row["damage_multiplier"]=a.damage;row["hit_count"]=key=="showdown"?3:a.blows;row["max_range_m"]=key=="fan_shot"?corecu::pistoleer::fanRange(w->getMaxRange()):w->getMaxRange();row["min_range_m"]=0;row["ammo_cost"]=key=="double_tap"?2:key=="fan_shot"?3:key=="run_and_gun"?0:1;
   row["weapon_requirement"]="Certified pistol and corresponding Pistoleer training. Pistols add no movement spread.";
   row["description"]=key=="double_tap"?"One physical contact resolves two 0.8x hits on the selected enemy; each retains normal secondary defenses.":key=="disarming_shot"?"Light hit and a resisted 20% enemy damage reduction for up to 6 seconds. Strongest suppression wins; no weapon removal.":key=="fan_shot"?"The Pistoleer's sole damaging AoE: a 60-degree muzzle cone, up to 12 metres and five nearest eligible enemies with line of sight. One 1.0x hit each; no extra states.":key=="run_and_gun"?"For 8 seconds, ordinary pistol firing is 25% faster and regular single-target pistol specials cost 25% less Action/Mind. Fan Shot and ultimates are unchanged.":"Three separately aimed 0.9x projectiles at one designated enemy, spaced 0.25 seconds apart. The first damaging impact attempts a resisted 30% outgoing damage reduction for up to 5 seconds; strongest suppression wins.";
   if(a.gesture){row["category"]="gesture";row["trigger_description"]=key=="fan_shot"?"With triggers and free offhand grip released, make two cowboy cock-fanning strokes above the held pistol's rear/top.":"With triggers released, hold a low hipfire pistol and extend the free arm sideways, or hold the pistol high and rolled sideways, for 0.8 seconds. Both poses share this buff and cooldown.";}
   if(key=="run_and_gun"){row["self_only"]=true;row["required_profession_skill"]="combat_pistol_support_02";}
   if(a.ultimate){row["interval_seconds"]=corecu::pistoleer::VolleySpacing;row["required_profession_skill"]="combat_pistol_master";row["profession_requirement"]="Master Pistoleer";row["volley_shots"]=3;row["volley_interval_seconds"]=corecu::pistoleer::VolleySpacing;row["trigger_description"]="Support the pistol, release both triggers, then press both together. Keep physically aiming at the designated enemy through the three-shot volley.";}
   out.push_back(row);
  }return out;
 }
 static Json run(CreatureObject* c,const Json& request){
  auto id=request.at("ability_id").get<std::string>();auto spec=corecu::pistoleer::ability(id);refresh(c);auto w=c->getWeapon();
  if(!spec.gesture || !learned(c,id) || !conditions(c,id) || std::to_string(w->getObjectID())!=request.at("item_id").get<std::string>() || !w->isASubChildOf(c))throw std::runtime_error("native_pistoleer_unavailable");
  if(cooldown(c,id)>0)throw std::runtime_error("native_pistoleer_cooldown");
  auto source=dynamic_cast<const CombatQueueCommand*>(c->getZoneServer()->getObjectController()->getQueueCommand("attack"));if(!source || !source->checkStateMask(c) || !source->checkInvalidLocomotions(c))throw std::runtime_error("native_pistoleer_attack_unavailable");
  auto p=c->getWorldPosition();corecu::warcry::Vec feet{{p.getX(),p.getZ(),p.getY()}},o{},d{};
  for(auto key:{"origin","direction"}){const auto& v=request.at(key);if(!v.is_array() || v.size()!=3)throw std::runtime_error("invalid_pistoleer_pose");for(int i=0;i<3;++i)if(!v[i].is_number())throw std::runtime_error("invalid_pistoleer_pose");}
  for(int i=0;i<3;++i){o[i]=request["origin"][i].get<double>();d[i]=request["direction"][i].get<double>();}if(!corecu::pistoleer::validPose(o,d,feet))throw std::runtime_error("invalid_pistoleer_pose");
  double length=std::sqrt(d[0]*d[0]+d[1]*d[1]+d[2]*d[2]);for(auto& axis:d)axis/=length;
  if(!request.value("target_id",std::string()).empty())throw std::runtime_error("invalid_pistoleer_target");
  const double range=corecu::pistoleer::fanRange(w->getMaxRange()*corecu::projectile::rangeScale(true,false));
  std::vector<ManagedReference<AiAgent*>> targets;
  if(id=="fan_shot"){SortedVector<TreeEntry*> nearby(32,32);c->getZone()->getInRangeObjects(p.getX(),p.getZ(),p.getY(),range+3,&nearby,true);
   for(int i=0;i<nearby.size();++i){auto obj=static_cast<SceneObject*>(nearby.get(i));if(!obj->isAiAgent())continue;auto a=obj->asAiAgent();Locker lock(a,c);if(eligible(c,a,o,d,range))targets.push_back(a);}
   std::sort(targets.begin(),targets.end(),[&](const ManagedReference<AiAgent*>& a,const ManagedReference<AiAgent*>& b){bool av=corecu::volley::guaranteed(c->getObjectID(),a->getObjectID()),bv=corecu::volley::guaranteed(c->getObjectID(),b->getObjectID());if(av!=bv)return av;auto x=a->getWorldPosition(),y=b->getWorldPosition();double ax=x.getX()-o[0],ay=x.getZ()-o[1],az=x.getY()-o[2],bx=y.getX()-o[0],by=y.getZ()-o[1],bz=y.getY()-o[2];double ad=ax*ax+ay*ay+az*az,bd=bx*bx+by*by+bz*bz;return ad==bd?a->getObjectID()<b->getObjectID():ad<bd;});
  }
  if(c->getWeapon()!=w || !conditions(c,id))throw std::runtime_error("native_pistoleer_unavailable");
  if(c->getHAM(3)<=spec.action || c->getHAM(6)<=spec.mind)throw std::runtime_error("native_pistoleer_insufficient_sac");c->inflictDamage(c,3,spec.action,false,true,false);c->inflictDamage(c,6,spec.mind,false,true,false);c->addCooldown(String(("swgxr_smuggler_"+id).c_str()),spec.cooldown*1000);
  Json out={{"success",true},{"operation","pistoleer"},{"shot_id",request.at("shot_id")},{"ability_id",id},{"interval_seconds",interval(c,id)},{"hit",false},{"damage",0},{"targets",Json::array()}};
  if(id=="run_and_gun"){ManagedReference<Buff*> buff=new Buff(c,STRING_HASHCODE("swgxr_run_and_gun"),corecu::pistoleer::BuffSeconds,BuffType::STATE);Locker lock(buff,c);c->addBuff(buff);return out;}
  int total=0,count=0;for(auto& a:targets){if(count>=corecu::pistoleer::FanTargets)break;Locker lock(a,c);if(c->getWeapon()!=w || !eligible(c,a,o,d,range))continue;
   SwgxrTkaStrike strike(*source,spec.damage);strike.setRange(int(std::ceil(range+3)));int before=a->getHAM(0);c->setTargetID(0,true);int code=strike.doCombatAction(c,a->getObjectID(),"",w);c->setTargetID(0,true);int damage=code==QueueCommand::SUCCESS?std::max(0,before-a->getHAM(0)):0;total+=damage;++count;out["targets"].push_back({{"target_id",std::to_string(a->getObjectID())},{"damage",damage},{"native_result",code}});
  }out["hit"]=total>0;out["damage"]=total;return out;
 }
};
