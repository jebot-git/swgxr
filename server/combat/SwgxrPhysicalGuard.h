#pragma once
#include "PhysicalGuardPolicy.h"
#include "server/zone/objects/creature/CreatureObject.h"
#include "server/zone/objects/tangible/weapon/WeaponObject.h"
#include "server/zone/objects/player/PlayerObject.h"
#include <chrono>
#include <map>
#include <mutex>

// The native creature lock is held by callers; this mutex protects only the cache.
class SwgxrPhysicalGuard {
 using Json=JSONSerializationType;
 struct Entry : corecu::guard::State {corecu::guard::Vec forward{},head{};};
 static std::map<uint64,Entry>& entries(){static std::map<uint64,Entry> value;return value;}
 static std::mutex& mutex(){static std::mutex value;return value;}
 static double now(){return std::chrono::duration<double>(std::chrono::steady_clock::now().time_since_epoch()).count();}
 static corecu::guard::Vec vec(const Json& p,double limit){
  if(!p.is_array()||p.size()!=3)throw std::runtime_error("invalid_guard_pose");
  corecu::guard::Vec out{};for(int i=0;i<3;++i){if(!p[i].is_number())throw std::runtime_error("invalid_guard_pose");out[i]=p[i].get<double>();if(!std::isfinite(out[i])||std::abs(out[i])>limit)throw std::runtime_error("invalid_guard_pose");}return out;
 }
 static bool eligible(CreatureObject* c){return c&&c->isPlayerCreature()&&!c->isDead()&&!c->isIncapacitated()&&!c->isFeigningDeath()&&(c->getPosture()==0||c->getPosture()==1)&&c->getPlayerObject()&&!c->getPlayerObject()->isOnLoadScreen();}
public:
 static void clear(uint64 id){std::lock_guard<std::mutex> lock(mutex());entries().erase(id);}
 static double release(uint64 id){std::lock_guard<std::mutex> lock(mutex());auto it=entries().find(id);if(it==entries().end())return 0;return it->second.release();}
 static void observe(CreatureObject* c,const Json& p){
  const double previous=release(c->getObjectID());
  if(!p.is_object()||p.value("mode",std::string("none"))=="none"||!eligible(c))return;
  const auto mode=p.at("mode").get<std::string>();
  if(p.value("main",std::string())!="left"&&p.value("main",std::string())!="right")return;
  auto weapon=c->getWeapon();
  if(!weapon||!weapon->isMeleeWeapon()||!weapon->isCertifiedFor(c))return;
  bool unarmed=mode=="boxing";
  if((mode!="boxing"&&mode!="parry")||unarmed!=weapon->isUnarmedWeapon()||p.value("item_id",std::string())!=std::to_string(weapon->getObjectID()))return;
  auto left=vec(p.at("left"),2),right=vec(p.at("right"),2),axis=vec(p.at("axis"),2),forward=vec(p.at("forward"),2),head=vec(p.at("head"),20000);
  if(unarmed?!corecu::guard::boxing(left,right):!corecu::guard::parry(p.at("main").get<std::string>()=="left"?left:right,axis))return;
  if(std::abs(corecu::guard::length(forward)-1)>.05||std::abs(forward[1])>.05)return;
  auto position=c->getWorldPosition();
  if(std::hypot(head[0]-position.getX(),head[2]-position.getY())>1.5||head[1]-position.getZ()<.3||head[1]-position.getZ()>3)return;
  std::lock_guard<std::mutex> lock(mutex());double stamp=now();auto& all=entries();
  for(auto it=all.begin();it!=all.end();)if(it->first!=c->getObjectID()&&stamp-it->second.at>120&&stamp-it->second.broken>120)it=all.erase(it);else ++it;
  if(!all.count(c->getObjectID())&&all.size()>=128)return;
  auto& e=all[c->getObjectID()];e.refresh(stamp,previous,weapon->getObjectID(),unarmed);e.forward=forward;e.head=head;
 }
 static double resolve(CreatureObject* defender,CreatureObject* attacker,WeaponObject* incoming,int damage){
  if(!eligible(defender)||!attacker||!incoming||!incoming->isMeleeWeapon()||damage<=0)return 1;
  auto weapon=defender->getWeapon();if(!weapon||!weapon->isMeleeWeapon()||!weapon->isCertifiedFor(defender))return 1;
  double stamp=now();std::lock_guard<std::mutex> lock(mutex());auto it=entries().find(defender->getObjectID());if(it==entries().end())return 1;auto& e=it->second;
  if(!e.active(stamp,weapon->getObjectID()))return 1;
  auto a=attacker->getWorldPosition(),d=defender->getWorldPosition();
  if(std::hypot(e.head[0]-d.getX(),e.head[2]-d.getY())>1.5||!corecu::guard::front(e.forward[0],e.forward[2],a.getX()-d.getX(),a.getY()-d.getY()))return 1;
  int cost=e.block(stamp,damage,defender->getHAM(3));if(cost==0)return 1;
  defender->inflictDamage(defender,3,cost,false,"guardCost",false,false);
  return corecu::guard::multiplier(e.unarmed);
 }
 static Json snapshot(CreatureObject* c){std::lock_guard<std::mutex> lock(mutex());auto it=entries().find(c->getObjectID());if(it==entries().end())return {{"active",false},{"blocks",0}};const auto& e=it->second;double stamp=now();return {{"active",e.active(stamp,c->getWeapon()?c->getWeapon()->getObjectID():0)&&eligible(c)},{"mode",e.unarmed?"boxing":"parry"},{"blocks",e.blocks},{"broken_seconds",std::max(0.,e.broken-stamp)}};}
};
