#pragma once
#include "server/zone/objects/player/PlayerObject.h"
#include "server/zone/objects/ship/ai/ShipAiAgent.h"

// Granted only by an original mission's docking stage, scoped to pilot + NPC.
// Journal state is rechecked on entry, during docking, and before quest credit.
class SwgxrDocking {
public:
 static bool missionPermission(ShipObject* ship, ShipObject* target) {
  if(!ship || !target || ship==target || !ship->getZone() || ship->getZone()!=target->getZone() ||
     !ship->isShipLaunched() || ship->isShipDestroyed() || ship->isShipDisabled() || ship->isHyperspacing() ||
     !target->isShipLaunched() || !target->isShipAiAgent() || target->isShipDestroyed() || target->isHyperspacing())return false;
  auto pilot=ship->getPilot();
  if(!pilot || !pilot->isPlayerCreature())return false;
  auto ghost=pilot->getPlayerObject();if(!ghost)return false;
  auto owner=target->asShipAiAgent()->getMissionOwnerID();
  if(owner && owner!=pilot->getObjectID())return false;
  auto quest=ghost->getScreenPlayData("swgxr_docking",String::valueOf(target->getObjectID()));
  if(!quest.beginsWith("spacequest/inspect/") && !quest.beginsWith("spacequest/rescue/") && !quest.beginsWith("spacequest/rescue_duty/"))return false;
  auto crc=quest.hashCode();
  return ghost->isJournalQuestActive(crc) && ghost->isJournalQuestTaskActive(crc,2) && !ghost->isJournalQuestTaskComplete(crc,2);
 }
 static bool permission(ShipObject* ship,ShipObject* target) {
  if(missionPermission(ship,target))return true;
  auto pilot=ship?ship->getPilot():nullptr;auto ghost=pilot?pilot->getPlayerObject():nullptr;
  return ghost && ghost->hasGodMode() && target && ship!=target && ship->getZone()==target->getZone();
 }
};
