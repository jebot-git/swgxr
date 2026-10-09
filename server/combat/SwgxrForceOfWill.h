#pragma once
#include "ForceOfWillPolicy.h"
#include "SwgxrSpice.h"
#include "server/zone/objects/player/events/SwgxrLiveRecovery.h"
#include <chrono>
class SwgxrForceOfWill {
 using Json=JSONSerializationType;
 static uint64 now(){return std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::system_clock::now().time_since_epoch()).count();}
public:
 static bool learned(CreatureObject* c){return c->isPlayerCreature() && c->getPlayerObject() && c->hasSkill("combat_unarmed_novice") && c->hasSkill("combat_unarmed_accuracy_04");}
 static double cooldown(CreatureObject* c){
  uint64 deadline=0;auto p=c->getPlayerObject();if(p){auto text=p->getScreenPlayData("swgxr_tka","force_of_will_deadline");if(!text.isEmpty())try{deadline=std::stoull(text.toCharArray());}catch(...) {return corecu::forceofwill::CooldownSeconds;}}
  auto old=c->getCooldownTime("tkaForceOfWill");
  return std::max(corecu::forceofwill::remaining(deadline,now()),old?std::max(0.,-old->miliDifference()/1000.):0.);
 }
 static bool conditions(CreatureObject* c){
  auto p=c->getPlayerObject();auto w=c->getWeapon();
  return corecu::forceofwill::eligible(learned(c),w && w->isUnarmedWeapon() && w->isCertifiedFor(c),c->isIncapacitated(),c->isDead(),c->isFeigningDeath() || c->hasBuff(STRING_HASHCODE("private_feign_buff")),!p || p->isCloning() || p->isOnLoadScreen(),SwgxrSpice::pinnedHam(c),c->getPendingTask("incapacitationRecovery")!=nullptr);
 }
 static Json snapshot(CreatureObject* c){return {{"learned",learned(c)},{"conditions_met",conditions(c)},{"cooldown_remaining_seconds",cooldown(c)},{"cooldown_seconds",corecu::forceofwill::CooldownSeconds},{"health_fraction",corecu::forceofwill::HealthFraction}};}
 // Caller owns the creature lock. Both the native command and life route use this path.
 static void recover(CreatureObject* c){
  if(!conditions(c))throw std::runtime_error("native_force_of_will_unavailable");
  if(cooldown(c)>0)throw std::runtime_error("native_force_of_will_cooldown");
  auto task=c->getPendingTask("incapacitationRecovery");auto p=c->getPlayerObject();
  p->setScreenPlayData("swgxr_tka","force_of_will_deadline",String(std::to_string(now()+corecu::forceofwill::CooldownSeconds*1000).c_str()));
  c->addCooldown("tkaForceOfWill",corecu::forceofwill::CooldownSeconds*1000);
  p->updateToDatabase();
  task->cancel();c->removePendingTask("incapacitationRecovery");
  c->setHAM(0,corecu::forceofwill::recoveredHealth(c->getHAM(0),c->getMaxHAM(0),c->getWounds(0)));
  SwgxrLiveRecovery::touch(c->getObjectID(),false);
  c->setPosture(CreaturePosture::UPRIGHT,true,true);
  c->notifyObservers(ObserverEventType::CREATUREREVIVED,nullptr,0);
  if(p->getForcePowerMax()>0 && p->getForcePower()<p->getForcePowerMax())p->activateForcePowerRegen();
  c->updateToDatabase();
 }
};
