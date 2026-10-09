#pragma once
#include "VolleyFirePolicy.h"
#include "server/zone/objects/group/GroupObject.h"
#include "server/zone/objects/player/PlayerObject.h"
#include "server/zone/managers/collision/CollisionManager.h"
#include "system/thread/Mutex.h"
#include <chrono>
#include <memory>
class SwgxrVolleyFire {
 using Json=JSONSerializationType;
 struct State {corecu::volley::Mark mark;std::set<uint64> reserved;};
 static Mutex& mutex(){static Mutex value;return value;}
 static std::map<uint64,State>& marks(){static std::map<uint64,State> value;return value;}
 static long long millis(){return std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::system_clock::now().time_since_epoch()).count();}
 static double now(){return millis()/1000.;}
 static std::string id(SceneObject* o){return o?std::to_string(o->getObjectID()):"";}
 static uint64 zone(CreatureObject* c){return c->getZone()?c->getZone()->getObjectID():0;}
 static bool ready(CreatureObject* c){return c && c->isPlayerCreature() && c->isOnline() && c->getZone() && !c->isDead() && !c->isIncapacitated();}
 static bool enemy(CreatureObject* c,TangibleObject* target){return target && target!=c && target->getZone()==c->getZone() && !target->isDestroyed() && target->isAttackableBy(c) && (target->isLairObject() || (target->isAiAgent() && !target->asAiAgent()->isPet() && !target->asAiAgent()->isDead() && !target->asAiAgent()->isIncapacitated()));}
 static void prune(){auto stamp=now();for(auto it=marks().begin();it!=marks().end();)if(it->second.mark.expires<=stamp)it=marks().erase(it);else ++it;}
 static Json position(SceneObject* target){auto p=target->getWorldPosition();return Json::array({p.getX(),p.getZ(),p.getY()});}
 static void finish(CreatureObject* c,const std::string& markID,uint64 group,bool consumed){Locker guard(&mutex(),c);auto found=marks().find(group);if(found==marks().end() || found->second.mark.id!=markID)return;found->second.reserved.erase(c->getObjectID());if(consumed)found->second.mark.spent.insert(c->getObjectID());}
