#ifndef SWGXR_CRAFTING_H
#define SWGXR_CRAFTING_H
#include "SwgxrServices.h"
#include "SwgxrCraftingView.h"
#include "SwgxrGathering.h"
#include "server/zone/objects/player/sessions/crafting/CraftingSession.h"
#include "server/zone/objects/player/sessions/crafting/events/CreateObjectTask.h"
#include "server/zone/objects/tangible/tool/CraftingStation.h"
#include <map>
#include <cmath>
class SwgxrCrafting : public SwgxrCraftingView {
 static ManagedReference<SceneObject*> object(CreatureObject* c,const std::string& key){return key.empty()?nullptr:c->getZoneServer()->getObject(std::stoull(key));}
 static ManagedReference<CraftingTool*> owned(CreatureObject* c,const std::string& key){auto g=SwgxrGathering::load(c);auto o=SwgxrGathering::ownedTool(c,g,key);auto t=o.castTo<CraftingTool*>();if(t==nullptr)throw std::runtime_error("An owned crafting tool is required");return t;}
 static Reference<CraftingSession*> session(CreatureObject* c,const Json& d){if(!d.is_object())return nullptr;auto t=object(c,d.value("tool_id",std::string()));return t==nullptr?nullptr:t->getActiveSession(SessionFacadeType::CRAFTING).castTo<CraftingSession*>();}
 static void transfer(SceneObject* item,SceneObject* destination){if(item==nullptr || destination==nullptr || !destination->transferObject(item,-1,true))throw std::runtime_error("Native crafting object transfer failed");}
 static void erase(SceneObject* o){if(o!=nullptr){o->destroyObjectFromWorld(true);o->destroyObjectFromDatabase(true);}}
 static void restore(CreatureObject* c,Json& s,bool consume){
  if(!s["draft"].is_object())return;
  // Return exact original objects; clones used for assembly never enter inventory.
  auto& entries=s["draft"]["escrow"];
  while(!entries.empty()){
   Json e=entries.back();auto o=object(c,e["id"]);auto parent=object(c,e["parent"]);
   if(o==nullptr || parent==nullptr)throw std::runtime_error("Escrow object or original container missing; recovery retained");
   if(consume){int n=e["consume"].get<int>();if(o->isResourceContainer()){auto r=o.castTo<ResourceContainer*>();r->setQuantity(r->getQuantity()-n,true);if(r->getQuantity()<=0)o=nullptr;}
    else if(o->isFactoryCrate() || o->asTangibleObject()->getUseCount()>1){int remaining=o->asTangibleObject()->getUseCount()-n;if(remaining<=0){erase(o);o=nullptr;}else o->asTangibleObject()->setUseCount(remaining,true);}
    else{erase(o);o=nullptr;}}
   // Refund uses its reserved slot, even if an administrative grant bypassed
   // capacity. Keep the journal entry until the native transfer succeeds.
   if(o!=nullptr && o->getParent().get()!=parent && !parent->transferObject(o,-1,true,true))throw std::runtime_error("Cannot restore reserved ingredient; escrow retained");
   entries.erase(entries.end()-1);save(c,s);
  }
 }
 static void cancel(CreatureObject* c,Json& s){
  auto cs=session(c,s["draft"]);if(cs!=nullptr){Locker lock(cs,c);cs->cancelSession();}
  if(!s["draft"].is_object())return;
  restore(c,s,false);auto store=object(c,s["draft"].value("store",std::string()));erase(store);s["draft"]=nullptr;save(c,s);
 }
 static void settle(CreatureObject* c,Json& s){
  if(s["draft"].is_object() && (session(c,s["draft"])==nullptr || s["draft"].value("expires",int64(0))<std::time(nullptr)))cancel(c,s);
  auto jobs=s["jobs"];for(auto& job:jobs){auto t=object(c,job["tool_id"]).castTo<CraftingTool*>();if(t==nullptr)throw std::runtime_error("Reserved crafting tool missing");if(job["due"].get<int64>()<=std::time(nullptr)){Reference<CreateObjectTask*> task=new CreateObjectTask(c,t,false);task->run();}else t->setBusy();}
  s=load(c);
 }
 static void walk(SceneObject* parent,std::vector<ManagedReference<TangibleObject*>>& items,int depth=0){if(parent==nullptr || depth>8 || items.size()>256)return;for(int i=0;i<parent->getContainerObjectsSize();++i){auto o=parent->getContainerObject(i);if(o->isTangibleObject())items.push_back(o.castTo<TangibleObject*>());if(o->getContainerVolumeLimit()>0 && !o->isCraftingTool() && !o->isFactoryCrate())walk(o,items,depth+1);}}
 static Json inventory(CreatureObject* c,DraftSchematic* d){
  Json result=Json::array();std::vector<ManagedReference<TangibleObject*>> items;walk(c->getInventory(),items);for(int i=0;i<c->getSlottedObjectsSize();++i){auto o=c->getSlottedObject(i);if(o!=nullptr && o->isWearableContainerObject())walk(o,items);}
  for(auto& o:items){Json slots=Json::array();for(int i=0;i<d->getDraftSlotCount();++i)if(fits(o,d->getDraftSlot(i)))slots.push_back(i);if(slots.empty())continue;
   auto row=SwgxrInventory::describe(o,c);row["quantity"]=quantity(o);row["slots"]=slots;row["quality"]=Json::array();
   if(o->isResourceContainer()){auto spawn=o.castTo<ResourceContainer*>()->getSpawnObject();for(int i=0;i<d->getResourceWeightCount();++i){auto weight=d->getResourceWeight(i);if(weight->isFiller())continue;float value=0;for(int j=0;j<weight->getPropertyListSize();++j)value+=spawn->getValueOf(weight->getTypeAndWeight(j)>>4)*weight->getPropertyPercentage(j);row["quality"].push_back({{"name",text(weight->getExperimentalTitle())},{"value",value/1000.f}});}}
   result.push_back(row);
  }return result;
 }
 static Json view(CreatureObject* c,Json& s){
  Json out={{"source_kind","core3_crafting"},{"character_id",id(c)},{"stage",0},{"jobs",s["jobs"]},{"server_time",std::time(nullptr)},{"session_id",""},{"inventory",Json::array()}};
  auto cs=session(c,s["draft"]);if(cs!=nullptr){auto v=Json::parse(cs->swgxrSnapshot().toCharArray());out.update(v);out["session_id"]=s["draft"]["session_id"];out["tool_id"]=s["draft"]["tool_id"];auto m=cs->getSchematic().get();if(m!=nullptr && cs->getState()==2)out["inventory"]=inventory(c,m->getDraftSchematic());}
  return out;
 }
 static void assemble(CreatureObject* c,Json& s,CraftingSession* cs,CraftingTool* tool,const Json& request){
  auto m=cs->getSchematic().get();if(cs->getState()!=2 || m==nullptr)throw std::runtime_error("Select a schematic first");
  auto d=m->getDraftSchematic();auto allocations=request.at("allocations");if(!allocations.is_array() || allocations.size()!=size_t(d->getDraftSlotCount()))throw std::runtime_error("Ingredient slot count mismatch");
  std::map<std::string,int> totals;std::vector<std::pair<int,ManagedReference<TangibleObject*>>> picks;
  for(int i=0;i<d->getDraftSlotCount();++i){auto slot=d->getDraftSlot(i);auto list=allocations[i];if(!list.is_array() || list.size()>64)throw std::runtime_error("Invalid slot ingredients");if(list.empty() && slot->getSlotType()>=3)continue;int remaining=slot->getQuantity();String serial;
   for(auto& key:list){auto o=object(c,key.get<std::string>()).castTo<TangibleObject*>();if(o==nullptr || !SwgxrEquipment::inInventory(o,c) || o==tool || !fits(o,slot))throw std::runtime_error("Ingredient ownership or type changed");
    if(remaining<=0)throw std::runtime_error("Slot contains extra ingredients");int units=std::min(remaining,quantity(o));if(slot->getSlotType()==0 && units<remaining)throw std::runtime_error("Resource stack cannot fill the slot");
    ManagedReference<TangibleObject*> actual=o;if(o->isFactoryCrate())actual=o.castTo<FactoryCrate*>()->getPrototype();if(slot->getSlotType()==1 || slot->getSlotType()==3){if(!serial.isEmpty() && serial!=actual->getSerialNumber())throw std::runtime_error("Identical components required");serial=actual->getSerialNumber();}
    int consumed=o->isFactoryCrate()?(units+std::max(1,o.castTo<FactoryCrate*>()->getPrototypeUseCount())-1)/std::max(1,o.castTo<FactoryCrate*>()->getPrototypeUseCount()):units;
    totals[id(o)]+=consumed;int available=o->isFactoryCrate()?o->getUseCount():quantity(o);if(totals[id(o)]>available)throw std::runtime_error("Ingredients allocated more than once");remaining-=units;picks.push_back({i,o});
   }if(remaining!=0)throw std::runtime_error("Fill every required slot first");
  }
  auto store=c->getZoneServer()->createObject(STRING_HASHCODE("object/tangible/inventory/character_inventory.iff"),1);if(store==nullptr)throw std::runtime_error("Cannot create crafting escrow");store->setContainerVolumeLimit(256);store->setContainerOwnerID(c->getObjectID());store->setContainerInheritPermissionsFromParent(false);
  s["draft"]["store"]=id(store);s["draft"]["escrow"]=Json::array();save(c,s);
  try{
   for(auto& total:totals){auto o=object(c,total.first);s["draft"]["escrow"].push_back({{"id",id(o)},{"parent",id(o->getParent().get())},{"cost",1+(o->isCraftingTool()?0:o->getCountableObjectsRecursive())},{"consume",total.second}});save(c,s);transfer(o,store);}
   m->synchronizedUIListen(c,0);auto satchel=tool->getCraftedComponentsSatchel();
   for(auto& pick:picks){auto clone=ObjectManager::instance()->cloneObject(pick.second,true);if(clone==nullptr)throw std::runtime_error("Cannot stage native crafting ingredient");transfer(clone,store);int code=m->addIngredientToSlot(c,satchel,clone->asTangibleObject(),pick.first);if(code!=0)throw std::runtime_error("Core3 rejected staged ingredient: "+std::to_string(code));}
   if(!m->isReadyForAssembly())throw std::runtime_error("Native ingredient validation failed");cs->nextCraftingStage(0);
   if(cs->getState()==2)throw std::runtime_error("Critical assembly failure; original ingredients returned");
  }catch(...){cancel(c,s);throw;}
 }
 static void finish(CreatureObject* c,Json& s,CraftingSession* cs,CraftingTool* tool,const Json& request){
  if(cs->getState()!=3 && cs->getState()!=4)throw std::runtime_error("Assembly required before crafting");auto root=c->getInventory();
  // Escrow reservations are still counted: never promise a slot released by
  // consuming ingredients until the recipe has actually committed.
  if(root==nullptr || root->getCountableObjectsRecursive()>=root->getContainerVolumeLimit())throw std::runtime_error("No inventory slot available for crafted output");
  auto view=Json::parse(cs->swgxrSnapshot().toCharArray());auto points=request.value("points",Json::array());int total=0,rows=0;std::string exp;
  if(!points.is_array() || points.size()>view["rows"].size())throw std::runtime_error("Invalid experimentation allocation");
  for(size_t i=0;i<points.size();++i){if(!points[i].is_number_integer())throw std::runtime_error("Experimentation points must be integers");int n=points[i];if(n<0 || n>view["rows"][i]["point_limit"].get<int>())throw std::runtime_error("Experimentation row limit exceeded");total+=n;if(n){++rows;exp+=std::to_string(i)+" "+std::to_string(n)+" ";}}
  if(total>view["points"].get<int>() || (total && cs->getState()!=3))throw std::runtime_error("Experimentation allowance exceeded");
  auto colors=request.value("colors",Json::array());if(!colors.is_array() || colors.size()>view["colors"].size())throw std::runtime_error("Invalid color choices");std::string customization;
  for(size_t i=0;i<colors.size();++i){if(!colors[i].is_number_integer())throw std::runtime_error("Invalid palette index");int n=colors[i];auto v=view["colors"][i];if(n<v["minimum"].get<int>() || n>v["maximum"].get<int>())throw std::runtime_error("Color is outside learned allowance");customization+=std::to_string(v["index"].get<int>())+" "+std::to_string(n)+" ";}
  if(rows)cs->experiment(rows,String(exp.c_str()),0);
  if(cs->getState()==3)cs->nextCraftingStage(0);
  cs->customization("",0xFF,1,String(customization.c_str()));cs->nextCraftingStage(0);
  auto m=cs->getSchematic().get();auto proto=tool->getPrototype();if(proto==nullptr || m==nullptr)throw std::runtime_error("Crafting prototype lost");
  // Persist the finished result before the ordinary timer, so restart can resume.
  ObjectManager::instance()->persistSceneObjectsRecursively(proto,1);
  auto due=std::time(nullptr)+int(m->getComplexity()*2)+1;
  s["jobs"].push_back({{"tool_id",id(tool)},{"prototype_id",id(proto)},{"parent",id(root)},{"cost",1},{"due",due},{"duration",int(m->getComplexity()*2)},{"template",text(proto->getObjectTemplate()->getFullTemplateString())}});save(c,s);
  restore(c,s,true);auto store=object(c,s["draft"].value("store",std::string()));erase(store);s["draft"]=nullptr;save(c,s);
  cs->createPrototype(0,true);
  if(!tool->isBusy())throw std::runtime_error("Native crafting timer did not start");
 }
public:
 static Json run(CreatureObject* c,const Json& request){
  Json s=load(c);settle(c,s);auto action=request.value("action",std::string("status"));auto key=request.value("request_id",std::string());Json mutation={{"success",true},{"operation",action}};
  if(action!="status" && (key.size()<8 || key.size()>64))throw std::runtime_error("Invalid request identifier");
  if(action!="status")for(auto& receipt:s["receipts"])if(receipt["id"]==key){if(receipt["request"]!=request)throw std::runtime_error("Request identifier reused");return {{"character_id",id(c)},{"state",view(c,s)},{"mutation",receipt["mutation"]}};}
  if(action!="status"){
   if(action=="cancel"){if(s["draft"].is_object() && request.value("session_id",std::string())!=s["draft"].value("session_id",std::string()))throw std::runtime_error("Stale crafting session");cancel(c,s);}
   else{
    if(c->isDead() || c->isIncapacitated() || c->getActiveSession(SessionFacadeType::TRADE)!=nullptr)throw std::runtime_error("Player cannot craft now");
    SwgxrServices::move(c,request);
    auto tool=owned(c,request.at("tool_id").get<std::string>());Locker toolLock(tool,c);
    if(action=="open"){
     if(tool->isBusy() || tool->isFinished())throw std::runtime_error("Tool is already producing an item");cancel(c,s);
     auto station=c->getZoneServer()->getPlayerManager()->getNearbyCraftingStation(c,tool->getToolType());Reference<CraftingSession*> cs=new CraftingSession(c);cs->initializeSession(tool,station);
     s["draft"]={{"tool_id",id(tool)},{"session_id",key},{"expires",std::time(nullptr)+300},{"escrow",Json::array()}};save(c,s);
    }else{
     if(!s["draft"].is_object() || s["draft"]["tool_id"]!=id(tool) || request.value("session_id",std::string())!=s["draft"].value("session_id",std::string()))throw std::runtime_error("Stale crafting session");
     auto cs=session(c,s["draft"]);if(cs==nullptr)throw std::runtime_error("Crafting session expired");Locker lock(cs,c);c->addActiveSession(SessionFacadeType::CRAFTING,cs);
     if(action=="select"){if(cs->getState()>2)throw std::runtime_error("Cancel assembled draft before changing schematic");int index=request.at("index").get<int>();auto choices=Json::parse(cs->swgxrSnapshot().toCharArray())["schematics"];if(index<0 || index>=int(choices.size()))throw std::runtime_error("Schematic is not usable with this tool");cs->selectDraftSchematic(index);}
     else if(action=="assemble"){assemble(c,s,cs,tool,request);if(cs->getState()==4)finish(c,s,cs,tool,request);}
     else if(action=="finish")finish(c,s,cs,tool,request);
     else throw std::runtime_error("Unknown crafting action");
    }
   }
   s["receipts"].push_back({{"id",key},{"request",request},{"mutation",mutation}});while(s["receipts"].size()>32)s["receipts"].erase(s["receipts"].begin());
  }
  if(s["draft"].is_object())s["draft"]["expires"]=std::time(nullptr)+300;save(c,s);
  // The local RPC transport disconnects after each request. Keep the session
  // on its owned tool; explicit cancellation/restart recovery refunds escrow.
  c->dropActiveSession(SessionFacadeType::CRAFTING);
  return {{"character_id",id(c)},{"state",view(c,s)},{"mutation",mutation}};
 }
};
#endif
