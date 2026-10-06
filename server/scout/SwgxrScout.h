#ifndef SWGXR_SCOUT_H
#define SWGXR_SCOUT_H
#include "SwgxrPlanets.h"
#include "SwgxrGathering.h"
#include "SwgxrBioEngineer.h"
#include "SwgxrRanger.h"
#include "server/zone/objects/area/CampSiteActiveArea.h"
#include "server/zone/objects/tangible/components/CampKitMenuComponent.h"
#include "server/zone/objects/tangible/components/CampTerminalMenuComponent.h"
#include "server/zone/objects/tangible/terminal/Terminal.h"
#include "server/zone/objects/creature/ai/AiAgent.h"
#include "templates/tangible/TrapTemplate.h"
#include "server/zone/managers/collision/CollisionManager.h"
class SwgxrScout {
 using Json=JSONSerializationType;
 static std::string id(SceneObject* o){return o?std::to_string(o->getObjectID()):"";}
 static Json position(SceneObject* o){auto p=o->getWorldPosition();return Json::array({p.getX(),p.getZ(),p.getY()});}
 static double cooldown(CreatureObject* c,const char* name){auto t=c->getCooldownTime(name);return t?std::max(0.0,double(t->getMiliTime())/1000.0-std::time(nullptr)):0;}
 static bool learned(CreatureObject* c,const char* name){auto command=c->getZoneServer()->getObjectController()->getQueueCommand(name);return command && (command->getCharacterAbility().isEmpty() || c->getPlayerObject()->hasAbility(command->getCharacterAbility()));}
 static void command(CreatureObject* c,const char* name,uint64 target=0,const String& args=""){
  auto cmd=c->getZoneServer()->getObjectController()->getQueueCommand(name);
  if(!cmd || !learned(c,name) || cmd->doQueueCommand(c,target,UnicodeString(args))!=QueueCommand::SUCCESS)throw std::runtime_error(std::string(name)+" rejected by Core3 skill, state, range or cooldown rules");
 }
 static bool eligible(CreatureObject* c,SceneObject* o){auto ai=o?o->asAiAgent():nullptr;return ai && !ai->isDead() && !ai->isIncapacitated() && !ai->isPet() && ai->isCreature() && ai->isMonster() && ai->isAttackableBy(c);}
 static Json visual(SceneObject* o){return {{"id",id(o)},{"template",std::string(o->getObjectTemplate()->getFullTemplateString().toCharArray())},{"position",position(o)},{"heading_radians",o->getDirectionAngle()*M_PI/180.0}};}
 static Json camps(CreatureObject* c){
  Json result=Json::array();SortedVector<TreeEntry*> nearby(256,256);c->getZone()->getInRangeObjects(c->getPositionX(),c->getPositionZ(),c->getPositionY(),128,&nearby,true);
  for(int i=0;i<nearby.size() && result.size()<16;++i){auto object=static_cast<SceneObject*>(nearby.get(i));if(!object->isCampStructure())continue;auto camp=static_cast<StructureObject*>(object);Locker lock(camp,c);auto areas=camp->getActiveAreas();
   for(int n=0;n<areas->size();++n){auto area=areas->get(n).castTo<CampSiteActiveArea*>();if(area==nullptr)continue;
    Json entry=visual(camp);auto owner=area->getOwner();entry["owner_id"]=id(owner);entry["owner"]=owner?std::string(owner->getDisplayedName().toCharArray()):"";entry["uptime_seconds"]=area->getUptime();entry["visitors"]=area->getVisitorCount();entry["abandoned"]=area->isAbandoned();entry["can_disband"]=camp->getOwnerObjectID()==c->getObjectID();entry["objects"]=Json::array();entry["terminal_id"]="";
    auto children=camp->getChildObjects();for(int k=0;k<children->size() && k<128;++k){auto child=children->get(k);if(child==nullptr)continue;entry["objects"].push_back(visual(child));if(child->isTerminal()){entry["terminal_id"]=id(child);entry["terminal_position"]=position(child);}}
    for(int f=0;f<nearby.size();++f){auto fire=static_cast<SceneObject*>(nearby.get(f));auto name=fire->getObjectTemplate()->getFullTemplateString();if(camp->isInRange(fire,1) && (name=="object/static/structure/general/campfire_fresh.iff" || name=="object/static/structure/general/campfire_smoldering.iff"))entry["objects"].push_back(visual(fire));}
    result.push_back(entry);break;
   }
  }return result;
 }
 static Json snapshot(CreatureObject* c){
  Json state={{"zone",SwgxrPlanets::name(c)},{"source_kind","core3_scout"},{"character_id",id(c)},{"server_time",std::time(nullptr)},{"scout",c->hasSkill("outdoors_scout_novice")},{"forage_available",c->hasSkill("outdoors_scout_novice") && learned(c,"forage")},{"foraging",c->getPendingTask("foraging")!=nullptr},{"mask_scent_available",c->getSkillMod("mask_scent")>0 && learned(c,"maskscent")},{"mask_scent_active",c->hasBuff(STRING_HASHCODE("skill_buff_mask_scent_self"))},{"mask_scent_cooldown",cooldown(c,"skill_buff_mask_scent_self")},{"mask_scent_duration",6*c->getSkillMod("mask_scent")},{"burst_available",learned(c,"burstrun")},{"burst_active",c->hasBuff(STRING_HASHCODE("burstrun"))},{"burst_cooldown",cooldown(c,"burstrun")},{"trap_cooldown",cooldown(c,"throwtrap")},{"trap_pending",c->getPendingTask("throwtrap")!=nullptr},{"slope_move",c->getSkillMod("slope_move")},{"slope_fraction",c->getSlopeModPercent()},{"harvesting",c->getSkillMod("creature_harvesting")},{"foraging_mod",c->getSkillMod("foraging")},{"burst_run_mod",c->getSkillMod("burst_run")},{"camps",camps(c)},{"targets",Json::array()},{"items",Json::array()},{"hip_tool",nullptr},{"ham",Json::array()}};
  SwgxrBioEngineer::status(c,state);
  state["ranger"]=SwgxrRanger::status(c);
  state["inventory"]=SwgxrInventory::snapshot(c);
  auto burst=c->getBuff(STRING_HASHCODE("burstrun"));state["burst_remaining"]=burst!=nullptr?burst->getTimeLeft():0.f;
  for(int i=0;i<9;++i)state["ham"].push_back(c->getHAM(i));
  auto root=c->getSlottedObject("inventory");if(root!=nullptr){std::vector<SceneObject*> todo{root};std::set<uint64> seen;while(!todo.empty() && seen.size()<256){auto container=todo.back();todo.pop_back();if(!seen.insert(container->getObjectID()).second)continue;for(int i=0;i<container->getContainerObjectsSize();++i){auto o=container->getContainerObject(i);if(o->isTrapObject() || o->isCampKit())state["items"].push_back(SwgxrInventory::describe(o,c));else if(o->getContainerVolumeLimit()>0 && !o->isFactoryCrate() && !o->isCraftingTool())todo.push_back(o);}}}
  auto gathering=SwgxrGathering::load(c);auto hip=SwgxrGathering::object(c,gathering.value("hip_tool_id",std::string()));if(hip!=nullptr)state["hip_tool"]=SwgxrInventory::describe(hip,c);
  SortedVector<TreeEntry*> objects(256,256);c->getZone()->getInRangeObjects(c->getPositionX(),c->getPositionZ(),c->getPositionY(),64,&objects,true);
  for(int i=0;i<objects.size() && state["targets"].size()<96;++i){auto o=static_cast<SceneObject*>(objects.get(i));if(o==c || !o->isCreatureObject())continue;Locker targetLock(o,c);bool trapEligible=eligible(c,o),dnaEligible=SwgxrBioEngineer::eligible(c,o);if(!trapEligible && !dnaEligible)continue;auto entry=visual(o);double scale=o->asCreatureObject()->getHeight(false);auto appearance=o->getAppearanceTemplate();auto volume=appearance?appearance->getBoundingVolume():nullptr;
   entry["bounds"]=nullptr;
   if(volume!=nullptr){const auto& sphere=volume->getBoundingSphere();const auto& center=sphere.getCenter();double radius=sphere.getRadius()*scale;
    if(std::isfinite(radius) && radius>0 && radius<=128)entry["bounds"]={{"center",Json::array({center.getX()*scale,center.getY()*scale,center.getZ()*scale})},{"radius",radius},{"source","original_appearance_sphere"}};
   }
   entry["dna_eligible"]=dnaEligible;entry["eligible"]=trapEligible;state["targets"].push_back(entry);}
  return state;
 }
public:
 static Json run(CreatureObject* c,const Json& request){
  SwgxrPlanets::require(c,request);
  auto verb=request.value("action",std::string("status"));bool ranger=SwgxrRanger::action(verb);
  if(!c || !c->getPlayerObject() || !c->getZone() || !SwgxrPlanets::supported(c->getZone()->getZoneName()) || (!ranger && c->getParent().get()!=nullptr))throw std::runtime_error("Scout actions require outdoors a supported planet");
  auto p=SwgxrGathering::position(request);
  if(!c->isDead() && !c->isIncapacitated()){
   if(!ranger)c->teleport(p[0].get<float>(),p[1].get<float>(),p[2].get<float>(),0);
   if(request.contains("posture") && !c->isKnockedDown() && c->getPendingTask("foraging")==nullptr){
    auto posture=request.at("posture").get<std::string>();if(posture!="standing" && posture!="kneeling" && posture!="prone")throw std::runtime_error("Invalid tracked posture");
    c->setPosture(posture=="prone"?CreaturePosture::PRONE:posture=="kneeling"?CreaturePosture::CROUCHED:CreaturePosture::UPRIGHT,true);
   }
  }
  auto raw=c->getPlayerObject()->getScreenPlayData("swgxr_scout","receipts");Json receipts=raw.isEmpty()?Json::array():Json::parse(raw.toCharArray());Json mutation={{"success",true},{"action",verb}};
  if(verb!="status" && verb!="ranger_status"){
   auto semantic=request;if(ranger)for(auto field:{"position","building_id","cell_index","zone","planet","hand_position","posture"})semantic.erase(field);
   const auto key=request.at("request_id").get<std::string>();if(key.size()<8 || key.size()>64)throw std::runtime_error("Invalid request id");bool replay=false;
   for(auto& r:receipts)if(r["key"]==key){if(r["request"]!=semantic)throw std::runtime_error("Request id reused");mutation=r["mutation"];mutation["replayed"]=true;replay=true;break;}
   if(!replay){
    if(c->isDead() || c->isIncapacitated())throw std::runtime_error("Player cannot act");
    if(ranger)SwgxrRanger::execute(c,request,mutation);
    else if(verb=="holster" || verb=="return_tool"){
     auto g=SwgxrGathering::load(c);auto trap=SwgxrGathering::ownedTool(c,g,request.at("item_id").get<std::string>());if(!trap->isTrapObject())throw std::runtime_error("Scout belt only accepts owned traps");
     auto q=request;q["tool_id"]=id(trap);SwgxrGathering::execute(c,g,q);SwgxrGathering::save(c,g);
    }else if(verb=="forage"){
     if(!c->hasSkill("outdoors_scout_novice") || c->getPendingTask("foraging")!=nullptr || c->isInCombat())throw std::runtime_error("Foraging unavailable or already in progress");
     command(c,"forage");if(c->getPendingTask("foraging")==nullptr)throw std::runtime_error("Core3 rejected foraging");
    }else if(verb=="mask_scent")command(c,"maskscent");
    else if(verb=="burst_run")command(c,"burstrun");
    else if(verb=="sample_dna"){SwgxrBioEngineer::run(c,request);mutation["target_id"]=request.at("target_id");mutation["sampling_started"]=true;}
    else if(verb=="discard_sample_dna")SwgxrBioEngineer::discard(c);
    else if(verb=="discard_mask_scent"){
     if(c->getSkillMod("mask_scent")<=0)throw std::runtime_error("Mask scent not learned");
     c->addCooldown("skill_buff_mask_scent_self",6000*c->getSkillMod("mask_scent"));
    }else if(verb=="camp"){
     auto o=SwgxrGathering::object(c,request.at("item_id").get<std::string>());if(o==nullptr || !o->isCampKit() || !SwgxrEquipment::inInventory(o,c))throw std::runtime_error("Owned camp kit required");
     if(!c->isStanding())throw std::runtime_error("Stand up before deploying a camp");
     if(c->isInCombat())throw std::runtime_error("Cannot deploy a camp during combat");
     if(c->isInWater())throw std::runtime_error("Cannot deploy a camp in water");
     if(c->getCityRegion().get()!=nullptr)throw std::runtime_error("Cannot deploy a camp inside a city");
     if(c->getCurrentCamp()!=nullptr)throw std::runtime_error("Leave the existing camp before deploying another");
     for(int i=0;i<c->getPlayerObject()->getTotalOwnedStructureCount();++i){auto existing=c->getZoneServer()->getObject(c->getPlayerObject()->getOwnedStructure(i));if(existing!=nullptr && existing->isCampStructure())throw std::runtime_error("Disband your existing camp before deploying another");}
     int before=c->getPlayerObject()->getTotalOwnedStructureCount();CampKitMenuComponent component;component.handleObjectMenuSelect(o,c,20);
     if(c->getPlayerObject()->getTotalOwnedStructureCount()<=before)throw std::runtime_error("Core3 rejected camp placement: skill, posture, terrain or proximity restrictions");
    }else if(verb=="disband"){
     auto terminal=SwgxrGathering::object(c,request.at("terminal_id").get<std::string>()).castTo<Terminal*>();if(terminal==nullptr || !c->isInRange(terminal,16))throw std::runtime_error("Camp terminal out of range");auto camp=dynamic_cast<StructureObject*>(terminal->getControlledObject());
     if(camp==nullptr || !camp->isCampStructure() || camp->getOwnerObjectID()!=c->getObjectID())throw std::runtime_error("Only the camp owner can disband");
     CampTerminalMenuComponent component;component.disbandCamp(terminal,c);
    }else if(verb=="trap"){
     auto g=SwgxrGathering::load(c);auto trap=SwgxrGathering::ownedTool(c,g,request.at("item_id").get<std::string>());
     if(!trap->isTrapObject())throw std::runtime_error("Owned trap required");
     // Native ThrowTrapTask requires a creature descendant; temporarily restore
     // a hip trap into its reserved owner inventory for the source command.
     bool hip=g.value("hip_tool_id",std::string())==id(trap);auto root=c->getSlottedObject("inventory");
     auto target=SwgxrGathering::object(c,request.at("target_id").get<std::string>());if(!eligible(c,target) || target->getZone()!=c->getZone())throw std::runtime_error("Invalid trap target");
     if(!CollisionManager::checkLineOfSight(c,target))throw std::runtime_error("Trap target obstructed");
     if(hip){SwgxrGathering::transfer(c,trap,root);g["hip_tool_id"]="";SwgxrGathering::save(c,g);}
     try{command(c,"throwtrap",target->getObjectID(),String(id(trap).c_str()));}catch(...){if(hip){SwgxrGathering::transfer(c,trap,SwgxrGathering::escrow(c,g));g["hip_tool_id"]=id(trap);SwgxrGathering::save(c,g);}throw;}
     if(hip){SwgxrGathering::transfer(c,trap,SwgxrGathering::escrow(c,g));g["hip_tool_id"]=id(trap);SwgxrGathering::save(c,g);}
     mutation["target_id"]=id(target);mutation["item_id"]=id(trap);
    }else throw std::runtime_error("Unsupported scout action");
    receipts.push_back({{"key",key},{"request",semantic},{"mutation",mutation}});while(receipts.size()>32)receipts.erase(receipts.begin());c->getPlayerObject()->setScreenPlayData("swgxr_scout","receipts",String(receipts.dump().c_str()));
   }
  }
  return {{"backend","core3"},{"zone",SwgxrPlanets::name(c)},{"source_kind","core3_scout"},{"character_id",id(c)},{"state",snapshot(c)},{"mutation",mutation}};
 }
};
#endif