public:
 static bool learned(CreatureObject* c){return c->hasSkill("outdoors_squadleader_master") && c->getPlayerObject() && c->getPlayerObject()->hasAbility("volleyFire");}
 static double cooldown(CreatureObject* c){auto raw=c->getPlayerObject()->getScreenPlayData("swgxr_volley_fire","until_ms");if(raw.isEmpty())return 0;try{return std::max(0.,std::min(corecu::volley::Cooldown,(std::stoll(raw.toCharArray())-millis())/1000.));}catch(...){return corecu::volley::Cooldown;}}
 static double receivedCooldown(CreatureObject* c){auto raw=c->getPlayerObject()->getScreenPlayData("swgxr_volley_fire","received_until_ms");if(raw.isEmpty())return 0;try{return std::max(0.,std::min(corecu::volley::Cooldown,(std::stoll(raw.toCharArray())-millis())/1000.));}catch(...){return corecu::volley::Cooldown;}}
 static Json snapshot(CreatureObject* c){
  Json out={{"learned",learned(c)},{"conditions_met",ready(c)&&c->isGrouped()&&!c->isRidingMount()},{"cooldown_seconds",corecu::volley::Cooldown},{"cooldown_remaining_seconds",cooldown(c)},{"duration_seconds",corecu::volley::Duration},{"recipient_cooldown_remaining_seconds",receivedCooldown(c)},{"action_cost",corecu::volley::Action},{"mind_cost",corecu::volley::Mind},{"range_m",corecu::volley::CastRange},{"mark",nullptr}};
  Locker guard(&mutex(),c);prune();auto found=marks().find(c->getGroupID());if(found==marks().end() || !ready(c) || !found->second.mark.permits(c->getObjectID(),c->getGroupID(),zone(c),now()))return out;
  auto& mark=found->second.mark;auto object=c->getZoneServer()->getObject(mark.target);auto target=object && object->isTangibleObject()?object->asTangibleObject():nullptr;if(!target)return out;Locker targetLock(target,c);if(!enemy(c,target))return out;
  out["mark"]={{"id",mark.id},{"target_id",std::to_string(mark.target)},{"remaining_seconds",std::max(0.,mark.expires-now())},{"position",position(target)},{"height",target->isCreatureObject()?target->asCreatureObject()->getHeight(false):2.},{"range_m",corecu::volley::CastRange},{"charges",1},{"per_member",true}};return out;
 }
 static Json abilities(CreatureObject* c){Json out=Json::array();auto w=c->getWeapon();if(!learned(c) || !w || (!w->isMeleeWeapon()&&!w->isRangedWeapon()))return out;auto row=snapshot(c);row.erase("mark");row["id"]="volley_fire";row["label"]="Volley Fire";row["native_family"]="squad_leader";row["activation"]="squad_leader_ultimate";row["ultimate"]=true;row["native_authority"]=true;row["required_profession_skill"]="outdoors_squadleader_master";row["profession_requirement"]="Master Squad Leader";row["sac_policy"]="fixed";row["base_sac"]={{"health",0},{"action",corecu::volley::Action},{"mind",corecu::volley::Mind}};row["max_range_m"]=corecu::volley::CastRange;row["min_range_m"]=0;row["ammo_cost"]=0;row["damage_multiplier"]=0;row["interval_seconds"]=1.;row["weapon_requirement"]="Any certified equipped weapon, including unarmed.";row["trigger_description"]="Aim at an enemy and use the selected ultimate chord.";row["description"]="Mark one enemy for 12 seconds. Each current eligible party member can consume their own reticle with one accepted attack within that attack's native range. It hits without an aim or avoidance roll; normal damage, armour, supply and costs remain. Cooldown 120 seconds.";out.push_back(row);return out;}
 static Json activate(CreatureObject* c,const Json& request){
  if(!learned(c) || !ready(c) || !c->isGrouped() || c->isRidingMount())throw std::runtime_error("native_volley_fire_unavailable");auto w=c->getWeapon();if(!w || !w->isCertifiedFor(c) || w->isBroken() || id(w)!=request.at("item_id").get<std::string>() || (!w->isUnarmedWeapon()&&!w->isASubChildOf(c)))throw std::runtime_error("native_volley_weapon_unavailable");
  if(cooldown(c)>0)throw std::runtime_error("native_volley_fire_cooldown");auto object=c->getZoneServer()->getObject(std::stoull(request.at("target_id").get<std::string>()));auto target=object && object->isTangibleObject()?object->asTangibleObject():nullptr;if(!target)throw std::runtime_error("native_volley_target_unavailable");
  {Locker lock(target,c);if(!enemy(c,target) || target->getParentID()!=c->getParentID() || !corecu::volley::inRange(c->getDistanceTo(target),corecu::volley::CastRange) || !CollisionManager::checkLineOfSight(c,target))throw std::runtime_error("native_volley_target_unavailable");}
  corecu::volley::Mark fresh;auto group=c->getGroup();{Locker groupLock(group,c);if(c->getGroup()!=group)throw std::runtime_error("native_volley_group_changed");fresh.group=group->getObjectID();for(int i=0;i<group->getGroupSize();++i){auto member=group->getGroupMember(i);if(ready(member)&&member->getZone()==c->getZone()&&receivedCooldown(member)<=0)fresh.members[member->getObjectID()]=corecu::volley::epoch(member->getObjectID());}}
  bool other=false;for(const auto& member:fresh.members)other=other||member.first!=c->getObjectID();if(!other)throw std::runtime_error("native_volley_party_required");if(c->getHAM(3)<=corecu::volley::Action || c->getHAM(6)<=corecu::volley::Mind)throw std::runtime_error("native_volley_insufficient_sac");
  Locker guard(&mutex(),c);prune();if(cooldown(c)>0)throw std::runtime_error("native_volley_fire_cooldown");auto previous=marks().find(fresh.group);if(previous!=marks().end())throw std::runtime_error("native_volley_fire_already_active");
  fresh.id="volley_"+id(c)+"_"+std::to_string(millis());fresh.caster=c->getObjectID();fresh.casterEpoch=corecu::volley::epoch(fresh.caster);fresh.target=target->getObjectID();fresh.zone=zone(c);fresh.expires=now()+corecu::volley::Duration;
  // Receiving the ultimate starts a persistent shared recipient recovery; a
  // second Squad Leader cannot chain fresh accuracy charges onto this member.
  for(const auto& member:fresh.members){auto object=c->getZoneServer()->getObject(member.first);if(!object || !object->isCreatureObject())continue;auto recipient=object->asCreatureObject();Locker lock(recipient,c);recipient->getPlayerObject()->setScreenPlayData("swgxr_volley_fire","received_until_ms",String(std::to_string(millis()+int(corecu::volley::Cooldown*1000)).c_str()));}
  c->inflictDamage(c,3,corecu::volley::Action,false,true,false);c->inflictDamage(c,6,corecu::volley::Mind,false,true,false);c->getPlayerObject()->setScreenPlayData("swgxr_volley_fire","until_ms",String(std::to_string(millis()+int(corecu::volley::Cooldown*1000)).c_str()));marks()[fresh.group].mark=fresh;
  return {{"success",true},{"operation","squadleader"},{"shot_id",request.at("shot_id")},{"ability_id","volley_fire"},{"target_id",id(target)},{"volley_mark_id",fresh.id},{"eligible_members",fresh.members.size()},{"interval_seconds",1.},{"ham_cost_committed",true}};
 }
 // The reservation is atomic but never pins a world-object lock while another
 // attack is executing. Only the same member's charge is reserved. A native
 // resolved hit is terminal even if an exception interrupts its response.
 template<class Resolve> static Json attack(CreatureObject* c,const Json& request,double range,Resolve resolve){
  const bool marked=request.contains("volley_mark_id") || request.contains("volley_target_id");if(!marked)return resolve(nullptr);
  const auto markID=request.at("volley_mark_id").get<std::string>(),targetID=request.at("volley_target_id").get<std::string>();ManagedReference<TangibleObject*> target;uint64 group=c->getGroupID();
  {Locker guard(&mutex(),c);prune();auto found=marks().find(group);if(found==marks().end() || found->second.mark.id!=markID || std::to_string(found->second.mark.target)!=targetID || !ready(c) || !found->second.mark.permits(c->getObjectID(),group,zone(c),now()) || found->second.reserved.count(c->getObjectID()))throw std::runtime_error("native_volley_mark_unavailable");auto object=c->getZoneServer()->getObject(found->second.mark.target);target=object && object->isTangibleObject()?object->asTangibleObject():nullptr;if(!target)throw std::runtime_error("native_volley_target_unavailable");Locker targetLock(target,c);if(!enemy(c,target) || !corecu::volley::inRange(c->getDistanceTo(target),range))throw std::runtime_error("native_volley_target_out_of_range");found->second.reserved.insert(c->getObjectID());}
  corecu::volley::Scope scope(c->getObjectID(),target->getObjectID());
  try{Json out=resolve(target);bool consumed=scope.resolved() || out.value("volley_deferred",false);finish(c,markID,group,consumed);if(consumed){out["volley_consumed"]=true;out["volley_mark_id"]=markID;out["volley_target_id"]=targetID;}return out;}catch(...){finish(c,markID,group,scope.resolved());throw;}
 }
};
