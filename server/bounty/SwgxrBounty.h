#ifndef SWGXR_BOUNTY_H
#define SWGXR_BOUNTY_H
#include "server/zone/objects/mission/BountyMissionObjective.h"
#include "server/zone/objects/mission/bountyhunter/BountyHunterDroid.h"
#include "server/zone/objects/creature/conversation/ConversationTemplate.h"
#include "server/zone/objects/creature/conversation/screenhandlers/InformantMissionScreenHandler.h"
#include "server/zone/managers/creature/CreatureTemplateManager.h"
#include "server/zone/managers/mission/MissionManager.h"
#include "server/zone/managers/collision/CollisionManager.h"
#include "server/zone/objects/waypoint/WaypointObject.h"
// Presentation only: native objectives, consumables, tasks, observers and reward
// transaction remain authoritative. Never project unrevealed target coordinates.
class SwgxrBounty {
 using Json=JSONSerializationType;
 static std::string str(const String& s){return s.toCharArray();}
 static std::string id(SceneObject* o){return o?std::to_string(o->getObjectID()):"0";}
 static uint64 oid(const Json& r,const char* field){auto s=r.at(field).get<std::string>();if(s.empty() || s.size()>20 || s.find_first_not_of("0123456789")!=std::string::npos)throw std::runtime_error("invalid_bounty_object_id");auto n=std::stoull(s);if(!n)throw std::runtime_error("invalid_bounty_object_id");return n;}
 static Reference<BountyMissionObjective*> objective(MissionObject* m){return m!=nullptr?cast<BountyMissionObjective*>(m->getMissionObjective()):nullptr;}
 static ManagedReference<MissionObject*> owned(CreatureObject* c){auto m=c->getZoneServer()->getMissionManager()->getBountyHunterMission(c);if(m==nullptr || !eligible(m) || m->getParent().get()!=c->getSlottedObject("datapad") || objective(m)==nullptr)throw std::runtime_error("owned_active_pve_bounty_required");return m;}
 static bool near(CreatureObject* c,SceneObject* o,float range){return o!=nullptr && o->getZone()==c->getZone() && o->getParentID()==c->getParentID() && c->isInRange(o,range) && CollisionManager::checkLineOfSight(c,o);}
 static Json actor(SceneObject* o){auto p=o->getWorldPosition();auto parent=o->getParent().get();auto root=o->getRootParent();int cell=parent!=nullptr && parent->isCellObject()?static_cast<CellObject*>(parent.get())->getCellNumber():0;return {{"id",id(o)},{"name",str(o->getDisplayedName())},{"template",str(o->getObjectTemplate()->getFullTemplateString())},{"client_crc",o->getClientObjectCRC()},{"position",Json::array({p.getX(),p.getZ(),p.getY()})},{"heading_radians",o->getDirection()->getRadians()+(cell && root?root->getDirection()->getRadians():0)},{"building_id",cell && root?id(root):"0"},{"cell_index",cell}};}
 static ConversationScreen* informantScreen(SceneObject* o){if(o==nullptr || !o->isAiAgent())return nullptr;auto ai=static_cast<AiAgent*>(o);auto mobile=ai->getCreatureTemplate();if(mobile==nullptr)return nullptr;auto convo=CreatureTemplateManager::instance()->getConversationTemplate(mobile->getConversationTemplate());if(convo==nullptr || convo->getConversationTemplateType()!=ConversationTemplate::ConversationTemplateTypeInformantMission)return nullptr;auto screen=convo->getInitialScreen();return screen!=nullptr && screen->getOptionCount()>0?screen:nullptr;}
 static int informantLevel(SceneObject* o){auto screen=informantScreen(o);if(screen==nullptr)return 0;auto link=screen->getOptionLink(0);return link=="1"?1:link=="2"?2:link=="3"?3:0;}
 static std::string droidKind(SceneObject* o){if(o==nullptr || !o->isTangibleObject() || o->getObjectTemplate()==nullptr)return "";auto name=o->getObjectTemplate()->getTemplateFileName();return name=="mission_bounty_droid_probot"?"probe":name=="mission_bounty_droid_seeker"?"seeker":"";}
 static bool outside(CreatureObject* c){return c->getParentID()==0 && !c->isRidingMount();}
 static bool canCall(CreatureObject* c){return outside(c);}
public:
 static bool eligible(MissionObject* m){return m!=nullptr && m->getTypeCRC()==MissionTypes::BOUNTY && m->getTargetObjectId()==0 && !m->getTargetOptionalTemplate().isEmpty();}
 static Json describe(MissionObject* m,bool active){Json out={{"pve_only",true},{"level",m->getMissionLevel()},{"mission_id",id(m)},{"stage",active?"informant":"offer"},{"signature",false},{"planet_known",false},{"planet",""},{"waypoint",{{"active",false},{"planet",""},{"position",Json::array()}}}};auto task=active?objective(m):nullptr;if(task!=nullptr){auto state=Json::parse(task->swgxrState().toCharArray());for(auto& field:state.items())out[field.key()]=field.value();}return out;}
 static Json snapshot(CreatureObject* c){
  auto m=c->getZoneServer()->getMissionManager()->getBountyHunterMission(c);if(m!=nullptr && !eligible(m))m=nullptr;auto task=objective(m);
  Json out=m!=nullptr?describe(m,true):Json{{"pve_only",true},{"mission_id","0"},{"level",0},{"stage","none"},{"signature",false},{"planet_known",false},{"planet",""},{"waypoint",{{"active",false},{"planet",""},{"position",Json::array()}}}};
  out["informants"]=Json::array();out["droids"]=Json::array();out["probe"]=Json::object();out["planets"]=Json::array();for(auto planet:{"corellia","dantooine","dathomir","endor","lok","naboo","rori","talus","tatooine","yavin4"})if(c->getZoneServer()->getZone(planet)!=nullptr)out["planets"].push_back(planet);
  bool signature=out.value("signature",false),busy=out.value("searching",false),skill=c->hasSkill("combat_bountyhunter_investigation_01"),track=c->hasSkill("combat_bountyhunter_investigation_03");
  auto probe=task!=nullptr?task->getArakydDroid():nullptr;
  if(probe!=nullptr && !probe->isPlayerCreature() && probe->getZone()==c->getZone()){out["probe"]=actor(probe);out["probe"]["kind"]="bounty_probe";out["probe"]["status"]=busy?"searching":"ready";out["probe"]["can_transmit"]=false;}
  auto inv=c->getInventory();if(inv!=nullptr)for(int i=0;i<inv->getContainerObjectsSize() && out["droids"].size()<128;++i){auto o=inv->getContainerObject(i);auto kind=droidKind(o);if(kind.empty())continue;auto t=static_cast<TangibleObject*>(o.get());bool ready=task!=nullptr && m->getMissionLevel()>=2 && skill && signature && !busy;out["droids"].push_back({{"id",id(o)},{"kind",kind},{"uses",std::max(1,t->getUseCount())},{"call_enabled",kind=="probe" && ready && probe==nullptr && canCall(c)},{"find_enabled",kind=="seeker" && ready && outside(c)},{"track_enabled",kind=="seeker" && ready && track && m->getMissionLevel()>=3 && outside(c)}});}
  SortedVector<TreeEntry*> nearby;auto p=c->getWorldPosition();c->getZone()->getInRangeObjects(p.getX(),p.getZ(),p.getY(),64,&nearby,true);auto cell=c->getParent().get();if(cell!=nullptr && cell->isCellObject())for(int i=0;i<cell->getContainerObjectsSize();++i)nearby.put(cell->getContainerObject(i));
  for(int i=0;i<nearby.size() && out["informants"].size()<64;++i){auto o=static_cast<SceneObject*>(nearby.get(i));int level=informantLevel(o);if(!level)continue;auto row=actor(o);row["kind"]="bounty_informant";row["level"]=level;row["eligible"]=m!=nullptr && level==m->getMissionLevel() && c->hasSkill("combat_bountyhunter_novice");row["can_contact"]=row["eligible"].get<bool>() && !signature && near(c,o,3);out["informants"].push_back(row);}
  return out;
 }
 static Json mutate(CreatureObject* c,const Json& r){
  auto m=owned(c);auto task=objective(m);auto action=r.at("action").get<std::string>();if(!c->hasSkill("combat_bountyhunter_novice"))throw std::runtime_error("novice_bounty_hunter_required");
  Json out={{"success",true},{"operation",action},{"mission_id",id(m)}};
  if(action=="bounty_informant"){
   auto npc=c->getZoneServer()->getObject(oid(r,"target_id"));if(!near(c,npc,3) || informantLevel(npc)!=m->getMissionLevel() || npc->asCreatureObject()->isDead() || npc->asCreatureObject()->isIncapacitated())throw std::runtime_error("bounty_informant_level_cell_range_or_los");
   if(task->getObjectiveStatus()!=BountyMissionObjective::INITSTATUS)throw std::runtime_error("bounty_signature_already_received");
   ConversationScreen screen(*informantScreen(npc));InformantMissionScreenHandler handler;handler.handleScreen(c,npc,0,&screen);
   if(task->getObjectiveStatus()!=BountyMissionObjective::HASBIOSIGNATURESTATUS)throw std::runtime_error("native_bounty_informant_rejected");out["dialogue"]=str(screen.getDialogText()->getFullPath());out["target_id"]=id(npc);
  }else{
   if(!c->hasSkill("combat_bountyhunter_investigation_01") || m->getMissionLevel()<2 || task->getObjectiveStatus()==BountyMissionObjective::INITSTATUS)throw std::runtime_error("bounty_investigation_and_signature_required");
   auto state=Json::parse(task->swgxrState().toCharArray());if(state.value("searching",false))throw std::runtime_error("bounty_droid_search_in_progress");
   if(!outside(c))throw std::runtime_error("bounty_droid_requires_outdoors_unmounted");
   ManagedReference<SceneObject*> droid;int command=0;
   droid=c->getZoneServer()->getObject(oid(r,"item_id"));if(droid==nullptr || droid->getParent().get()!=c->getInventory())throw std::runtime_error("owned_inventory_bounty_droid_required");auto kind=droidKind(droid);
   if(action=="bounty_probe"){
    if(kind!="probe" || task->getArakydDroid()!=nullptr || !canCall(c))throw std::runtime_error("probe_requires_outdoors_location");
    auto planet=r.at("search_planet").get<std::string>();bool allowed=false;for(auto name:{"corellia","dantooine","dathomir","endor","lok","naboo","rori","talus","tatooine","yavin4"})if(planet==name && c->getZoneServer()->getZone(name)!=nullptr)allowed=true;if(!allowed)throw std::runtime_error("loaded_ground_search_planet_required");
    String selectedPlanet(planet.c_str());task->setSwgxrSearchPlanet(selectedPlanet);out["search_planet"]=planet;command=BountyHunterDroid::CALLDROID;
   }else if(action=="bounty_seek" || action=="bounty_track"){if(kind!="seeker")throw std::runtime_error("seeker_droid_required");bool tracking=action=="bounty_track";if(tracking && (!c->hasSkill("combat_bountyhunter_investigation_03") || m->getMissionLevel()<3))throw std::runtime_error("investigation_three_required");command=tracking?BountyHunterDroid::FINDANDTRACKTARGET:BountyHunterDroid::FINDTARGET;}else throw std::runtime_error("unknown_bounty_action");
   out["item_id"]=id(droid);if(!task->performDroidAction(command,droid,c))throw std::runtime_error("native_bounty_droid_rejected");out["consumed_charge"]=true;
  }
  task->updateToDatabase();return out;
 }
};
#endif
