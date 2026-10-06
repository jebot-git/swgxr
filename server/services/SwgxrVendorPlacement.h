#ifndef SWGXR_VENDOR_PLACEMENT_H
#define SWGXR_VENDOR_PLACEMENT_H
#include "SwgxrInventory.h"
#include "server/zone/objects/building/BuildingObject.h"
#include "server/zone/objects/cell/CellObject.h"
#include "server/zone/managers/objectcontroller/ObjectController.h"
#include "server/zone/managers/collision/CollisionManager.h"
#include "server/zone/objects/tangible/components/vendor/VendorDataComponent.h"
#include "server/zone/objects/scene/variables/ContainerPermissions.h"
#include <memory>
// Datapad rows reference existing native inventory vendors. Preview is client-only.
class SwgxrVendorPlacement {
 using Json=JSONSerializationType;
 static std::string id(SceneObject* o){return o?std::to_string(o->getObjectID()):"0";}
 static VendorDataComponent* data(SceneObject* o){auto d=o?o->getDataObjectComponent():nullptr;return o && o->isVendor() && d && d->get() && d->get()->isVendorData()?cast<VendorDataComponent*>(d->get()):nullptr;}
 static bool eligible(CreatureObject* c){
  auto parent=c->getParent().get();auto root=c->getRootParent();
  if(parent==nullptr || !parent->isCellObject() || root==nullptr || !root->isBuildingObject() || c->isDead() || c->isIncapacitated() || c->isInCombat())return false;
  auto building=static_cast<BuildingObject*>(root);
  return building->isPublicStructure() && (building->isOnAdminList(c) || building->isOnPermissionList("VENDOR",c));
 }
 static Json describe(SceneObject* o,CreatureObject* c){auto row=SwgxrInventory::describe(o,c);auto p=o->getWorldPosition();auto parent=o->getParent().get();auto root=o->getRootParent();bool cell=parent!=nullptr && parent->isCellObject();auto vd=data(o);row["owner_id"]=vd?std::to_string(vd->getOwnerId()):"0";row["galactic_search"]=vd && vd->isVendorSearchEnabled();row["kind"]="vendor";row["position"]=Json::array({p.getX(),p.getZ(),p.getY()});row["building_id"]=cell?id(root):"0";row["cell_index"]=cell?static_cast<CellObject*>(parent.get())->getCellNumber():0;row["heading_radians"]=o->getDirection()->getRadians()+(cell && root?root->getDirection()->getRadians():0);return row;}
public:
 static void snapshot(CreatureObject* c,Json& out){
  out["vendors"]=Json::array();out["placed_vendors"]=Json::array();auto parent=c->getParent().get();auto root=c->getRootParent();bool cell=parent!=nullptr && parent->isCellObject();
  out["vendor_placement"]={{"eligible",eligible(c)},{"building_id",cell?id(root):"0"},{"cell_index",cell?static_cast<CellObject*>(parent.get())->getCellNumber():0},{"max_distance",4.0},{"reason",eligible(c)?"":"Enter a public building where you have administrator or vendor permission."}};
  auto ids=c->getPlayerObject()->getOwnedVendors();
  for(int i=0;i<ids->size() && out["vendors"].size()<64;++i){auto o=c->getZoneServer()->getObject(ids->elementAt(i));auto d=data(o);if(d && d->getOwnerId()==c->getObjectID() && (!d->isInitialized() || d->isSwgxrStored()) && c->getInventory()!=nullptr && o->isASubChildOf(c->getInventory()))out["vendors"].push_back(describe(o,c));}
  if(cell)for(int i=0;i<parent->getContainerObjectsSize() && out["placed_vendors"].size()<64;++i){auto o=parent->getContainerObject(i);auto d=data(o);if(d && d->isInitialized() && !d->isSwgxrStored())out["placed_vendors"].push_back(describe(o,c));}
 }
 static Json place(CreatureObject* c,const Json& r){
  if(!eligible(c))throw std::runtime_error("vendor_location_not_permitted");
  auto value=r.at("vendor_id").get<std::string>();if(value.empty() || value.size()>20 || value.find_first_not_of("0123456789")!=std::string::npos)throw std::runtime_error("invalid_vendor_id");
  auto vendor=c->getZoneServer()->getObject(std::stoull(value));if(vendor==nullptr)throw std::runtime_error("vendor_missing");Locker lock(vendor,c);auto d=data(vendor);auto inv=c->getInventory();
  if(!d || d->getOwnerId()!=c->getObjectID() || (d->isInitialized() && !d->isSwgxrStored()) || inv==nullptr || !vendor->isASubChildOf(inv))throw std::runtime_error("owned_unplaced_vendor_required");
  auto parent=c->getParent().get();auto root=c->getRootParent();auto cell=static_cast<CellObject*>(parent.get());
  if(r.value("building_id",std::string())!=id(root) || r.value("cell_index",0)!=cell->getCellNumber() || !cell->checkContainerPermission(c,ContainerPermissions::MOVEVENDOR))throw std::runtime_error("vendor_cell_changed");
  auto p=r.at("placement_position");double heading=r.at("placement_heading").get<double>();if(!p.is_array() || p.size()!=3 || !std::isfinite(heading))throw std::runtime_error("invalid_vendor_pose");
  for(int i=0;i<3;++i)if(!p[i].is_number() || !std::isfinite(p[i].get<double>()) || std::abs(p[i].get<double>())>(i==1?2048:8192))throw std::runtime_error("invalid_vendor_pose");
  auto player=c->getWorldPosition();double dx=p[0].get<double>()-player.getX(),dy=p[2].get<double>()-player.getY(),dz=p[1].get<double>()-player.getZ();if(dx*dx+dy*dy+dz*dz>16)throw std::runtime_error("vendor_too_far");
  double a=root->getDirection()->getRadians();dx=p[0].get<double>()-root->getPositionX();dy=p[2].get<double>()-root->getPositionY();double x=dx*std::cos(a)-dy*std::sin(a),y=dx*std::sin(a)+dy*std::cos(a),z=p[1].get<double>()-root->getPositionZ();
  std::unique_ptr<Vector<float>> floors(CollisionManager::getCellFloorCollision(x,y,cell));bool supported=false;float floorZ=0;if(floors)for(int i=0;i<floors->size();++i)if(std::abs(floors->get(i)-z)<=.25){floorZ=floors->get(i);supported=true;break;}if(!supported)throw std::runtime_error("vendor_requires_cell_floor");
  Vector3 end(x,y,floorZ);if(!CollisionManager::checkLineOfSightInParentCell(c,end))throw std::runtime_error("vendor_position_obstructed");
  String error;if(cell->canAddObject(vendor,-1,error)!=0)throw std::runtime_error("vendor_container_rejected");
  auto old=vendor->getPosition();float oldHeading=vendor->getDirection()->getRadians();vendor->initializePosition(x,floorZ,y);vendor->setDirection(float(heading-a));
  if(!c->getZoneServer()->getObjectController()->transferObject(vendor,cell,-1,true)){vendor->initializePosition(old.getX(),old.getZ(),old.getY());vendor->setDirection(oldHeading);throw std::runtime_error("vendor_transfer_failed");}
  // Same initialization and maintenance scheduling as the original radial 79.
  bool restored=d->isSwgxrStored(),search=d->swgxrRestoreSearch();d->setSwgxrStored(false);d->setInitialized(true);if(restored){if(d->isRegistered())vendor->getZone()->registerObjectWithPlanetaryMap(vendor);c->getZoneServer()->getAuctionManager()->getAuctionMap()->updateUID(vendor,d->getUID(),d->getUID());d->setVendorSearchEnabled(search && !d->isOnStrike());}else d->setEmpty();d->scheduleVendorCheckTask(VendorDataComponent::VENDORCHECKINTERVAL);vendor->updateToDatabaseAllObjects(false);
  return {{"vendor_id",value},{"placed",true}};
 }
};
#endif
