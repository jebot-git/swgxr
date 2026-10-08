#ifndef SWGXR_UNDERWORLD_STATE_H
#define SWGXR_UNDERWORLD_STATE_H
#include "server/zone/objects/creature/CreatureObject.h"
#include "server/zone/objects/player/PlayerObject.h"
#include "server/zone/objects/mission/DeliverMissionObjective.h"
#include "server/zone/managers/mission/MissionManager.h"
// Persistent per-character native mission metadata. Original Core3 mission
// objects remain the authority for parcel ownership, objectives and credits.
class SwgxrUnderworldState {
 using Json=JSONSerializationType;
public:
 static constexpr int DURATION_MS=30*60*1000;
 static uint64 incarnation(){static const uint64 value=System::getMiliTime();return value;}
 static Json load(CreatureObject* c){if(!c || !c->getPlayerObject())return Json::object();auto s=c->getPlayerObject()->getScreenPlayData("swgxr_underworld","state");return s.isEmpty()?Json::object():Json::parse(s.toCharArray());}
 static void save(CreatureObject* c,const Json& state){auto ghost=c->getPlayerObject();ghost->setScreenPlayData("swgxr_underworld","state",String(state.dump().c_str()));ghost->updateToDatabase();}
 static std::string id(SceneObject* o){return o?std::to_string(o->getObjectID()):"";}
 static bool active(CreatureObject* c){return !load(c).value("mission_id",std::string()).empty();}
 static bool owns(CreatureObject* c,MissionObject* m){return c && m && load(c).value("mission_id",std::string())==id(m);}
 static ManagedReference<MissionObject*> mission(CreatureObject* c){auto key=load(c).value("mission_id",std::string());if(key.empty())return nullptr;return c->getZoneServer()->getObject(std::stoull(key)).castTo<MissionObject*>();}
 static void finish(CreatureObject* c,MissionObject* m,bool success,const std::string& reason){
  if(!owns(c,m))return;auto s=load(c);int reputation=s.value("reputation",0),delta=success?s.value("reward_faction",50):-10;
  // Only this process incarnation's explicitly recorded transient enemies are
  // removed. Saved ephemeral IDs must never resolve to unrelated post-restart NPCs.
  if(s.value("encounter_incarnation",uint64(0))==incarnation())for(const auto& entry:s.value("encounter_ids",Json::array())){auto enemy=c->getZoneServer()->getObject(std::stoull(entry.get<std::string>()));if(enemy!=nullptr){Locker guard(enemy,c);enemy->destroyObjectFromWorld(true);}}s["encounter_ids"]=Json::array();
  s["reputation"]=std::max(-3000,std::min(5000,reputation+delta));s["last_mission_id"]=id(m);s["mission_id"]="";s["last_result"]=reason;s["last_faction_delta"]=s["reputation"].get<int>()-reputation;s["deadline_ms"]=0;save(c,s);
  c->sendSystemMessage(success?"Underworld delivery complete. Your reputation has increased.":"Underworld mission failed. Front money is forfeited and Underworld reputation reduced by 10.");
 }
 static void fail(CreatureObject* c,const std::string& reason){
  auto m=mission(c);if(m==nullptr)return;finish(c,m,false,reason);m->setRewardCredits(0);
  if(m->getParent().get()==c->getSlottedObject("datapad"))c->getZoneServer()->getMissionManager()->handleMissionAbort(m,c);
 }
 static bool contraband(SceneObject* item){
  if(!item)return false;auto c=item->getParentRecursively(SceneObjectType::PLAYERCREATURE).castTo<CreatureObject*>();if(c==nullptr)return false;
  auto m=mission(c);if(m==nullptr)return false;auto task=cast<DeliverMissionObjective*>(m->getMissionObjective());return task!=nullptr && task->getItem()==item;
 }
};
#endif
