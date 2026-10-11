#pragma once
#include "ActionCombatPolicy.h"
#include "AttackCommand.h"
#include "server/zone/objects/creature/ai/AiAgent.h"
#include "server/zone/objects/creature/ai/PatrolPoint.h"
#include "server/zone/managers/creature/CreatureManager.h"
#include "server/zone/packets/scene/AttributeListMessage.h"
#include <atomic>
#include <cstdlib>
#include <memory>
#include <mutex>

// All encounter mutation holds the owner and Engine encounter locks. The registry
// mutex is released before acquiring any Engine/object lock.
class SwgxrActionCombat {
 using Json=JSONSerializationType;
 using Role=corecu::action::Role;
 using Vec=corecu::action::Vec;
 struct Victim { ManagedWeakReference<CreatureObject*> actor; corecu::action::Attack contact; };
 struct Mob {
  ManagedReference<AiAgent*> actor;
  Role role=Role::Melee;
  corecu::action::Attack attack;
  ManagedReference<AiAgent*> healTarget;
  std::map<uint64,Victim> victims;
  double next=0,aimPublishedAt=0;
  uint64_t publishedRevision=0;
  std::string phase;
 };
 struct Encounter {
  Mutex mutex;
  uint64 id=0, serial=0;
  double expires=0,last=0;
  Vec home{};
  bool stopped=false;
  std::vector<Mob> mobs;
  std::map<uint64,ManagedWeakReference<CreatureObject*>> participants;
  Json results=Json::array();
  int damage=0,healing=0,contacts=0,misses=0,fallbacks=0,cancelled=0;
 };
 static std::mutex& registryMutex(){static std::mutex m;return m;}
 static std::map<uint64,std::shared_ptr<Encounter>>& entries(){static std::map<uint64,std::shared_ptr<Encounter>> v;return v;}
 static std::shared_ptr<Encounter> find(uint64 id){std::lock_guard<std::mutex> l(registryMutex());auto i=entries().find(id);return i==entries().end()?nullptr:i->second;}
 static std::shared_ptr<Encounter> findEncounter(const std::string& id){std::lock_guard<std::mutex> l(registryMutex());for(auto& row:entries())if(std::to_string(row.second->id)==id)return row.second;return nullptr;}
 static double now(){return std::chrono::duration<double>(std::chrono::steady_clock::now().time_since_epoch()).count();}
 static Vec point(CreatureObject* c){auto p=c->getWorldPosition();return {{p.getX(),p.getZ(),p.getY()}};}
 static std::string id(SceneObject* c){return std::to_string(c->getObjectID());}
 static const char* roleName(Role r){return r==Role::Melee?"melee":r==Role::Ranged?"ranged":"support";}
 static bool alive(CreatureObject* c){return c && c->getZone() && !c->isDead() && !c->isIncapacitated();}
 static bool eligible(CreatureObject* c,const Encounter& e){return alive(c)&&c->isPlayerCreature()&&c->isOnline()&&!c->getPlayerObject()->isOnLoadScreen()&&c->getParentID()==0&&c->getZone()->getZoneName()=="tatooine"&&corecu::action::distance(point(c),e.home)<=45;}
 static void syncAim(corecu::action::Attack& contact,const corecu::action::Attack& attack){contact.aim=attack.aim;contact.aimRevision=attack.aimRevision;contact.aimLocked=attack.aimLocked;}
 static bool interrupted(CreatureObject* c){return !alive(c)||c->isKnockedDown()||c->isStunned();}
 static void event(CreatureObject* owner,Encounter& e,Mob& m,const char* phase){
  auto& a=m.attack;auto s=corecu::action::spec(m.role);m.phase=phase;
  m.aimPublishedAt=now();m.publishedRevision=a.aimRevision;
  Json row={{"id",id(m.actor)},{"target_id",m.healTarget?id(m.healTarget):id(owner)},{"encounter_id",std::to_string(e.id)},{"attack_id",std::to_string(a.id)},
   {"phase",phase},{"role",roleName(m.role)},{"cell_id","0"},{"origin",a.origin},{"direction",a.aim},
   {"server_now",now()},{"start",a.start},{"delivery_at",a.deliveryAt()},{"animation",corecu::action::animation(m.role)},{"animation_end_at",a.animationEndAt()},{"active_at",a.activeAt()},{"end_at",a.endAt()},{"recover_at",a.recoveredAt()},
   {"range",s.range},{"radius",s.radius},{"cosine",s.cosine}};
  row["eligible_victim_ids"]=Json::array();for(auto& v:m.victims)row["eligible_victim_ids"].push_back(std::to_string(v.first));
  row["hit_policy"]=m.role==Role::Melee?"cleave":m.role==Role::Ranged?"piercing_lane":"support";
  row["aim_revision"]=a.aimRevision;row["aim_locked"]=a.aimLocked;row["lock_at"]=a.lockAt();
  auto message=new AttributeListMessage(m.actor->getObjectID());message->insertAttribute("swgxr.action.event",String(row.dump().c_str()));m.actor->broadcastMessage(message,true);
 }
 static void cancel(CreatureObject* owner,Encounter& e,Mob& m){
  if(m.attack.id && !m.attack.settled && !m.attack.cancelled){m.attack.cancelled=true;++e.cancelled;event(owner,e,m,"cancelled");}
  m.healTarget=nullptr;m.next=now()+1;
 }
 static void finish(CreatureObject* owner,const std::shared_ptr<Encounter>& e){
  if(e->stopped)return;e->stopped=true;
  for(auto& m:e->mobs){Locker l(m.actor,owner);cancel(owner,*e,m);m.actor->setCurrentSpeed(0);m.actor->cancelBehaviorEvent();m.actor->destroyObjectFromWorld(true);}
  std::lock_guard<std::mutex> l(registryMutex());auto i=entries().find(owner->getObjectID());if(i!=entries().end() && i->second==e)entries().erase(i);
 }
 static void schedule(CreatureObject* owner,const std::shared_ptr<Encounter>& e){
  ManagedWeakReference<CreatureObject*> weak=owner;
  Core::getTaskManager()->scheduleTask([weak,e]() mutable {auto c=weak.get();if(!c)return;Locker l(c);Locker guard(&e->mutex,c);if(e->stopped)return;try{tick(c,e);}catch(const std::exception&){finish(c,e);}},"SwgxrActionPrototype",50);
 }
 static void reposition(CreatureObject* owner,Mob& m,double dt){
  auto a=point(m.actor),b=point(owner);double d=corecu::action::distance(a,b);auto s=corecu::action::spec(m.role);
  double error=d-s.preferred;if(std::abs(error)<.65){m.actor->setCurrentSpeed(0);return;}
  auto dir=corecu::action::direction(a,b);double step=std::min(std::abs(error),2.5*dt)*(error<0?-1:1);
  double x=a[0]+dir[0]*step,z=a[2]+dir[2]*step;
  auto zone=owner->getZone();double y=CollisionManager::getWorldFloorCollision(x,z,zone,false);
  if(!std::isfinite(y)||std::abs(y-a[1])>.3||!CollisionManager::checkLineOfSight(m.actor,owner)){m.actor->setCurrentSpeed(0);return;}
  m.actor->setDirection(std::atan2(dir[0],dir[2]));m.actor->setCurrentSpeed(2.5);
  PatrolPoint goal(x,y,z);m.actor->updateCurrentPosition(&goal);
 }
 static void begin(CreatureObject* owner,Encounter& e,Mob& m,double stamp){
  m.actor->setCurrentSpeed(0);m.attack={};auto& a=m.attack;a.id=++e.serial;a.role=m.role;a.start=stamp;a.origin=point(m.actor);a.aim=corecu::action::direction(a.origin,m.healTarget?point(m.healTarget):point(owner));
  m.victims.clear();if(m.role!=Role::Support)for(auto& participant:e.participants){auto c=participant.second.get();if(!c)continue;Locker l(c,owner);if(eligible(c,e)){Victim v;v.actor=c;v.contact=a;m.victims.emplace(participant.first,v);}}
  m.actor->setDirection(std::atan2(a.aim[0],a.aim[2]));m.next=a.recoveredAt();event(owner,e,m,"windup");
 }
 static void settle(CreatureObject* owner,Encounter& e,Mob& m){
  auto& a=m.attack;
  if(m.role==Role::Support){
   a.settled=true;
   if(m.healTarget){Locker l(m.healTarget,m.actor);if(alive(m.healTarget)&&m.healTarget->getZone()==owner->getZone()&&m.healTarget->isInRange(m.actor,18)&&CollisionManager::checkLineOfSight(m.actor,m.healTarget)){
    int before=m.healTarget->getHAM(0);m.healTarget->healDamage(m.actor,0,std::max(1,m.healTarget->getMaxHAM(0)/10),true,true);e.healing+=m.healTarget->getHAM(0)-before;
   }}
  }else{
   for(auto& item:m.victims){auto& contact=item.second.contact;if(contact.settled)continue;
    auto victim=item.second.actor.get();
    if(!victim){contact.cancelled=true;contact.settled=true;continue;}
    Locker lock(victim,owner);syncAim(contact,a);
    if(!e.participants.count(item.first)||!eligible(victim,e))contact.cancelled=true;
    if(!contact.cancelled&&!contact.due(now()))continue;
    int damage=0;bool hit=contact.resolve();
    if(contact.cancelled)++e.cancelled;
    else{
     if(!contact.reported)++e.fallbacks;
     if(hit){
      auto cmd=dynamic_cast<const CombatQueueCommand*>(owner->getZoneServer()->getObjectController()->getQueueCommand("attack"));
      if(cmd&&m.actor->getWeapon()&&victim->isAttackableBy(m.actor)){
       corecu::action::ContactScope confirmed(m.actor->getObjectID(),victim->getObjectID());int before=victim->getHAM(0);
       CombatManager::instance()->doCombatAction(m.actor,m.actor->getWeapon(),victim,CreatureAttackData(UnicodeString(""),cmd,victim->getObjectID()));
       damage=std::max(0,before-victim->getHAM(0));e.damage+=damage;++e.contacts;
      }
     }else ++e.misses;
    }
    e.results.push_back({{"actor_id",id(m.actor)},{"attack_id",std::to_string(a.id)},{"target_id",id(owner)},{"victim_id",std::to_string(item.first)},{"role",roleName(m.role)},{"aim_revision",a.aimRevision},{"contact",hit},{"reported",contact.reported},{"cancelled",contact.cancelled},{"damage",damage}});
    if(e.results.size()>128)e.results.erase(e.results.begin());
   }
   for(auto& v:m.victims)if(!v.second.contact.settled)return;
   a.settled=true;
  }
  event(owner,e,m,"recovery");
 }
 static void tick(CreatureObject* owner,const std::shared_ptr<Encounter>& e){
  const double stamp=now();double dt=std::min(.1,std::max(0.,stamp-e->last));e->last=stamp;
  if(!alive(owner)||!owner->isOnline()||owner->getPlayerObject()->isOnLoadScreen()||owner->getParentID()!=0||owner->getZone()->getZoneName()!="tatooine"||stamp>e->expires||corecu::action::distance(point(owner),e->home)>45){finish(owner,e);return;}
  for(auto& m:e->mobs){
   Locker l(m.actor,owner);
   if(interrupted(m.actor)||m.actor->getZone()!=owner->getZone()){cancel(owner,*e,m);continue;}
   auto& a=m.attack;
   if(a.id && !a.settled && !a.cancelled){
    const bool wasLocked=a.aimLocked;
    a.prepare(stamp,m.healTarget?point(m.healTarget):point(owner));
    m.actor->setDirection(std::atan2(a.aim[0],a.aim[2]));
    // Publish at most 10 Hz while steering; always publish the final lock.
    if((!wasLocked&&a.aimLocked)||(a.aimRevision!=m.publishedRevision&&stamp-m.aimPublishedAt>=.1))event(owner,*e,m,"windup");
    if(stamp>=a.deliveryAt() && m.phase=="windup")event(owner,*e,m,"active");
    if(m.role!=Role::Support)for(auto& item:m.victims){auto c=item.second.actor.get();auto& contact=item.second.contact;if(!c||contact.settled||contact.cancelled)continue;Locker lock(c,owner);syncAim(contact,a);if(!eligible(c,*e)||!e->participants.count(item.first))contact.cancelled=true;else if(CollisionManager::checkLineOfSight(m.actor,c))contact.sample(stamp,point(c));}
    if(stamp>=a.endAt())settle(owner,*e,m);
    continue;
   }
   if(stamp<m.next)continue;
   reposition(owner,m,dt);
   if(!CollisionManager::checkLineOfSight(m.actor,owner))continue;
   if(m.role==Role::Support){
    m.healTarget=nullptr;double lowest=.99;
    for(auto& ally:e->mobs){if(ally.actor==m.actor)continue;Locker other(ally.actor,m.actor);if(alive(ally.actor)&&ally.actor->isInRange(m.actor,18)){
     double ratio=double(ally.actor->getHAM(0))/std::max(1,ally.actor->getMaxHAM(0));if(ratio<lowest){lowest=ratio;m.healTarget=ally.actor;}
    }}
    if(m.healTarget)begin(owner,*e,m,stamp);
   }else if(corecu::action::distance(point(m.actor),point(owner))<=corecu::action::spec(m.role).range)begin(owner,*e,m,stamp);
  }
  schedule(owner,e);
 }
 static Json status(const Encounter& e){Json mobs=Json::array();for(auto& m:e.mobs)mobs.push_back({{"id",id(m.actor)},{"role",roleName(m.role)}});return {{"success",true},{"encounter_id",std::to_string(e.id)},{"mobs",mobs},{"participant_count",e.participants.size()},{"victim_results",e.results},{"damage",e.damage},{"healing",e.healing},{"contacts",e.contacts},{"misses",e.misses},{"fallbacks",e.fallbacks},{"cancelled",e.cancelled}};}
public:
 static void stop(CreatureObject* c){auto e=find(c->getObjectID());if(e){Locker guard(&e->mutex,c);finish(c,e);}}
 static Json run(CreatureObject* c,const Json& q){
  const auto op=q.at("action").get<std::string>();
  if(op=="stop"){stop(c);return {{"success",true}};}
  auto e=q.contains("encounter_id")?findEncounter(q.at("encounter_id").get<std::string>()):find(c->getObjectID());
  if(op=="start"){
   const char* enabled=std::getenv("SWGXR_ACTION_COMBAT_PROTOTYPE");
   if(!enabled||std::string(enabled)!="1"||c->getPlayerObject()->getScreenPlayData("swgxr_livecombat","test_authorized")!="1")throw std::runtime_error("action_prototype_disabled");
   if(e)throw std::runtime_error("action_encounter_exists");
   if(!alive(c)||c->getParentID()!=0||c->getZone()->getZoneName()!="tatooine"||c->getPlayerObject()->isOnLoadScreen())throw std::runtime_error("action_fixture_not_ready");
   static std::atomic<uint64> serial{uint64(System::getMiliTime())};e=std::make_shared<Encounter>();e->id=++serial;e->expires=now()+180;e->last=now();e->home=point(c);e->participants[c->getObjectID()]=c;
   try{
    for(int i=0;i<3;++i){double x=e->home[0]+(i-1)*5,z=e->home[2]+8+i*2,y=CollisionManager::getWorldFloorCollision(x,z,c->getZone(),false);
     auto creature=c->getZone()->getCreatureManager()->spawnCreature(String(i==0?"worrt":"thug").hashCode(),0,x,y,z,0);
     if(!creature||!creature->isAiAgent())throw std::runtime_error("action_fixture_spawn_failed");
     Mob m;m.actor=creature->asAiAgent();m.role=i==0?Role::Melee:i==1?Role::Ranged:Role::Support;m.next=now()+1+i*.5;e->mobs.push_back(m);
     Locker l(m.actor,c);m.actor->setRespawnTimer(0);m.actor->setOptionsBitmask(m.actor->getOptionsBitmask() & ~OptionBitmask::AIENABLED);m.actor->cancelBehaviorEvent();
     if(m.role==Role::Ranged){auto weapon=m.actor->createWeapon(String("object/weapon/ranged/pistol/pistol_dl44.iff").hashCode(),true);if(!weapon)throw std::runtime_error("action_fixture_weapon_failed");m.actor->setPrimaryWeapon(weapon);m.actor->equipPrimaryWeapon();}
     if(!CollisionManager::checkLineOfSight(c,m.actor))throw std::runtime_error("action_fixture_obstructed");
    }
    {std::lock_guard<std::mutex> l(registryMutex());entries()[c->getObjectID()]=e;}schedule(c,e);
   }catch(...){finish(c,e);throw;}
  }
  if(!e)throw std::runtime_error("action_encounter_missing");Locker guard(&e->mutex,c);
  if(e->stopped)throw std::runtime_error("action_encounter_missing");
  if(op=="join"){
   const char* enabled=std::getenv("SWGXR_ACTION_COMBAT_PROTOTYPE");
   if(!enabled||std::string(enabled)!="1"||c->getPlayerObject()->getScreenPlayData("swgxr_livecombat","test_authorized")!="1")throw std::runtime_error("action_prototype_disabled");
   if(!eligible(c,*e))throw std::runtime_error("action_fixture_not_ready");
   if(!e->participants.count(c->getObjectID())&&e->participants.size()>=8)throw std::runtime_error("action_participants_full");
   e->participants[c->getObjectID()]=c;return status(*e);
  }
  if(!e->participants.count(c->getObjectID()))throw std::runtime_error("action_not_participant");
  if(op=="leave"){
   if(find(c->getObjectID())==e)throw std::runtime_error("action_owner_must_stop");
   e->participants.erase(c->getObjectID());for(auto& m:e->mobs){auto v=m.victims.find(c->getObjectID());if(v!=m.victims.end())v->second.contact.cancelled=true;}return {{"success",true}};
  }
  if(op=="contact"){
   if(!eligible(c,*e)||q.contains("victim_id"))throw std::runtime_error("action_contact_identity");
   if(q.at("encounter_id").get<std::string>()!=std::to_string(e->id)||!q.at("contact").is_boolean())throw std::runtime_error("action_contact_identity");
   for(auto& m:e->mobs)if(id(m.actor)==q.at("actor_id").get<std::string>() && std::to_string(m.attack.id)==q.at("attack_id").get<std::string>() && m.role!=Role::Support){
    auto v=m.victims.find(c->getObjectID());if(v==m.victims.end())throw std::runtime_error("action_not_eligible_victim");syncAim(v->second.contact,m.attack);
    if(!v->second.contact.receipt(now(),q.at("contact").get<bool>(),q.at("coverage_start").get<double>(),q.at("coverage_end").get<double>(),q.at("aim_revision").get<uint64_t>()))throw std::runtime_error("action_contact_expired_duplicate_or_aim_revision");
    return {{"success",true},{"accepted",true},{"attack_id",q.at("attack_id")}};
   }
   throw std::runtime_error("action_contact_unknown");
  }
  if(op!="status"&&op!="start")throw std::runtime_error("action_operation_invalid");return status(*e);
 }
};
