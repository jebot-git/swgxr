#ifndef SWGXR_CRAFTING_STATE_H
#define SWGXR_CRAFTING_STATE_H
#include "server/zone/objects/creature/CreatureObject.h"
#include "server/zone/objects/player/PlayerObject.h"
#include <ctime>
// Native persistent transaction journal. Original objects stay in private escrow
// until start; reservations keep their original slots available for cancellation.
class SwgxrCraftingState {
public:
 using Json=JSONSerializationType;
 static std::string id(SceneObject* o){return o?std::to_string(o->getObjectID()):"";}
 static Json load(CreatureObject* c){auto raw=c->getPlayerObject()->getScreenPlayData("swgxr_crafting","state");return raw.isEmpty()?Json{{"draft",nullptr},{"jobs",Json::array()},{"receipts",Json::array()}}:Json::parse(raw.toCharArray());}
 static void save(CreatureObject* c,const Json& s){c->getPlayerObject()->setScreenPlayData("swgxr_crafting","state",String(s.dump().c_str()));}
 static int reserved(SceneObject* container){
  auto parent=container->getParent().get();int depth=0;
  while(parent!=nullptr && !parent->isPlayerCreature() && depth++<12)parent=parent->getParent().get();
  if(parent==nullptr || !parent->isPlayerCreature())return 0;
  auto c=cast<CreatureObject*>(parent.get());if(c->getPlayerObject()==nullptr)return 0;
  auto s=load(c);int count=0;auto key=id(container);
  if(s["draft"].is_object())for(auto& entry:s["draft"].value("escrow",Json::array()))if(entry.value("parent",std::string())==key)count+=entry.value("cost",1);
  for(auto& job:s["jobs"])if(job.value("parent",std::string())==key)count+=job.value("cost",1);
  return count;
 }
 static bool complete(CreatureObject* c,SceneObject* tool){auto s=load(c);bool found=false;Json jobs=Json::array();for(auto& job:s["jobs"]){if(job["tool_id"]==id(tool))found=true;else jobs.push_back(job);}if(found){s["jobs"]=jobs;save(c,s);}return found;}
};
#endif
