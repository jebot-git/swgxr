#ifndef SWGXR_UNDERWORLD_ENCOUNTERS_H
#define SWGXR_UNDERWORLD_ENCOUNTERS_H
#include "SwgxrUnderworldState.h"
#include "server/zone/managers/creature/CreatureManager.h"
#include "server/zone/managers/combat/CombatManager.h"
#include "server/zone/managers/collision/CollisionManager.h"
#include "server/zone/objects/creature/ai/AiAgent.h"
// Bounded ground interceptions. Native AI, damage, loot and police scanners keep
// their normal rules. No NPCs spawn in cities, interiors or for offline players.
class SwgxrUnderworldEncounters {
 using Json=JSONSerializationType;
 class EncounterTask:public Task {
  ManagedWeakReference<CreatureObject*> owner;
 public:
  EncounterTask(CreatureObject* c):owner(c){}
  void run(){auto c=owner.get();if(!c)return;Locker lock(c);c->removePendingTask("swgxr_underworld_encounter");tick(c);ensure(c);}
 };
 static void tick(CreatureObject* c){
  auto s=SwgxrUnderworldState::load(c);if(!SwgxrUnderworldState::active(c))return;
  if(s.value("deadline_ms",uint64(0))<=System::getMiliTime()){SwgxrUnderworldState::fail(c,"expired");return;}
  if(!c->isOnline() || c->getPlayerObject()->isOnLoadScreen() || !c->getZone() || c->getParentID()!=0 || c->getCityRegion().get()!=nullptr || c->isInCombat() || c->isDead() || c->isIncapacitated())return;
  auto mission=SwgxrUnderworldState::mission(c);if(mission==nullptr)return;auto task=cast<DeliverMissionObjective*>(mission->getMissionObjective());if(task==nullptr || task->getObjectiveStatus()!=DeliverMissionObjective::PICKEDUPSTATUS)return;
  int count=s.value("encounter_count",0);if(count>=2 || s.value("next_encounter_ms",uint64(0))>System::getMiliTime())return;
  float dx=c->getPositionX()-s.value("encounter_x",c->getPositionX()),dy=c->getPositionY()-s.value("encounter_y",c->getPositionY());if(dx*dx+dy*dy<300*300)return;
  // At most one roll each minute after 300m of travel; 50% chance per roll.
  s["next_encounter_ms"]=System::getMiliTime()+60000;SwgxrUnderworldState::save(c,s);if(System::random(1)==0)return;
  static const char* templates[]={"thug","rogue","pirate","mercenary","pirate_leader"};
  int rank=s.value("reputation",0),tier=rank<1000?0:rank<1500?1:rank<2000?2:rank<2500?3:4;
  float angle=System::random(628)/100.f,x=c->getPositionX()+24*std::cos(angle),y=c->getPositionY()+24*std::sin(angle);
  float z=CollisionManager::getWorldFloorCollision(x,y,c->getZone(),false);
  auto creature=c->getZone()->getCreatureManager()->spawnCreature(String(templates[tier]).hashCode(),0,x,z,y,0);if(creature==nullptr || !creature->isAiAgent())return;
  auto enemy=creature->asAiAgent();Locker enemyLock(enemy,c);enemy->setRespawnTimer(0);
  // Reject obstructed placements, including authored building collision.
  if(!CollisionManager::checkLineOfSight(c,enemy)){enemy->destroyObjectFromWorld(true);return;}
  s["encounter_count"]=count+1;s["encounter_x"]=c->getPositionX();s["encounter_y"]=c->getPositionY();s["next_encounter_ms"]=System::getMiliTime()+120000;
  if(s.value("encounter_incarnation",uint64(0))!=SwgxrUnderworldState::incarnation())s["encounter_ids"]=Json::array();s["encounter_incarnation"]=SwgxrUnderworldState::incarnation();if(!s.contains("encounter_ids"))s["encounter_ids"]=Json::array();s["encounter_ids"].push_back(std::to_string(enemy->getObjectID()));SwgxrUnderworldState::save(c,s);
  c->sendSystemMessage("An underworld rival has intercepted your delivery.");CombatManager::instance()->startCombat(enemy,c);
 }
public:
 static Json status(CreatureObject* c){auto mission=SwgxrUnderworldState::mission(c);auto task=mission!=nullptr?cast<DeliverMissionObjective*>(mission->getMissionObjective()):nullptr;auto pending=c->getPendingTask("swgxr_underworld_encounter");return {{"pending_scheduled",pending!=nullptr && pending->isScheduled()},{"pending",pending!=nullptr},{"online",c->isOnline()},{"loading",c->getPlayerObject()->isOnLoadScreen()},{"city",c->getCityRegion().get()!=nullptr},{"combat",c->isInCombat()},{"posture",int(c->getPosture())},{"objective_status",task!=nullptr?task->getObjectiveStatus():-1}};}
 static void ensure(CreatureObject* c){if(SwgxrUnderworldState::active(c) && c->isOnline() && c->getPendingTask("swgxr_underworld_encounter")==nullptr)c->addPendingTask("swgxr_underworld_encounter",new EncounterTask(c),20000);}
};
#endif
