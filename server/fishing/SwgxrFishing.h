#ifndef SWGXR_FISHING_H
#define SWGXR_FISHING_H
#include "SwgxrInventory.h"
#include "server/zone/ZoneProcessServer.h"
#include "server/zone/managers/minigames/FishingManager.h"
#include "server/zone/managers/minigames/FishingSession.h"
#include "server/zone/objects/tangible/fishing/FishingPoleObject.h"
#include "server/zone/objects/tangible/fishing/FishingBaitObject.h"
#include "server/zone/managers/collision/CollisionManager.h"

// The original manager owns timing, RNG, bait deterioration and all rewards.
class SwgxrFishing {
 using Json=JSONSerializationType;
 static std::string id(SceneObject* o){return o?std::to_string(o->getObjectID()):"";}
 static uint64 oid(const Json& r,const char* key){auto s=r.at(key).get<std::string>();if(s.empty() || s.size()>20 || s.find_first_not_of("0123456789")!=std::string::npos)throw std::runtime_error("Invalid fishing object ID");return std::stoull(s);}
 static String data(CreatureObject* c,const char* key){return c->getPlayerObject()->getScreenPlayData("swgxr_fishing",key);}
 static void put(CreatureObject* c,const char* key,const std::string& value){c->getPlayerObject()->setScreenPlayData("swgxr_fishing",key,String(value.c_str()));}
 static FishingManager* manager(CreatureObject* c){auto p=c->getZoneProcessServer();auto m=p?p->getFishingManager():nullptr;if(!m)throw std::runtime_error("Native fishing manager unavailable");return m;}
 static FishingPoleObject* pole(CreatureObject* c,const Json& r){auto o=c->getZoneServer()->getObject(oid(r,"rod_id"));if(!o || !o->isFishingPoleObject() || (!SwgxrEquipment::inInventory(o,c) && o->getParent().get()!=c))throw std::runtime_error("Owned fishing pole required");return static_cast<FishingPoleObject*>(o.get());}
 static Json state(CreatureObject* c,FishingPoleObject* rod){
  auto m=manager(c);auto marker=m->getFishMarker(c);int stage=m->getFishingState(c);
  Json s={{"rod_id",id(rod)},{"active",stage!=FishingManager::NOTFISHING},{"stage",stage},{"next_action",m->getNextAction(c)},{"session_id",std::string(data(c,"session").toCharArray())},{"equipped",m->getPole(c)==rod},{"freshness",0},{"bait_id",""},{"bait_count",0},{"bait_status","No bait"},{"bait_template",""},{"baits",Json::array()},{"reward_available",false}};
  if(rod->getContainerObjectsSize()>0){auto b=rod->getContainerObject(0).castTo<FishingBaitObject*>();if(b){s["bait_id"]=id(b);s["bait_template"]=std::string(b->getObjectTemplate()->getFullTemplateString().toCharArray());s["bait_count"]=std::max(1,b->getUseCount());s["freshness"]=b->getFreshness();s["bait_status"]=b->getFreshness()>=FishingManager::MUSH?"Mush":b->getFreshness()>=FishingManager::SOGGY?"Soggy":"Fresh";}}
  if(marker){auto p=marker->getWorldPosition();s["marker"]={{"id",id(marker)},{"template",std::string(marker->getObjectTemplate()->getFullTemplateString().toCharArray())},{"position",Json::array({p.getX(),p.getZ(),p.getY()})}};s["density"]=m->density(marker);s["vegetation"]=m->vegetation(marker);}
  auto inventory=SwgxrInventory::snapshot(c);for(auto& item:inventory["items"])if(item.value("fishing_bait",false) && item.value("container_id",std::string())!=id(rod))s["baits"].push_back(item);
  auto reward=data(c,"reward");if(!reward.isEmpty()){auto o=c->getZoneServer()->getObject(UnsignedLong::valueOf(reward));s["reward_available"]=o && o->getContainerObjectsSize()>0;}
  s["message"]=std::string(data(c,"message").toCharArray());return s;
 }
public:
 static Json run(CreatureObject* c,const Json& r){
  auto action=r.at("action").get<std::string>();auto rod=pole(c,r);auto m=manager(c);bool mutation=action!="fishing_status";
  Json result={{"success",true},{"operation",action}},proposal=r,receipts=Json::array();
  for(auto field:{"position","building_id","cell_index","zone","request_id"})proposal.erase(field);
  auto saved=data(c,"receipts");if(!saved.isEmpty())receipts=Json::parse(saved.toCharArray());
  std::string key=r.value("request_id",std::string());bool replay=false;
  if(mutation){if(key.size()<8 || key.size()>64)throw std::runtime_error("Stable fishing request ID required");for(auto& receipt:receipts)if(receipt["id"]==key){if(receipt["request"]!=proposal)throw std::runtime_error("Fishing request ID reused");result=receipt["result"];result["replayed"]=true;replay=true;break;}}
  if(mutation && !replay){
   if(action!="fishing_stow" && action!="fishing_stop" && (c->isDead() || c->isIncapacitated() || c->isInCombat() || c->isRidingMount() || c->getActiveSession(SessionFacadeType::TRADE)!=nullptr))throw std::runtime_error("Fishing unavailable in current player state");
   if(action=="fishing_open"){
    if(m->hasFishingSession(c))throw std::runtime_error("Finish current fishing attempt first");put(c,"active","");
    if(m->getPole(c)!=rod){auto equipped=SwgxrEquipment::mutate(c,String(("swgxr_equipment_v1 equip "+id(rod)+" 0").c_str()));if(!equipped.value("success",false))throw std::runtime_error("Core3 could not equip fishing pole");}
    put(c,"message","Load bait, hold trigger, swing back then forward and release to cast.");
   }else if(action=="fishing_stop" || action=="fishing_stow"){
    // A release may only stop/stow this owned rod, never a different equipped rod.
    if(m->getPole(c)==rod){if(m->hasFishingSession(c))m->stopFishing(c,m->getFishBoxID(c),true);if(action=="fishing_stow"){String error;auto inv=c->getInventory();if(!inv || inv->canAddObject(rod,-1,error)!=0 || !c->getZoneServer()->getObjectController()->transferObject(rod,inv,-1,true))throw std::runtime_error("Inventory space required to stow rod");}}
   }else if(action=="fishing_bait"){
    if(m->getPole(c)!=rod || m->hasFishingSession(c))throw std::runtime_error("Hold idle rod to change bait");
    auto bait=c->getZoneServer()->getObject(oid(r,"bait_id"));if(!bait || !bait->isFishingBait() || !SwgxrEquipment::inInventory(bait,c) || bait->isASubChildOf(rod))throw std::runtime_error("Owned inventory bait required");
    Locker lock(bait,c);auto inventory=c->getInventory();auto controller=c->getZoneServer()->getObjectController();ManagedReference<SceneObject*> old=rod->getContainerObjectsSize()?rod->getContainerObject(0):nullptr;
    if(old){String error;if(inventory->canAddObject(old,-1,error)!=0 || !controller->transferObject(old,inventory,-1,true))throw std::runtime_error("Space required for previous bait");}
    String error;if(rod->canAddObject(bait,-1,error)!=0 || !controller->transferObject(bait,rod,-1,true)){if(old)controller->transferObject(old,rod,-1,true);throw std::runtime_error("Native bait loading rejected");}
    put(c,"message","Bait loaded. Swing and release trigger to cast.");
   }else if(action=="fishing_cast"){
    if(m->getPole(c)!=rod || m->hasFishingSession(c))throw std::runtime_error("Hold an idle equipped rod to cast");
    if(state(c,rod).value("reward_available",false))throw std::runtime_error("Collect the previous catch first");
    auto target=r.at("cast_position");if(!target.is_array() || target.size()!=3)throw std::runtime_error("Invalid cast point");for(auto& n:target)if(!n.is_number() || !std::isfinite(n.get<double>()) || std::abs(n.get<double>())>8192)throw std::runtime_error("Invalid cast point");
    put(c,"cast",target.dump());put(c,"active","1");put(c,"session",key);put(c,"message","Watching float");
    try {auto cmd=c->getZoneServer()->getObjectController()->getQueueCommand("fish");if(!cmd || cmd->doQueueCommand(c,0,UnicodeString())!=QueueCommand::SUCCESS || !m->hasFishingSession(c))throw std::runtime_error("Cast rejected: bait, water, reach or player state");if(!CollisionManager::checkLineOfSight(c,m->getFishMarker(c))){m->stopFishing(c,m->getFishBoxID(c),true);throw std::runtime_error("Fishing cast obstructed");}}
    catch(...){put(c,"cast","");put(c,"active","");throw;}put(c,"cast","");
   }else if(action=="fishing_action"){
    if(m->getPole(c)!=rod || !m->hasFishingSession(c) || data(c,"active")!="1" || r.value("session_id",std::string())!=data(c,"session").toCharArray())throw std::runtime_error("Fishing attempt changed");
    int gesture=r.at("gesture").get<int>();if(gesture<1 || gesture>4)throw std::runtime_error("Invalid fishing gesture");if(!c->checkCooldownRecovery("swgxr_fishing_input"))throw std::runtime_error("Fishing gesture recovering");
    m->setNextAction(c,gesture);c->addCooldown("swgxr_fishing_input",350);
   }else if(action=="fishing_collect"){
    auto reward=data(c,"reward");auto marker=reward.isEmpty()?nullptr:c->getZoneServer()->getObject(UnsignedLong::valueOf(reward)).get();if(!marker || marker->getZone()!=c->getZone() || !c->isInRange(marker,10) || !CollisionManager::checkLineOfSight(c,marker))throw std::runtime_error("Fishing catch unavailable or out of reach");
    Locker lock(marker,c);auto inv=c->getInventory();while(marker->getContainerObjectsSize()>0){auto loot=marker->getContainerObject(0);String error;if(inv->canAddObject(loot,-1,error)!=0 || !c->getZoneServer()->getObjectController()->transferObject(loot,inv,-1,true))throw std::runtime_error("Free inventory space to collect catch");loot->updateToDatabase();}m->removeMarker(c,marker);put(c,"reward","");put(c,"message","Catch collected");
   }else throw std::runtime_error("Unknown fishing action");
   result["request_id"]=key;receipts.push_back({{"id",key},{"request",proposal},{"result",result}});while(receipts.size()>64)receipts.erase(receipts.begin());put(c,"receipts",receipts.dump());c->updateToDatabaseAllObjects(false);
  }
  return {{"backend","core3"},{"source_kind","core3_services"},{"character_id",id(c)},{"fishing",state(c,rod)},{"inventory",SwgxrInventory::snapshot(c)},{"mutation",result}};
 }
};
#endif
