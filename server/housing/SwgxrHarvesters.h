#ifndef SWGXR_HARVESTERS_H
#define SWGXR_HARVESTERS_H
#include "SwgxrInventory.h"
#include <climits>
#include "server/zone/managers/structure/StructureManager.h"
#include "server/zone/managers/crafting/CraftingManager.h"
#include "server/zone/Zone.h"
#include "server/zone/objects/installation/InstallationObject.h"
#include "server/zone/objects/installation/harvester/HarvesterObject.h"
#include "server/zone/objects/tangible/deed/structure/StructureDeed.h"
#include "server/zone/objects/player/sessions/DestroyStructureSession.h"
#include "server/zone/managers/resource/ResourceManager.h"
#include "server/zone/managers/resource/resourcespawner/ResourceSpawner.h"
#include "server/zone/objects/transaction/TransactionLog.h"
class SwgxrHarvesters {
 using Json=JSONSerializationType;
 static std::string id(SceneObject* o){return o?std::to_string(o->getObjectID()):"0";}
 static std::string text(const String& s){return s.toCharArray();}
public:
 static bool supports(SceneObject* o){return o && (o->isHarvesterObject() || o->isGeneratorObject());}
 static bool deed(SceneObject* o){auto d=dynamic_cast<StructureDeed*>(o);return d && text(d->getGeneratedObjectTemplate()).find("object/installation/")==0 && (text(d->getGeneratedObjectTemplate()).find("object/installation/mining_")==0 || text(d->getGeneratedObjectTemplate()).find("object/installation/generators/")==0);}
 static void deeds(CreatureObject* c,SceneObject* parent,Json& out,int depth=0){if(!parent || depth>8)return;for(int i=0;i<parent->getContainerObjectsSize() && out.size()<128;++i){auto o=parent->getContainerObject(i);if(deed(o))out.push_back(SwgxrInventory::describe(o,c));if(o->getContainerVolumeLimit()>0 && !o->isFactoryCrate())deeds(c,o,out,depth+1);}}
 static ManagedReference<InstallationObject*> nearby(CreatureObject* c,const Json& r){auto o=c->getZoneServer()->getObject(std::stoull(r.at("structure_id").get<std::string>()));if(!supports(o) || o->getZone()!=c->getZone() || c->getParentID()!=0 || !c->isInRange(o,20))throw std::runtime_error("Harvester out of reach");auto h=o.castTo<InstallationObject*>();if(!h->isOnAdminList(c))throw std::runtime_error("Harvester administrator permission required");return h;}
 static Json resources(InstallationObject* h){Json rows=Json::array();Vector<ManagedReference<ResourceSpawn*>> list;h->getZoneServer()->getResourceManager()->getResourceListByType(list,h->getInstallationType(),h->getZone()->getZoneName());for(int i=0;i<list.size();++i){auto s=list.get(i);float density=s->getDensityAt(h->getZone()->getZoneName(),h->getPositionX(),h->getPositionY());if(density>0 && s->inShift())rows.push_back({{"id",id(s)},{"name",text(s->getName())},{"type",text(s->getType())},{"density",density}});}return rows;}
 static Json view(CreatureObject* c,InstallationObject* h){
  h->updateInstallationWork();Json out={{"id",id(h)},{"active",h->isActive()},{"selected_resource",std::to_string(h->getActiveResourceSpawnID())},{"power",h->getSurplusPower()},{"power_rate",h->getBasePowerRate()},{"maintenance",h->getSurplusMaintenance()},{"maintenance_rate",h->getMaintenanceRate()},{"cash",c->getCashCredits()},{"hopper_size",h->getHopperSize()},{"hopper_capacity",h->getHopperSizeMax()},{"rate",h->getActualRate()},{"resources",resources(h)},{"output",Json::array()},{"owner",h->isOwnerOf(c)},{"redeed_cost",h->getRedeedCost()},{"redeedable",h->isRedeedable()}};
  auto hopper=h->getHopperList();for(int i=0;i<hopper->size();++i){auto container=hopper->get(i);if(container->getQuantity()<=0)continue;auto row=SwgxrInventory::describe(container,c);row["resource_id"]=id(container->getSpawnObject());row["name"]=text(container->getSpawnObject()->getName());row["quantity"]=container->getQuantity();out["output"].push_back(row);}return out;
 }
 static Json execute(CreatureObject* c,const Json& r){
  auto h=nearby(c,r);Locker lock(h,c);if(h->getDeedObjectID()==0)throw std::runtime_error("Harvester recovery already pending");h->updateInstallationWork();auto action=r.at("action").get<std::string>();Json result=Json::object();
  if(action=="house_harvester_select"){
   auto spawn=r.at("resource_id").get<std::string>();bool eligible=false;for(auto& row:resources(h))if(row["id"]==spawn)eligible=true;if(!eligible)throw std::runtime_error("Resource depleted or unavailable to this harvester");
   h->changeActiveResourceID(std::stoull(spawn));if(h->getActiveResourceSpawnID()!=std::stoull(spawn))throw std::runtime_error("Native resource selection rejected");h->setActive(true);
  }else if(action=="house_harvester_active"){h->setActive(r.at("active").get<bool>());
  }else if(action=="house_harvester_power"){
   auto container=c->getZoneServer()->getObject(std::stoull(r.at("item_id").get<std::string>())).castTo<ResourceContainer*>();if(!container || !SwgxrEquipment::inInventory(container,c))throw std::runtime_error("Owned energy resource required");Locker resourceLock(container,c);auto spawn=container->getSpawnObject();if(!spawn || !spawn->isEnergy() || container->getQuantity()<=0 || h->getBasePowerRate()==0)throw std::runtime_error("This resource or installation cannot accept power");
   // Same potential-energy conversion as ResourceManager; only the dragged stack is consumed.
   int64 energy=int64(std::max(1.0f,spawn->getValueOf(CraftingManager::PE)/500.0f)*container->getQuantity());if(energy<=0 || energy>INT_MAX-h->getSurplusPower())throw std::runtime_error("Power reserve limit");h->addPower(energy);container->destroyObjectFromWorld(true);container->destroyObjectFromDatabase(true);result["power_deposited"]=energy;
  }else if(action=="house_harvester_deposit"){
   int amount=r.at("amount").get<int>();if(amount<=0 || amount>c->getCashCredits() || amount>100000000-h->getSurplusMaintenance())throw std::runtime_error("Invalid maintenance deposit");auto before=c->getCashCredits();StructureManager::instance()->payMaintenance(h,c,amount);if(before-c->getCashCredits()!=amount)throw std::runtime_error("Maintenance deposit rejected");
  }else if(action=="house_harvester_collect"){
   auto spawn=c->getZoneServer()->getObject(std::stoull(r.at("resource_id").get<std::string>())).castTo<ResourceSpawn*>();ManagedReference<ResourceContainer*> container=nullptr;if(spawn)container=h->getContainerFromHopper(spawn);int quantity=r.at("quantity").get<int>();if(!container || quantity<=0 || quantity>container->getQuantity() || quantity>ResourceContainer::MAXSIZE || c->getInventory()->isContainerFullRecursive())throw std::runtime_error("Output unavailable or inventory full");
   Locker spawnLock(spawn);TransactionLog trx(h,c,TrxCode::MINED);if(!c->getZoneServer()->getResourceManager()->getResourceSpawner()->addResourceToPlayerInventory(trx,c,spawn,quantity))throw std::runtime_error("Native hopper transfer rejected");h->updateResourceContainerQuantity(container,container->getQuantity()-quantity,true);
  }else if(action=="house_harvester_recover"){
   if(!h->isOwnerOf(c) || !h->isRedeedable() || h->getHopperSize()>0 || h->getDeedObjectID()==0 || c->containsActiveSession(SessionFacadeType::DESTROYSTRUCTURE))throw std::runtime_error("Owner, empty hopper and native redeeding requirements required");
   auto original=c->getZoneServer()->getObject(h->getDeedObjectID()).castTo<StructureDeed*>();if(!original)throw std::runtime_error("Original deed unavailable; recovery refused");
   for(auto field:{"left_hand","right_hand"}){auto p=r.at(field);Vector3 hand(p[0].get<float>(),p[2].get<float>(),p[1].get<float>());if(hand.distanceTo(c->getWorldPosition())>3.5 || hand.distanceTo(h->getWorldPosition())>std::max(2.f,h->getTemplateRadius()+.25f))throw std::runtime_error("Both hands must touch the harvester");}
   auto harvester=dynamic_cast<HarvesterObject*>(h.get());int slots=harvester && harvester->isSelfPowered()?2:1;auto inventory=c->getInventory();if(!inventory || inventory->getCountableObjectsRecursive()>inventory->getContainerVolumeLimit()-slots)throw std::runtime_error("Inventory space required to recover original deed");
   h->setActive(false);Reference<DestroyStructureSession*> session=new DestroyStructureSession(c,h);c->addActiveSession(SessionFacadeType::DESTROYSTRUCTURE,session);StructureManager::instance()->redeedStructure(c);if(h->getDeedObjectID()!=0 || !SwgxrEquipment::inInventory(original,c))throw std::runtime_error("Native recovery rejected: check inventory space");original->updateToDatabaseAllObjects(false);result["recovered_deed_id"]=id(original);return result;
  }else if(action!="house_harvester_status")throw std::runtime_error("Unknown harvester operation");
  h->updateToDatabaseAllObjects(false);result["harvester"]=view(c,h);return result;
 }
};
#endif
