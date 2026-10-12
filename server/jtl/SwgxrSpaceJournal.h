#pragma once
#include "server/zone/managers/player/QuestTasks.h"
#include "server/zone/objects/waypoint/WaypointObject.h"
// Read the existing owner-only Core3 journal and server-created quest waypoints.
class SwgxrSpaceJournal {
 using Json=JSONSerializationType;
public:
 static void snapshot(CreatureObject* c,Json& out){
  out["missions"]=Json::array();out["waypoints"]=Json::array();auto ghost=c->getPlayerObject();if(!ghost)return;
  auto quests=ghost->getPlayerQuestsData();auto manager=c->getZoneServer()->getPlayerManager();
  for(int i=0;i<quests->size();++i){
   auto crc=quests->getKeyAt(i);auto value=quests->getValueAt(i);if(value.getCompletedFlag())continue;
   auto tasks=manager->getQuestTasks(crc);if(!tasks)continue;
   for(int n=0;n<tasks->getNumberOfTasks() && n<16;++n){
    if(!(value.getActiveStepBitmask()&(1<<n)))continue;auto task=tasks->getTask(n);auto title=task->getJournalEntryTitle();
    if(!task->getIsVisible() || !title.beginsWith("@spacequest/"))continue;
    out["missions"].push_back({{"id","spacequest:"+std::to_string(crc)+":"+std::to_string(n)},{"type","space_mission"},{"category","data"},{"name",title.toCharArray()},{"description",task->getJournalEntryDescription().toCharArray()},{"deletable",false},{"source","core3_quest_journal"},{"attributes",{{"Progress",value.getQuestCounter()},{"Quest CRC",crc},{"Task",n}}}});
   }
  }
  auto zone=c->getZone();if(!zone)return;
  for(int i=0;i<ghost->getWaypointListSize();++i){auto w=ghost->getWaypoint(i);if(!w || !w->isActive() || w->getPlanetCRC()!=zone->getZoneName().hashCode())continue;
   out["waypoints"].push_back({{"id",std::to_string(w->getObjectID())},{"kind","waypoint"},{"color",int(w->getColor())},{"name",w->getDisplayedName().toCharArray()},{"position",Json::array({w->getPositionX(),w->getPositionZ(),w->getPositionY()})}});
  }
 }
};
