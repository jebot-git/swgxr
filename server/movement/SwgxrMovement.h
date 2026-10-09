#ifndef SWGXR_MOVEMENT_H
#define SWGXR_MOVEMENT_H
#include "SwgxrPlanets.h"
#include "SwgxrSquadLeader.h"
#include "server/zone/objects/player/PlayerObject.h"
#include "MovementBudget.h"
#include <chrono>
#include <map>
#include <mutex>
#include "server/zone/packets/object/transform/Transform.h"
#include "server/zone/managers/player/PlayerManager.h"
#include "server/zone/managers/planet/PlanetManager.h"
#include "server/zone/managers/collision/CollisionManager.h"
#include "server/zone/managers/collision/IntersectionResults.h"
#include "server/zone/objects/cell/CellObject.h"
#include "server/zone/objects/building/BuildingObject.h"
#include "terrain/manager/TerrainManager.h"
// JSON presentation of the original DataTransform/DataTransformWithParent
// movement policy. Only genuine transport operations may use teleport().
class SwgxrMovement {
 using Json=JSONSerializationType;
 struct RequestRevision {uint64 owner=0,value=0;bool present=false;};
 static RequestRevision& requestRevision(){static thread_local RequestRevision value;return value;}
 struct Record {swgxr::movement::Budget budget;uint64 zone=0;};
 static double monotonic(){return std::chrono::duration<double>(std::chrono::steady_clock::now().time_since_epoch()).count();}
 static std::map<uint64,Record>& records(){static std::map<uint64,Record> value;return value;}
 static std::mutex& gate(){static std::mutex value;return value;}
 static double maxSpeed(CreatureObject* c){return std::max(0.0,double(c->getRunSpeed()*c->getSpeedMultiplierMod()*SwgxrSquadLeader::movementScale(c)));}
 static Record read(CreatureObject* c){
  std::lock_guard<std::mutex> lock(gate());auto it=records().find(c->getObjectID());
  if(it!=records().end())return it->second;
  Record row;auto world=c->getWorldPosition();row.zone=c->getZone()?c->getZone()->getObjectID():0;
  row.budget.rebase(monotonic(),world.getX(),world.getY(),c->getParentID(),maxSpeed(c));return row;
 }
 static void store(CreatureObject* c,const Record& row){
  std::lock_guard<std::mutex> lock(gate());records()[c->getObjectID()]=row;
 }
 static void place(CreatureObject* c,const Vector3& p,SceneObject* parent){
  c->setPosition(p.getX(),p.getZ(),p.getY());
  if(parent)c->updateZoneWithParent(parent,false,true);else c->updateZone(false,true);
 }
public:
 class RequestScope {
  RequestRevision previous;
 public:
  RequestScope(CreatureObject* c,const Json& request):previous(requestRevision()){
   RequestRevision next;next.owner=c->getObjectID();
   if(request.contains("movement_revision")){
    auto value=request.at("movement_revision");
    if(!value.is_number_integer() || value.get<int64>()<0)throw std::runtime_error("native_movement_revision_invalid");
    next.present=true;next.value=value.get<uint64>();
   }
   requestRevision()=next;
  }
  ~RequestScope(){requestRevision()=previous;}
 };
 // Control affects intentional movement only. Tracking-driven room movement
 // still follows the established spatial movement budget, never a head snap.
 static Json controls(CreatureObject* c){
  int slow=0;for(auto mod:{"private_swgxr_snare","private_swgxr_hamstring","private_pikeman_pin","private_pikeman_drive","private_carbineer_crippling","private_carbineer_sweep","private_commando_cryo"})slow=std::max(slow,c->getSkillMod(mod));
  if(c->hasState(CreatureState::IMMOBILIZED))slow=std::max(slow,50);slow=std::max(0,std::min(100,slow));bool root=c->hasState(CreatureState::FROZEN) || c->getSkillMod("private_commando_glop")>0;
  return {{"slow_percent",slow},{"rooted",root},{"voluntary_scale",root?0.:1.-slow/100.}};
 }
 static Json snapshot(CreatureObject* c){return {
  {"controls",controls(c)},{"movement_revision",read(c).budget.revision},{"run_speed",c->getRunSpeed()},{"walk_speed",c->getWalkSpeed()},
  {"run_acceleration",c->getRunAcceleration()},{"walk_acceleration",c->getWalkAcceleration()},
  {"speed_multiplier_base",c->getSpeedMultiplierBase()},{"speed_multiplier_mod",c->getSpeedMultiplierMod()*SwgxrSquadLeader::movementScale(c)},
  {"acceleration_multiplier_base",c->getAccelerationMultiplierBase()},{"acceleration_multiplier_mod",c->getAccelerationMultiplierMod()*SwgxrSquadLeader::movementScale(c)},
  {"slope_mod_angle_radians",c->getSlopeModAngle()},{"slope_mod_percent",c->getSlopeModPercent()},
  {"water_mod_percent",c->getWaterModPercent()},{"swim_height",c->getSwimHeight()},
  {"turn_scale",c->getTurnScale()},{"current_speed",c->getCurrentSpeed()},
  {"server_max_speed",c->getRunSpeed()*c->getSpeedMultiplierMod()*SwgxrSquadLeader::movementScale(c)},
  {"movement_allowed",c->isMovementAllowed()},{"frozen",c->isFrozen()},{"swimming",c->isSwimming()}};}
 static void begin(CreatureObject* c){
  if(!c || !c->isPlayerCreature() || !c->getPlayerObject() || !c->getZone())return;
  auto row=read(c);auto world=c->getWorldPosition();row.zone=c->getZone()->getObjectID();
  row.budget.rebase(monotonic(),world.getX(),world.getY(),c->getParentID(),maxSpeed(c));store(c,row);
  c->getPlayerObject()->updateLastValidatedPosition();c->setCurrentSpeed(0);c->updateLocomotion();
 }
 static void end(CreatureObject* c){std::lock_guard<std::mutex> lock(gate());records().erase(c->getObjectID());}
 static void move(CreatureObject* c,const Json& r){
  try{moveChecked(c,r);}catch(const std::exception& e){
   std::string code=e.what();if(code.rfind("native_movement_",0)==0)throw;
   if(code.rfind("native_",0)==0)code=code.substr(7);
   throw std::runtime_error("native_movement_"+code);
  }
 }
private:
 static void moveChecked(CreatureObject* c,const Json& r){
  SwgxrPlanets::require(c,r);if(!r.contains("position"))return;
  auto ghost=c->getPlayerObject();auto zone=c->getZone();auto manager=c->getZoneServer()->getPlayerManager();
  if(!ghost || !zone || !manager)throw std::runtime_error("native_movement_context_missing");
  auto p=r.at("position");if(!p.is_array() || p.size()!=3)throw std::runtime_error("invalid_position");
  for(int i=0;i<3;++i)if(!p[i].is_number() || !std::isfinite(p[i].get<double>()) || std::abs(p[i].get<double>())>8192)throw std::runtime_error("invalid_position");
  auto budget=read(c);
  if(requestRevision().owner==c->getObjectID() && requestRevision().present && requestRevision().value!=budget.budget.revision)throw std::runtime_error("native_movement_stale_revision");
  if(r.contains("movement_revision") && (!r["movement_revision"].is_number_unsigned() && !r["movement_revision"].is_number_integer()))throw std::runtime_error("native_movement_revision_invalid");
  if(r.contains("movement_revision") && r["movement_revision"].get<uint64>()!=budget.budget.revision)throw std::runtime_error("native_movement_stale_revision");
  auto oldParent=c->getParent().get();ManagedReference<SceneObject*> parent=oldParent,root=c->getRootParent();
  if(r.contains("building_id")){
   auto text=r.at("building_id").get<std::string>();if(text.empty() || text.size()>20 || text.find_first_not_of("0123456789")!=std::string::npos)throw std::runtime_error("invalid_source_cell");
   uint64 bid=std::stoull(text);int index=r.value("cell_index",0);
   if(!bid && !index){parent=nullptr;root=nullptr;}else{
    root=c->getZoneServer()->getObject(bid);if(root==nullptr || !root->isBuildingObject() || root->getZone()!=zone || index<=0)throw std::runtime_error("invalid_source_cell");
    parent=static_cast<BuildingObject*>(root.get())->getCell(index);if(parent==nullptr)throw std::runtime_error("invalid_source_cell");
   }
  }
  if(parent!=nullptr && (!parent->isCellObject() || root==nullptr || !root->isBuildingObject()))throw std::runtime_error("unsupported_movement_parent");
  double x=p[0].get<double>(),z=p[1].get<double>(),y=p[2].get<double>();
  double heading=r.value("heading_radians",double(c->getDirection()->getRadians()+(oldParent!=nullptr && c->getRootParent()!=nullptr?c->getRootParent()->getDirection()->getRadians():0)));
  if(!std::isfinite(heading))throw std::runtime_error("invalid_heading");
  if(parent!=nullptr){double a=root->getDirection()->getRadians(),dx=x-root->getPositionX(),dy=y-root->getPositionY();x=dx*std::cos(a)-dy*std::sin(a);y=dx*std::sin(a)+dy*std::cos(a);z-=root->getPositionZ();heading-=a;if(std::abs(x)>1024 || std::abs(y)>1024 || std::abs(z)>1024)throw std::runtime_error("cell_position_out_of_bounds");}
  const auto previous=c->getPosition();Vector3 next(x,y,z);
  // Client tile support and the native continuous height may differ; vertical
  // support adjustment alone is not physical locomotion.
  bool changed=parent!=oldParent || previous.squaredDistanceTo2d(next)>0.000001f;
  if(changed){
   Transform policy;if(!policy.isPostureValid(c->getPosture()) || c->hasBuff(STRING_HASHCODE("private_feign_buff")))throw std::runtime_error("native_player_immobilized");
   if(!c->isMovementAllowed())throw std::runtime_error("native_animation_movement_locked");
   if(!ghost->isPrivileged()){
    if(c->isFrozen())throw std::runtime_error("native_player_frozen");
    auto inv=c->getInventory();if(!inv || inv->getCountableObjectsRecursive()>inv->getContainerVolumeLimit()+1)throw std::runtime_error("native_inventory_overloaded");
   }
  }
  if(parent!=nullptr){
   auto cell=static_cast<CellObject*>(parent.get());
   if(parent!=oldParent){
    if(c->isRidingMount())throw std::runtime_error("native_dismount_before_entry");
    if(!ghost->isPrivileged() && !static_cast<BuildingObject*>(root.get())->isAllowedEntry(c))throw std::runtime_error("house_entry_denied");
    const auto layout=root->getObjectTemplate()->getPortalLayout();
    if(oldParent!=nullptr && oldParent->isCellObject()){
     if(oldParent->getParentID()!=root->getObjectID() || !layout)throw std::runtime_error("unconnected_source_cell");
     auto property=layout->getCellProperty(static_cast<CellObject*>(oldParent.get())->getCellNumber());
     if(!property || !property->hasConnectedCell(cell->getCellNumber()))throw std::runtime_error("unconnected_source_cell");
     UniqueReference<Vector<float>*> floors(CollisionManager::getCellFloorCollision(x,y,cell));float error=16384;
     if(floors)for(int i=0;i<floors->size();++i)error=std::min(error,std::abs(floors->get(i)-float(z)));
     if(error>0.25f)throw std::runtime_error("native_cell_floor_mismatch");
    }else if(!c->isInRange(root,root->getOutOfRangeDistance()) && (!c->getCloseObjects() || !c->getCloseObjects()->contains(root.get())))throw std::runtime_error("native_building_out_of_range");
   }
   auto permissions=parent->getContainerPermissions();if(!permissions || (!permissions->hasInheritPermissionsFromParent() && !parent->checkContainerPermission(c,ContainerPermissions::WALKIN)))throw std::runtime_error("native_cell_walkin_denied");
  }
  IntersectionResults intersections;float floorZ=z;
  if(parent==nullptr){
   auto pm=zone->getPlanetManager();auto terrain=pm?pm->getTerrainManager():nullptr;if(!terrain)throw std::runtime_error("native_terrain_missing");
   if(x<=terrain->getMin() || x>=terrain->getMax() || y<=terrain->getMin() || y>=terrain->getMax())throw std::runtime_error("native_terrain_out_of_bounds");
   CollisionManager::getWorldFloorCollisions(x,y,zone,&intersections,c->getCloseObjects());
   floorZ=pm->findClosestWorldFloor(x,y,z,c->getSwimHeight(),&intersections,c->getCloseObjects());
  }
  const double clock=monotonic();const double since=std::max(0.001,clock-budget.budget.stamp);
  budget.budget.accrue(clock,maxSpeed(c));
  // Budget coordinates are world horizontal, including connected cell changes.
  // Do not compare two unrelated parent-local coordinate frames.
  auto proposed=budget;
  if(budget.zone!=zone->getObjectID() || !proposed.budget.accept(p[0].get<double>(),p[2].get<double>(),parent?parent->getObjectID():0)){
   store(c,budget);throw std::runtime_error("native_movement_speed_rejected");
  }
  auto validated=ghost->getLastValidatedPosition();uint32 stamp=ghost->getClientLastMovementStamp();
  // No client wall clock is trusted. Core3 validates against its own elapsed
  // server time and allows the same recent-speed-change grace period.
  int valid=manager->checkSpeedHackTests(c,ghost,validated,next,stamp,floorZ,parent);
  if(valid==Transform::INVALID_POSITION){
   // Accepted pose and budget remain authoritative. A rejection does not rewind
   // them, reset the native timer or grant a new unchecked interval.
   store(c,budget);throw std::runtime_error("native_movement_speed_rejected");
  }
  float speed=std::hypot(p[0].get<double>()-budget.budget.x,p[2].get<double>()-budget.budget.y)/since;
  if(!changed)speed=0;
  c->setDirection(float(std::fmod(std::fmod(heading,6.283185307179586)+6.283185307179586,6.283185307179586)));
  next.setZ(floorZ);c->setCurrentSpeed(speed);place(c,next,parent);c->updateLocomotion();store(c,proposed);
  if(parent==nullptr)manager->updateSwimmingState(c,floorZ,&intersections,c->getCloseObjects());else c->notifySelfPositionUpdate();
  if(valid==Transform::FULL_VALIDATED){validated->setPosition(x,floorZ,y);validated->setParent(parent?parent->getObjectID():0);ghost->updateServerLastMovementStamp();}
 }
};
#endif
