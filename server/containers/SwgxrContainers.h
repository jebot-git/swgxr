#ifndef SWGXR_CONTAINERS_H
#define SWGXR_CONTAINERS_H
#include "SwgxrInventory.h"
#include "server/zone/objects/tangible/Container.h"
#include "server/zone/objects/creature/ai/DroidObject.h"
#include "server/zone/objects/scene/variables/ContainerPermissions.h"
#include "server/zone/managers/collision/CollisionManager.h"
// Native containers only. Scenery without server storage is not made lootable.
class SwgxrContainers {
 using Json=JSONSerializationType;
 static std::string id(SceneObject* o){return o?std::to_string(o->getObjectID()):"0";}
 static bool volume(SceneObject* o){return o && (o->getContainerType()==ContainerType::VOLUME || o->getContainerType()==ContainerType::GENERIC) && o->getContainerVolumeLimit()>0 && !o->isCraftingTool() && !o->isCraftingStation() && !o->isFactoryCrate() && !o->isResourceContainer() && !o->isCreatureObject() && !o->isBuildingObject() && !o->isCellObject() && !o->isInstallationObject() && !o->isTerminal();}
 static void permission(CreatureObject* c,SceneObject* o){
  auto box=dynamic_cast<Container*>(o);if(box && box->isContainerLocked())throw std::runtime_error("Container is locked");
  if(!o->checkContainerPermission(c,ContainerPermissions::OPEN))throw std::runtime_error("Container access denied");
 }
public:
 static SceneObject* root(SceneObject* o){
  if(o && o->isDroidObject()){
   auto d=static_cast<DroidObject*>(o);if(!d->getModule("item_storage_module"))return nullptr;
   return d->getSlottedObject("inventory");
  }
  auto p=o?o->getParent().get():nullptr;
  return volume(o) && (!p || p->isCellObject())?o:nullptr;
 }
 static bool supports(SceneObject* o){return root(o)!=nullptr;}
 static SceneObject* selected(CreatureObject* c,SceneObject* anchor,const Json& r){
  auto storage=root(anchor);if(!storage || anchor->getZone()!=c->getZone() || anchor->getParentID()!=c->getParentID() || !c->isInRange(anchor,3) || !CollisionManager::checkLineOfSight(c,anchor) || c->isDead() || c->isIncapacitated())throw std::runtime_error("Container is out of reach");
  if(anchor->isDroidObject()){
   auto d=static_cast<DroidObject*>(anchor);if(d->isDead() || d->isIncapacitated() || d->getLinkedCreature().get()!=c)throw std::runtime_error("Called owned storage droid required");
  }
  permission(c,storage);
  auto key=r.value("container_id",id(storage));auto o=c->getZoneServer()->getObject(std::stoull(key));
  if(!o || !volume(o) || (o!=storage && !o->isASubChildOf(storage)))throw std::runtime_error("Container is outside selected storage");
  ManagedReference<SceneObject*> current=o;bool reached=false;
  for(int depth=0;current && depth<=8;++depth){permission(c,current);if(current==storage){reached=true;break;}current=current->getParent().get();}
  if(!reached)throw std::runtime_error("Container depth exceeds limit");return o;
 }
 static void open(CreatureObject* c,SceneObject* anchor,const Json& r){
  auto o=selected(c,anchor,r);auto cmd=c->getZoneServer()->getObjectController()->getQueueCommand("opencontainer");
  if(!cmd || cmd->doQueueCommand(c,o->getObjectID(),UnicodeString())!=QueueCommand::SUCCESS)throw std::runtime_error("Native container could not be opened");
 }
 static Json snapshot(CreatureObject* c,SceneObject* anchor,const Json& r){
  auto o=selected(c,anchor,r);Locker lock(o,c);permission(c,o);
  if(o->getContainerObjectsSize()>256)throw std::runtime_error("Container snapshot exceeds item limit");
  Json items=Json::array(),ids=Json::array();
  for(int i=0;i<o->getContainerObjectsSize();++i){auto child=o->getContainerObject(i);if(!child)continue;
   auto row=SwgxrInventory::describe(child,c);row["external_container_id"]=id(o);row["external_anchor_id"]=id(anchor);row["split_supported"]=false;row["split_available"]=false;row["equipped"]=false;row["consume_available"]=false;
   items.push_back(row);ids.push_back(id(child));child->sendAttributeListTo(c);
  }
  Json bag={{"id",id(o)},{"parent_id",o==root(anchor)?id(o):id(o->getParent().get())},{"capacity",o->getContainerVolumeLimit()},{"occupied",o->getCountableObjectsRecursive()},{"direct_count",ids.size()},{"depth",0},{"item_ids",ids}};
  return {{"source_kind","core3_inventory"},{"character_id",id(c)},{"external",true},{"anchor_id",id(anchor)},{"root_id",id(root(anchor))},{"inventory",bag},{"containers",Json::array({bag})},{"items",items},{"equipment",Json::array()},{"equipped_backpack",nullptr}};
 }
 static void transfer(CreatureObject* c,SceneObject* anchor,const Json& r){
  auto container=selected(c,anchor,r);auto item=c->getZoneServer()->getObject(std::stoull(r.at("item_id").get<std::string>()));
  if(!item)throw std::runtime_error("Item no longer exists");Locker itemLock(item,c);
  SceneObject* destination=nullptr;
  if(r.at("direction")=="take"){
   if(item->getParent().get()!=container)throw std::runtime_error("Container item has moved");
   auto bag=c->getZoneServer()->getObject(std::stoull(r.at("destination_id").get<std::string>()));
   if(!volume(bag) || (bag!=c->getInventory() && !SwgxrEquipment::inInventory(bag,c) && !(bag->isWearableContainerObject() && bag->getParent().get()==c)))throw std::runtime_error("Owned backpack or inventory destination required");
   destination=bag;
  }else if(r.at("direction")=="store"){
   if(!SwgxrEquipment::inInventory(item,c))throw std::runtime_error("Owned inventory item required");destination=container;
  }else throw std::runtime_error("Invalid container transfer direction");
  auto cmd=c->getZoneServer()->getObjectController()->getQueueCommand("transferitemmisc");auto args=id(destination)+" -1 0 0 0";
  if(!cmd || cmd->doQueueCommand(c,item->getObjectID(),UnicodeString(String(args.c_str())))!=QueueCommand::SUCCESS || item->getParent().get()!=destination)throw std::runtime_error("Native container transfer rejected: permission, item type or capacity");
  item->updateToDatabaseAllObjects(false);
 }
};
#endif
