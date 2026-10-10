#pragma once
#include "JtlPolicy.h"
#include "server/zone/managers/spacecombat/SpaceCombatManager.h"
#include "server/zone/managers/spacecombat/projectile/ShipProjectile.h"
#include "server/zone/objects/ship/transform/ShipObjectTransform.h"
#include "SwgxrSpaceEvents.h"
#include "SwgxrSpaceJournal.h"
#include "SwgxrHyperspace.h"
#include "SwgxrStationComms.h"
#include "SwgxrPublicAppearance.h"
#include "SwgxrJtlLifecycle.h"
#include "server/zone/managers/planet/PlanetTravelPoint.h"
#include "server/zone/objects/ship/events/InsertGroupMemberIntoShipTask.h"
#include <mutex>
#include "conf/ConfigManager.h"
#include "server/login/account/Account.h"
#include "server/db/ServerDatabase.h"
#include "server/zone/managers/object/ObjectManager.h"
#include "server/zone/managers/ship/ShipManager.h"
#include "server/zone/objects/ship/PobShipObject.h"
#include "server/zone/objects/ship/ComponentSlots.h"
#include "server/zone/objects/intangible/ShipControlDevice.h"
#include "server/zone/objects/ship/events/InsertPilotIntoShipTask.h"
#include "server/zone/objects/intangible/tasks/StoreShipTask.h"
#include <set>
#include "QueueCommand.h"
#include "SwgxrEquipment.h"
#include "SwgxrPlanets.h"
#include "SwgxrMovement.h"
#include "SwgxrHousing.h"
#include <chrono>
#include <map>
#include "system/thread/Mutex.h"
// Bounded noncombat JtL testing, backed by the real Core3 ship, cells, inventory,
// account object and native commands. No alternative character/ship JSON store.
class SwgxrJtl {
 using Json=JSONSerializationType;
 struct Walk {double stamp=0,credit=1.5;uint64 sequence=0;};
 struct Motion {swgxr::jtl::State state;swgxr::jtl::Input input;double received=0,generation=0;bool ticking=false,primaryFire=false;std::map<int,double> nextShot;std::map<uint64,Walk> walkers;std::string power="balanced";};
 static std::map<uint64,Motion>& motions(){static std::map<uint64,Motion> value;return value;}
 static Mutex& motionMutex(){static Mutex value;return value;}
 static void eraseMotion(ShipObject* s){Locker guard(&motionMutex(),s);motions().erase(s->getObjectID());}
 static void eraseWalker(ShipObject* s,CreatureObject* c){Locker guard(&motionMutex(),s);auto it=motions().find(s->getObjectID());if(it!=motions().end())it->second.walkers.erase(c->getObjectID());}
 static double now(){return std::chrono::duration<double>(std::chrono::steady_clock::now().time_since_epoch()).count();}
 static std::string id(SceneObject* o){return o?std::to_string(o->getObjectID()):"0";}
 static Json point(SceneObject* o){return Json::array({o->getPositionX(),o->getPositionZ(),o->getPositionY()});}
 static Json quat(SceneObject* o){auto q=o->getDirection();return Json::array({q->getX(),q->getY(),q->getZ(),q->getW()});}
 static std::string zone(CreatureObject* c){return c && c->getZone()?c->getZone()->getZoneName().toCharArray():"";}
 static uint64 oid(const Json& r,const char* key){auto s=r.at(key).get<std::string>();if(s.empty() || s.size()>20 || s.find_first_not_of("0123456789")!=std::string::npos)throw std::runtime_error("jtl_invalid_object");auto v=std::stoull(s);if(!v)throw std::runtime_error("jtl_invalid_object");return v;}
 static swgxr::jtl::Vec vec(const Json& p){if(!p.is_array() || p.size()!=3)throw std::runtime_error("jtl_invalid_position");swgxr::jtl::Vec v{};for(int i=0;i<3;++i){if(!p[i].is_number() || !std::isfinite(p[i].get<double>()) || std::abs(p[i].get<double>())>64)throw std::runtime_error("jtl_invalid_position");v[i]=p[i].get<double>();}return v;}
 static Json record(SceneObject* o){return {{"id",id(o)},{"template",std::string(o->getObjectTemplate()->getFullTemplateString().toCharArray())},{"position",point(o)},{"quaternion",quat(o)}};}
 static bool yacht(SceneObject* o){return o && o->isPobShip() && o->getObjectTemplate()->getFullTemplateString()=="object/ship/player/player_sorosuub_space_yacht.iff";}
 static ShipObject* entitled(CreatureObject* c){
  auto a=c->getPlayerObject()->getAccount();if(!a)return nullptr;Locker accountLock(a,c);if(a->getSwgxrYachtCharacter()!=c->getObjectID() || !a->getSwgxrYachtShip())return nullptr;
  auto o=c->getZoneServer()->getObject(a->getSwgxrYachtShip());return yacht(o) && o->asShipObject()->getOwnerID()==c->getObjectID()?o->asShipObject():nullptr;
 }
 static ShipObject* require(CreatureObject* c){if(!enabled())throw std::runtime_error("jtl_disabled");auto s=entitled(c);if(!s)throw std::runtime_error("jtl_first_character_yacht_required");return s;}
 static ShipControlDevice* device(CreatureObject* c,ShipObject* s){auto d=c->getZoneServer()->getObject(s->getControlDeviceID());if(!d || !d->isShipControlDevice() || !d->isASubChildOf(c))throw std::runtime_error("jtl_owned_control_device_required");return static_cast<ShipControlDevice*>(d.get());}
 static void persist(CreatureObject* c,ShipObject* s){s->updateToDatabaseAllObjects(false);c->updateToDatabaseAllObjects(false);}
 static CellObject* interior(CreatureObject* c,ShipObject* s){auto p=c->getParent().get();if(c->getRootParent()!=s || !p || !p->isCellObject())throw std::runtime_error("jtl_leave_station_first");return static_cast<CellObject*>(p.get());}
 static Motion& motion(ShipObject* ship){Locker guard(&motionMutex(),ship);auto found=motions().find(ship->getObjectID());if(found==motions().end()){Motion m;m.state.position={{ship->getPositionX(),ship->getPositionZ(),ship->getPositionY()}};auto q=ship->getDirection();m.state.orientation={{q->getX(),q->getY(),q->getZ(),q->getW()}};m.state.stamp=now();m.generation=m.state.stamp;found=motions().emplace(ship->getObjectID(),m).first;}return found->second;}
 static void applyMotion(ShipObject* s,Motion& m,double stamp){
  s->updateSpeedRotationValues(false);
  swgxr::jtl::Dynamics d;d.maxSpeed=s->getActualMaxSpeed();d.acceleration=s->getActualAccelerationRate();d.deceleration=s->getActualDecelerationRate();d.rates={{s->getActualPitchRate(),s->getActualYawRate(),s->getActualRollRate()}};d.angularAcceleration={{s->getActualPitchAccelerationRate(),s->getActualYawAccelerationRate(),s->getActualRollAccelerationRate()}};d.slideDampener=s->getSlip();
  m.state=swgxr::jtl::advance(m.state,m.input,m.received,stamp,d);
  auto& state=m.state;s->setCurrentSpeed(state.speed);s->setPosition(state.position[0],state.position[1],state.position[2]);Quaternion q(state.orientation[3],state.orientation[0],state.orientation[1],state.orientation[2]);s->setDirection(q);s->setRotationMatrix(q);s->updateZone(false,true);s->incrementMovementCounter();auto transform=s->getShipTransform();if(transform)transform->setCurrentTransform(s);
 }
 static void fireWeapons(ShipObject* s,Motion& m,double stamp){
  if(!m.primaryFire || stamp>=m.received+swgxr::jtl::CONTROL_LEASE_SECONDS || yacht(s) || s->isHyperspacing() || !s->getPilot())return;
  auto direction=SpaceMath::matrixToVelocity(*s->getConjugateMatrix());
  for(int slot=Components::WEAPON_START;slot<=Components::FIGHTERSLOTMAX;++slot){
   if(m.nextShot[slot]>stamp || !s->isComponentFunctional(slot))continue;
   auto data=ShipManager::instance()->getProjectileData(s->getShipComponentMap()->get(slot));
   // Primary fixed guns only. Mining is deferred; missiles need lock-on controls.
   if(!data || data->isMissile() || data->isCountermeasure() || data->isMiningLaser() || data->isTractorBeam() || data->consumesAmmo() || data->getSpeed()<=0 || data->getRange()<=0)continue;
   if(ShipManager::instance()->getShipTurretData(s->getShipChassisName(),slot-Components::WEAPON_START))continue;
   float energy=std::max(0.f,s->getEnergyPerShotMap()->get(slot))/swgxr::jtl::clamp(s->getComponentEnergyEfficiencyMap()->get(slot),.1,10);
   if(s->getCapacitorEnergy()<energy)continue;
   double refire=std::max(.05,double(s->getComponentRefireRate()->get(slot))/swgxr::jtl::clamp(s->getComponentRefireEfficiency()->get(slot),.1,10));
   auto projectile=new ShipProjectile(s,slot-Components::WEAPON_START,data->getIndex(),0,s->getPosition(),direction*7800.f,data->getSpeed(),data->getRange(),1.f,System::getMiliTime());projectile->readProjectileData(data);
   s->setCapacitorEnergy(s->getCapacitorEnergy()-energy,true);m.nextShot[slot]=stamp+refire;
   SpaceCombatManager::instance()->addProjectile(s,projectile,s->getPilot());
  }
 }
 static void flightTick(ManagedWeakReference<ShipObject*> weak,double generation){
  Core::getTaskManager()->scheduleTask([weak,generation]() mutable {
   auto s=weak.get();if(!s)return;Locker lock(s);
   Motion* m=nullptr;{Locker guard(&motionMutex(),s);auto it=motions().find(s->getObjectID());if(it==motions().end() || it->second.generation!=generation)return;m=&it->second;}
   if(!s->isShipLaunched() || !s->getPilot() || s->isHyperspacing()){swgxr::jtl::stop(m->state);s->setCurrentSpeed(0);m->ticking=false;return;}
   double stamp=now();applyMotion(s,*m,stamp);fireWeapons(s,*m,stamp);
   if(stamp>=m->received+swgxr::jtl::CONTROL_LEASE_SECONDS){m->ticking=false;return;}
   flightTick(weak,generation);
  },"SwgxrJtlFlight",50);
 }
 static void requirePilot(CreatureObject* c,ShipObject* s){if(!s || s->getOwnerID()!=c->getObjectID() || current(c)!=s || s->getPilot()!=c || !c->isPilotingShip())throw std::runtime_error("jtl_pilot_required");}
 static void terminalAction(CreatureObject* c,ShipObject* s,const Json& request){
  // This fixed terminal is part of the authored POB interior mesh: a ray to
  // its origin hits that same mesh. Gate its original radial interaction by
  // exact fixed-child identity, same room, short reach and native admin rights.
  auto terminal=c->getZoneServer()->getObject(oid(request,"terminal_id"));auto pob=s->asPobShip();
  if(!pob || !terminal || terminal->getObjectTemplate()->getFullTemplateString()!="object/tangible/terminal/terminal_pob_ship.iff" || !s->containsChildObject(terminal) || terminal->getRootParent()!=s || terminal->getParentID()!=c->getParentID() || !c->isInRange(terminal,4))throw std::runtime_error("jtl_pob_terminal_out_of_reach");
  if(!pob->isOnAdminList(c))throw std::runtime_error("jtl_ship_admin_required");
  if(request.at("action")=="terminal_recover"){
   auto item=c->getZoneServer()->getObject(oid(request,"item_id"));auto inventory=c->getInventory();
   if(!item || !inventory || !item->isTangibleObject() || item->isClientObject() || item->isCreatureObject() || item->isTerminal() || item->isVendor() || s->containsChildObject(item) || item->getRootParent()!=s)throw std::runtime_error("jtl_movable_furniture_required");
   Locker itemLock(item,c);auto parent=item->getParent().get();
   if(!parent || !parent->isCellObject() || !item->checkContainerPermission(c,ContainerPermissions::MOVECONTAINER) || !parent->checkContainerPermission(c,ContainerPermissions::MOVEOUT) || !inventory->checkContainerPermission(c,ContainerPermissions::MOVEIN))throw std::runtime_error("jtl_furniture_permission_rejected");
   String description;if(inventory->canAddObject(item,-1,description)!=0)throw std::runtime_error("jtl_inventory_full");
   if(!c->getZoneServer()->getObjectController()->transferObject(item,inventory,-1,true) || item->getParentID()!=inventory->getObjectID())throw std::runtime_error("jtl_native_recovery_rejected");
   item->updateToDatabaseAllObjects(false);persist(c,s);
  }
 }
 static void command(CreatureObject* c,ShipObject* s,const Json& request){
  const auto cmd=request.at("command_id").get<std::string>();
  if(cmd=="elevator_up" || cmd=="elevator_down"){
   auto cell=interior(c,s);if(passengerSeated(c))throw std::runtime_error("jtl_leave_station_first");auto terminal=c->getZoneServer()->getObject(oid(request,"interaction_id"));auto expected=cmd=="elevator_up"?"object/tangible/terminal/terminal_elevator_up.iff":"object/tangible/terminal/terminal_elevator_down.iff";
   if(!terminal || !s->containsChildObject(terminal) || terminal->getObjectTemplate()->getFullTemplateString()!=expected || terminal->getParentID()!=cell->getObjectID() || !c->isInRange(terminal,2) || !CollisionManager::checkLineOfSight(c,terminal))throw std::runtime_error("jtl_elevator_out_of_reach");auto before=c->getPosition();terminal->handleObjectMenuSelect(c,cmd=="elevator_up"?198:199);if(c->getPosition().distanceTo(before)<.1)throw std::runtime_error("jtl_elevator_no_floor_change");auto& m=motion(s).walkers[c->getObjectID()];m.stamp=now();m.credit=1.5;persist(c,s);return;
  }
  requirePilot(c,s);Locker lock(s,c);
  if(cmd=="shield_front" || cmd=="shield_rear" || cmd=="shield_balance"){
   if(!s->isComponentFunctional(Components::SHIELD0))throw std::runtime_error("jtl_shield_unavailable");
   auto banks=swgxr::jtl::shields(s->getFrontShield(),s->getRearShield(),s->getMaxFrontShield(),s->getMaxRearShield(),cmd=="shield_front"?1:cmd=="shield_rear"?0:.5);
   s->setFrontShield(banks[0]);s->setRearShield(banks[1]);
  }else if(cmd=="power_engines" || cmd=="power_balanced"){
   // Engine priority halves shield recharge and reallocates its efficiency.
   // The speed remains bounded by original engine stats, never a staff bonus.
   if(!s->isComponentFunctional(Components::ENGINE))throw std::runtime_error("jtl_engine_unavailable");
   bool engines=cmd=="power_engines";s->setEfficiency(Components::ENGINE,engines?1.15f:1.f);s->setEfficiency(Components::SHIELD0,engines?.5f:1.f);motion(s).power=engines?"engines":"balanced";s->updateSpeedRotationValues(true);
  }else{
   // The native command checks installed interface, assigned droid, learned
   // program and cooldown; the stock Yacht deliberately grants none of these.
   if(cmd.rfind("droidcommand_",0)!=0 || cmd.size()>64 || cmd.find_first_not_of("abcdefghijklmnopqrstuvwxyz0123456789_")!=std::string::npos || !s->hasDroidCommand(String(cmd.c_str()).hashCode()))throw std::runtime_error("jtl_droid_program_unavailable");
   auto q=c->getZoneServer()->getObjectController()->getQueueCommand("droid");if(!q || q->doQueueCommand(c,0,UnicodeString(String(cmd.c_str())))!=QueueCommand::SUCCESS)throw std::runtime_error("jtl_native_droid_rejected");
  }
  persist(c,s);
 }
 static bool walkClear(CreatureObject* c,ShipObject* s,const Vector3& destination){
  // Destination support is checked in its own cell. The old-cell LOS helper
  // also requires a floor under the destination in the OLD room, blocking doors.
  auto layout=s->getObjectTemplate()->getPortalLayout();if(!layout)return false;
  Vector3 start=c->getPosition(),end=destination;start.set(start.getX(),start.getY(),start.getZ()+.5f);end.set(end.getX(),end.getY(),end.getZ()+.5f);
  float distance=end.distanceTo(start);if(distance<.001f)return true;
  Vector3 direction=end-start;direction.normalize();Ray ray(start,direction);float hit=0;Triangle* triangle=nullptr;
  for(int i=1;i<layout->getAppearanceTemplatesSize();++i){auto appearance=layout->getAppearanceTemplate(i);if(appearance && appearance->intersects(ray,distance,hit,triangle,true))return false;}
  return true;
 }
 static void walk(CreatureObject* c,ShipObject* s,const Json& r){
  if(!s->isPobShip())throw std::runtime_error("jtl_no_walkable_interior");if(passengerSeated(c))throw std::runtime_error("jtl_leave_station_first");auto old=interior(c,s);auto p=vec(r.at("position"));int index=r.at("cell_index").get<int>();auto pob=s->asPobShip();if(index<=0 || index>pob->getTotalCellNumber())throw std::runtime_error("jtl_invalid_cell");auto cell=pob->getCell(index-1);if(!cell)throw std::runtime_error("jtl_invalid_cell");
  auto layout=s->getObjectTemplate()->getPortalLayout();if(cell!=old){auto prop=layout?layout->getCellProperty(old->getCellNumber()):nullptr;if(!prop || !prop->hasConnectedCell(index))throw std::runtime_error("jtl_unconnected_cell");}
  UniqueReference<Vector<float>*> floors(CollisionManager::getCellFloorCollision(p[0],p[2],cell));double error=1000;if(floors)for(int i=0;i<floors->size();++i)error=std::min(error,std::abs(double(floors->get(i))-p[1]));if(error>.3)throw std::runtime_error("jtl_floor_mismatch");
  Vector3 dest(p[0],p[2],p[1]);if(!walkClear(c,s,dest))throw std::runtime_error("jtl_walk_obstructed");
  auto& m=motion(s).walkers[c->getObjectID()];auto sequence=r.at("sequence").get<uint64>();if(!sequence || sequence<=m.sequence)throw std::runtime_error("jtl_stale_walk");m.sequence=sequence;double stamp=now(),credit=m.credit;swgxr::jtl::Vec from{{c->getPositionX(),c->getPositionZ(),c->getPositionY()}};bool accepted=swgxr::jtl::walkBudget(from,p,stamp-m.stamp,credit,c->getRunSpeed()*c->getSpeedMultiplierMod());m.stamp=stamp;m.credit=credit;if(!accepted)throw std::runtime_error("jtl_walk_speed_rejected");
  Locker cellLock(cell,c);if(cell!=old && !cell->transferObject(c,-1,true))throw std::runtime_error("jtl_cell_transfer_rejected");c->initializePosition(p[0],p[1],p[2]);c->updateZoneWithParent(cell,true);
 }
 static void furnish(CreatureObject* c,ShipObject* s,const Json& r,bool recover){
  auto cell=interior(c,s);Json request=r;if(!recover){if(r.at("cell_index").get<int>()!=cell->getCellNumber())throw std::runtime_error("jtl_current_cell_required");vec(r.at("placement_position"));}else{vec(r.at("left_hand"));vec(r.at("right_hand"));}
  SwgxrHousing::furnish(c,request,recover,true);persist(c,s);
 }
 static SceneObject* passenger(ShipObject* s){auto children=s->getChildObjects();for(int i=0;i<children->size();++i){auto o=children->get(i);if(o && o->getObjectTemplate()->getFullTemplateString()=="object/tangible/furniture/space/frn_chair_falcon_passenger_s01.iff")return o;}return nullptr;}
 static std::string passengerOccupant(ShipObject* s,CreatureObject* observer){auto ids=s->getPlayersOnBoard();for(int i=0;i<ids.size();++i){auto c=player(observer,std::to_string(ids.get(i)));if(c && current(c)==s && passengerSeated(c))return id(c);}return "0";}
 static bool passengerSeated(CreatureObject* c){return aboard(c) && c->getPlayerObject()->getScreenPlayData("swgxr_jtl","station")=="passenger";}
 static void store(CreatureObject* c,ShipObject* s,bool docking=false){
  if(!s->isShipLaunched())return;auto before=s->getPlayersOnBoard();auto d=device(c,s);auto returnZone=s->getSpaceLaunchZone();auto returnPosition=s->getSpaceLaunchLocation();if(!SwgxrPlanets::supported(returnZone))throw std::runtime_error("jtl_invalid_return_zone");c->getPlayerObject()->notifySceneReady();StoreShipTask task(c,d,returnZone,returnPosition);task.run();if(s->isShipLaunched())throw std::runtime_error("jtl_native_land_failed");s->clearOptionBit(OptionBitmask::INVULNERABLE,false);eraseMotion(s);c->getPlayerObject()->setScreenPlayData("swgxr_jtl","station","");c->clearState(CreatureState::SITTINGONCHAIR);c->setPosture(CreaturePosture::UPRIGHT);c->getPlayerObject()->notifySceneReady();if(SwgxrPlanets::supportedName(zone(c)))SwgxrMovement::begin(c);for(int i=0;i<before.size();++i){auto member=player(c,std::to_string(before.get(i)));if(!member)continue;Locker memberLock(member,c);if(SwgxrPlanets::supportedName(zone(member))){member->clearState(CreatureState::SITTINGONCHAIR);member->setPosture(CreaturePosture::UPRIGHT);member->getPlayerObject()->notifySceneReady();SwgxrMovement::begin(member);save(member,"aboard_ship",Json::object());if(!docking)save(member,"parked_ship",Json::object());member->updateToDatabaseAllObjects(false);}}persist(c,s);
 }

 struct Lease {std::string token;double touched=0;};
 static std::map<uint64,Lease>& leases(){static std::map<uint64,Lease> value;return value;}
 static std::mutex& leaseMutex(){static std::mutex value;return value;}
 static double epoch(){return std::chrono::duration<double>(std::chrono::system_clock::now().time_since_epoch()).count();}
 static std::string leaseToken(CreatureObject* c){std::lock_guard<std::mutex> lock(leaseMutex());auto it=leases().find(c->getObjectID());return it==leases().end()?"":it->second.token;}
 static bool connected(CreatureObject* c){if(!c || !c->getPlayerObject() || c->getPlayerObject()->isOffline())return false;std::lock_guard<std::mutex> lock(leaseMutex());auto it=leases().find(c->getObjectID());return it!=leases().end() && now()-it->second.touched<=60;}
 static Json data(CreatureObject* c,const char* key){auto raw=c->getPlayerObject()->getScreenPlayData("swgxr_jtl",key);return raw.isEmpty()?Json::object():Json::parse(raw.toCharArray());}
 static void save(CreatureObject* c,const char* key,const Json& value){c->getPlayerObject()->setScreenPlayData("swgxr_jtl",key,String(value.dump().c_str()));c->getPlayerObject()->updateToDatabase();}
 static CreatureObject* player(CreatureObject* c,const std::string& key){if(key.empty() || key.size()>20 || key.find_first_not_of("0123456789")!=std::string::npos)return nullptr;auto o=c->getZoneServer()->getObject(std::stoull(key));return o && o->isPlayerCreature()?o->asCreatureObject():nullptr;}
 static ShipObject* ship(CreatureObject* c,const std::string& key){if(key.empty() || key.size()>20 || key.find_first_not_of("0123456789")!=std::string::npos)return nullptr;auto o=c->getZoneServer()->getObject(std::stoull(key));return o && o->isShipObject()?o->asShipObject():nullptr;}
 static ShipObject* current(CreatureObject* c){auto o=c?c->getRootParent():nullptr;return o && o->isShipObject() && spaceZoneName(zone(c))?o->asShipObject():nullptr;}

 // Ground building cells never index an owned ship's independent cell vector.
 static CellObject* playerCell(CreatureObject* c,ShipObject* s){
  if(!s || !s->isPobShip() || current(c)!=s)return nullptr;
  auto parent=c->getParent().get();int index=parent && parent->isCellObject()?static_cast<CellObject*>(parent.get())->getCellNumber():1;
  auto pob=s->asPobShip();if(index<=0 || index>pob->getTotalCellNumber())throw std::runtime_error("jtl_invalid_cell");
  return pob->getCell(index-1);
 }
 static bool gunship(ShipObject* s){return s->getShipChassisName().contains("gunship") || s->getObjectTemplate()->getFullTemplateString().contains("gunship");}
 static bool supported(ShipObject* s){if(!s)return false;if(yacht(s))return true;if(s->isPobShip() || gunship(s))return false;const auto& entries=ConfigManager::instance()->getStringVector("Core3.JTL.SwgxrShipTemplates");for(int i=0;i<entries.size();++i)if(entries.get(i)==s->getObjectTemplate()->getFullTemplateString())return true;return false;}
 static ShipObject* owned(CreatureObject* c,const Json& r){auto s=r.contains("ship_id")?ship(c,std::to_string(oid(r,"ship_id"))):nullptr;if(!s){auto saved=data(c,"selected_ship");if(saved.is_string())s=ship(c,saved.get<std::string>());else s=entitled(c);}if(!s || s->getOwnerID()!=c->getObjectID() || !supported(s))throw std::runtime_error("jtl_supported_owned_ship_required");device(c,s);if(!s->canBePilotedBy(c))throw std::runtime_error("jtl_ship_certification_required");return s;}
 // Original POB launch accepts native group members (group maximum 20), not an authored chassis seat count.
 static int capacity(ShipObject* s){return s->isPobShip()?20:s->isMultiPassengerShip()?2:1;}
 static Json member(CreatureObject* c){return {{"id",id(c)},{"name",std::string(c->getFirstName().toCharArray())}};}
 static bool atTerminal(CreatureObject* c,uint64 terminal){if(!connected(c) || !SwgxrPlanets::supportedName(zone(c)) || c->isDead() || c->isIncapacitated() || c->isInCombat() || c->isRidingMount())return false;auto t=c->getZoneServer()->getObject(terminal);return starshipTerminal(t) && t->getZone()==c->getZone() && t->getParentID()==c->getParentID() && c->isInRange(t,8) && CollisionManager::checkLineOfSight(c,t);}
 static void cancelStage(CreatureObject* pilot){auto stage=data(pilot,"launch_stage");if(stage.empty())return;for(auto& row:stage.value("members",Json::array())){auto c=player(pilot,row.at("id").get<std::string>());if(!c || c==pilot)continue;Locker lock(c,pilot);auto link=data(c,"crew_pilot");if(link.is_string() && link.get<std::string>()==id(pilot))save(c,"crew_pilot",Json::object());}save(pilot,"launch_stage",Json::object());}
 static Json stage(CreatureObject* c){auto pilot=c;auto link=data(c,"crew_pilot");if(link.is_string())pilot=player(c,link.get<std::string>());if(!pilot){save(c,"crew_pilot",Json::object());return Json::object();}Locker lock(pilot,c);auto value=data(pilot,"launch_stage");if(value.empty())return value;auto s=ship(pilot,value.at("ship_id").get<std::string>());uint64 terminal=oid(value,"terminal_id");if(!s || s->isShipLaunched() || !atTerminal(pilot,terminal)){cancelStage(pilot);return Json::object();}auto before=value["members"];Json members=Json::array();for(auto& row:before){auto candidate=player(c,row.at("id").get<std::string>());if(!candidate)continue;Locker memberLock(candidate,c);if(candidate==pilot || atTerminal(candidate,terminal))members.push_back(member(candidate));else save(candidate,"crew_pilot",Json::object());}value["members"]=members;if(before!=members)save(pilot,"launch_stage",value);return value;}
 static void removeFromStage(CreatureObject* c){auto link=data(c,"crew_pilot");if(link.is_string()){auto pilot=player(c,link.get<std::string>());if(pilot){Locker lock(pilot,c);auto value=data(pilot,"launch_stage");if(value.contains("members")){Json members=Json::array();for(auto& row:value["members"])if(row.at("id")!=id(c))members.push_back(row);value["members"]=members;save(pilot,"launch_stage",value);}}save(c,"crew_pilot",Json::object());}cancelStage(c);}
 static void crewAction(CreatureObject* c,const Json& r){auto action=r.at("action").get<std::string>();
  if(action=="crew_prepare"){auto s=owned(c,r);if(s->isShipLaunched() || !atTerminal(c,oid(r,"terminal_id")))throw std::runtime_error("jtl_starship_terminal_out_of_reach");removeFromStage(c);save(c,"selected_ship",id(s));Json value={{"id",r.at("request_id")},{"pilot_id",id(c)},{"ship_id",id(s)},{"terminal_id",r.at("terminal_id")},{"capacity",capacity(s)},{"members",Json::array({member(c)})}};save(c,"launch_stage",value);return;}
  if(action=="crew_cancel"){removeFromStage(c);return;}
  if(action=="crew_remove"){auto value=stage(c);if(value.empty() || value.at("pilot_id")!=id(c) || r.at("member_id")==id(c))throw std::runtime_error("jtl_crew_pilot_required");auto target=player(c,r.at("member_id").get<std::string>());if(!target)throw std::runtime_error("jtl_crew_member_missing");Locker lock(target,c);if(data(target,"crew_pilot")!=id(c))throw std::runtime_error("jtl_crew_member_missing");removeFromStage(target);return;}
  if(!r.value("handshake_authorized",false))throw std::runtime_error("jtl_mutual_handshake_required");auto pilot=player(c,r.at("pilot_id").get<std::string>());if(!pilot || pilot==c)throw std::runtime_error("jtl_crew_pilot_required");Locker lock(pilot,c);auto value=stage(pilot);if(value.empty() || value.at("id")!=r.at("launch_id") || !atTerminal(c,oid(value,"terminal_id")) || !c->isInRange(pilot,3))throw std::runtime_error("jtl_crew_stage_changed");for(auto& row:value["members"])if(row.at("id")==id(c))return;if(value["members"].size()>=value.at("capacity").get<unsigned>())throw std::runtime_error("jtl_crew_full");removeFromStage(c);value["members"].push_back(member(c));save(c,"crew_pilot",id(pilot));save(pilot,"launch_stage",value);
 }
 // The original Tatooine station serves four cities. Mos Eisley is the explicit
 // original landing fallback; the native interplanetary travel point provides its
 // current arrival/floor. Space coordinates are never treated as ground coordinates.
 static Vector3 disconnectArrival(CreatureObject* c){auto z=c->getZoneServer()->getZone("tatooine");if(!z || !z->getPlanetManager())throw std::runtime_error("jtl_disconnect_starport_unavailable");Vector3 anchor(3600,-4785,5);auto travel=z->getPlanetManager()->getNearestPlanetTravelPoint(anchor,16000,true);if(!travel)throw std::runtime_error("jtl_disconnect_starport_unavailable");auto p=travel->getArrivalPosition();p.setZ(CollisionManager::getWorldFloorCollision(p.getX(),p.getY(),p.getZ(),z,true));return p;}
 static void bind(CreatureObject* c,ShipObject* s){save(c,"aboard_ship",id(s));String z="tatooine";auto p=disconnectArrival(c);c->getPlayerObject()->setSpaceLaunchZone(z);c->getPlayerObject()->setSpaceLaunchLocation(p);}

 static void insertGuest(CreatureObject* c,ShipObject* s){if(s->getTotalPlayersOnBoard()>=capacity(s))throw std::runtime_error("jtl_crew_full");c->clearSpaceStates();c->clearState(CreatureState::SITTINGONCHAIR);c->setPosture(CreaturePosture::UPRIGHT);InsertGroupMembertIntoShipTask task(s,c->getObjectID(),s->isMultiPassengerShip()?PlayerArrangement::SHIP_GUNNER1:-1);task.run();if(current(c)!=s)throw std::runtime_error("jtl_native_guest_insert_failed");s->addPlayerOnBoard(c);bind(c,s);c->getPlayerObject()->notifySceneReady();c->getPlayerObject()->setScreenPlayData("swgxr_jtl","station","");persist(c,s);}
 static void eject(CreatureObject* c,ShipObject* s){String z="tatooine";auto p=disconnectArrival(c);if(!SwgxrPlanets::supported(z))throw std::runtime_error("jtl_invalid_return_zone");if(s){s->removePlayerOnBoard(c);eraseWalker(s,c);}c->clearSpaceStates();c->clearState(CreatureState::SITTINGONCHAIR);c->setPosture(CreaturePosture::UPRIGHT);c->switchZone(z,p.getX(),p.getZ(),p.getY(),0,false,-1);c->getPlayerObject()->notifySceneReady();SwgxrMovement::begin(c);save(c,"aboard_ship",Json::object());save(c,"parked_ship",Json::object());save(c,"boarding_request",Json::object());c->updateToDatabaseAllObjects(false);}
 static bool alone(CreatureObject* c,ShipObject* s){auto ids=s->getPlayersOnBoard();for(int i=0;i<ids.size();++i)if(ids.get(i)!=c->getObjectID())return false;for(int i=0;i<s->getSlottedObjectsSize();++i){auto o=s->getSlottedObject(i);if(o && o!=c && (o->isPlayerCreature() || (o->isCreatureObject() && o->getContainmentType()>=PlayerArrangement::SHIP_GUNNER0 && o->getContainmentType()<=PlayerArrangement::SHIP_GUNNER7)))return false;}return true;}
 static void boardingEligible(CreatureObject* guest,ShipObject* own,ShipObject* host){if(!own || !host || own==host || own->isPobShip() || gunship(own) || !supported(own) || !host->isPobShip() || !supported(host))throw std::runtime_error("jtl_boarding_ship_class_rejected");requirePilot(guest,own);device(guest,own);if(!alone(guest,own))throw std::runtime_error("jtl_boarding_seat_occupied");auto captain=player(guest,std::to_string(host->getOwnerID()));if(!connected(guest) || !captain || !connected(captain) || host->getPilot()!=captain || current(captain)!=host || !captain->isPilotingShip() || own->getZone()!=host->getZone() || !own->isInRange(host,256) || !std::isfinite(own->getCurrentSpeed()) || !std::isfinite(host->getCurrentSpeed()) || std::abs(own->getCurrentSpeed())>1 || std::abs(host->getCurrentSpeed())>1)throw std::runtime_error("jtl_boarding_hold_nearby");if(host->getTotalPlayersOnBoard()>=capacity(host))throw std::runtime_error("jtl_crew_full");}
 static void boardingAction(CreatureObject* c,const Json& r){auto action=r.at("action").get<std::string>();
  if(action=="boarding_request"){auto own=current(c);auto host=ship(c,r.at("target_ship_id").get<std::string>());if(!own || !host)throw std::runtime_error("jtl_boarding_ship_class_rejected");Locker hostLock(host,c);Locker ownLock(own,c);boardingEligible(c,own,host);auto captain=player(c,std::to_string(host->getOwnerID()));Locker lock(captain,c);save(c,"boarding_request",{{"target_ship_id",id(host)},{"ship_id",id(own)},{"requester_id",id(c)},{"name",std::string(c->getFirstName().toCharArray())},{"expires",epoch()+30},{"guest_session",leaseToken(c)},{"captain_session",leaseToken(captain)}});auto incoming=data(captain,"boarding_incoming");if(!incoming.is_array())incoming=Json::array();bool present=false;for(auto& key:incoming)if(key==id(c))present=true;if(!present)incoming.push_back(id(c));while(incoming.size()>32)incoming.erase(incoming.begin());save(captain,"boarding_incoming",incoming);return;}
  if(action=="return_ship"){auto parked=data(c,"parked_ship");auto host=current(c);if(parked.empty() || !host || parked.at("host_ship_id")!=id(host))throw std::runtime_error("jtl_return_ship_unavailable");Locker hostLock(host,c);auto own=owned(c,Json{{"ship_id",parked.at("ship_id")}});Locker lock(own,c);auto d=device(c,own);if(own->isShipLaunched())throw std::runtime_error("jtl_return_ship_already_launched");parked["phase"]="returning";save(c,"parked_ship",parked);auto pos=host->getPosition();pos.setX(std::min(6900.f,pos.getX()+200));auto oldZone=own->getSpaceLaunchZone();auto oldReturn=own->getSpaceLaunchLocation();try{if(d->launchShip(c,host->getZone()->getZoneName(),pos)!=own)throw std::runtime_error("jtl_native_launch_failed");c->clearSpaceStates();InsertPilotIntoShipTask insert(c,own);insert.run();if(current(c)!=own)throw std::runtime_error("jtl_native_board_failed");host->removePlayerOnBoard(c);eraseWalker(host,c);own->setSpaceLaunchZone(oldZone);own->setSpaceLaunchLocation(oldReturn);if(yacht(own))own->setOptionBit(OptionBitmask::INVULNERABLE,false);own->setCurrentSpeed(0);eraseMotion(own);motion(own);bind(c,own);save(c,"parked_ship",Json::object());save(c,"selected_ship",id(own));c->getPlayerObject()->notifySceneReady();persist(c,own);}catch(...){if(own->isShipLaunched())store(c,own,true);if(spaceZoneName(zone(c)))eject(c,host);host->removePlayerOnBoard(c);eraseWalker(host,c);save(c,"parked_ship",Json::object());save(c,"aboard_ship",Json::object());c->updateToDatabaseAllObjects(false);throw;}return;}
  auto host=current(c);if(!host)throw std::runtime_error("jtl_pilot_required");Locker hostLock(host,c);requirePilot(c,host);auto guest=player(c,r.at("requester_id").get<std::string>());if(!guest)throw std::runtime_error("jtl_boarding_request_missing");Locker lock(guest,c);auto pending=data(guest,"boarding_request");if(pending.empty() || pending.at("target_ship_id")!=id(host) || pending.at("expires").get<double>()<epoch() || pending.value("guest_session",std::string())!=leaseToken(guest) || pending.value("captain_session",std::string())!=leaseToken(c))throw std::runtime_error("jtl_boarding_request_expired");if(action=="boarding_decline"){save(guest,"boarding_request",Json::object());return;}auto own=current(guest);if(!own || pending.at("ship_id")!=id(own))throw std::runtime_error("jtl_boarding_ship_changed");Locker shipLock(own,c);boardingEligible(guest,own,host);save(guest,"parked_ship",{{"ship_id",id(own)},{"device_id",std::to_string(own->getControlDeviceID())},{"host_ship_id",id(host)}});try{store(guest,own,true);insertGuest(guest,host);}catch(...){if(spaceZoneName(zone(guest)))eject(guest,current(guest));save(guest,"parked_ship",Json::object());throw;}save(guest,"boarding_request",Json::object());
 }
 static Json crew(ShipObject* s,CreatureObject* observer){Json rows=Json::array();auto ids=s->getPlayersOnBoard();for(int i=0;i<ids.size();++i){auto c=player(observer,std::to_string(ids.get(i)));if(!c)continue;Locker lock(c,observer);if(current(c)!=s)continue;auto row=member(c);row["ship_id"]=id(s);row["kind"]="player";row["position"]=c->isPilotingShip() && s->isPobShip()?Json::array({-.76,.93,21.14}):s->isPobShip()?point(c):Json::array({0,0,0});auto cell=playerCell(c,s);row["cell_index"]=cell?cell->getCellNumber():0;row["cell_id"]=id(cell);row["heading_radians"]=c->getDirection()->getRadians();row["posture"]=int(c->getPosture());row["station"]=s->getPilot()==c?"pilot":s->isPobShip()?passengerSeated(c)?"passenger":"interior":"gunner";row["appearance"]=SwgxrPublicAppearance::publicAppearance(c);row["equipment_complete"]=row["appearance"]["equipment_complete"];row["template"]=row["appearance"]["template"];row["dead"]=c->isDead();row["incapacitated"]=c->isIncapacitated();row["scale"]=c->getHeight(false);rows.push_back(row);}return rows;}
 static Json boardingState(CreatureObject* c){Json out={{"incoming",Json::array()},{"pending",Json::object()},{"return_ship",data(c,"parked_ship")}};auto pending=data(c,"boarding_request");if(!pending.empty() && pending.value("expires",0.)>epoch() && pending.value("guest_session",std::string())==leaseToken(c)){pending.erase("guest_session");pending.erase("captain_session");out["pending"]=pending;}auto list=data(c,"boarding_incoming");if(list.is_array())for(auto& key:list){auto guest=player(c,key.get<std::string>());if(!guest)continue;Locker lock(guest,c);auto request=data(guest,"boarding_request");if(!request.empty() && current(c) && request.at("target_ship_id")==id(current(c)) && request.value("expires",0.)>epoch() && connected(guest) && request.value("guest_session",std::string())==leaseToken(guest) && request.value("captain_session",std::string())==leaseToken(c)){request.erase("guest_session");request.erase("captain_session");out["incoming"].push_back(request);}}return out;}

public:
 static bool starshipTerminal(SceneObject* o){return o && o->isTerminal() && o->getObjectTemplate()->getFullTemplateString()=="object/tangible/terminal/terminal_space.iff";}
static void recoverGround(CreatureObject* c){if(!spaceZoneName(zone(c)))return;auto s=current(c);if(!s){auto saved=data(c,"aboard_ship");if(saved.is_string())s=ship(c,saved.get<std::string>());}if(s){Locker lock(s,c);if(s->getOwnerID()==c->getObjectID()){String fallback="tatooine";auto arrival=disconnectArrival(c);s->setSpaceLaunchZone(fallback);s->setSpaceLaunchLocation(arrival);store(c,s);if(spaceZoneName(zone(c)))eject(c,s);}else eject(c,s);}else eject(c,nullptr);}

 static void expire(CreatureObject* c){removeFromStage(c);save(c,"boarding_request",Json::object());recoverGround(c);}
 static void watchdog(ManagedWeakReference<CreatureObject*> weak,const std::string& token){auto current=weak.get();if(!current)return;uint64 owner=current->getObjectID();Core::getTaskManager()->scheduleTask([weak,token,owner]() mutable {auto c=weak.get();if(!c || !c->getPlayerObject()){std::lock_guard<std::mutex> lock(leaseMutex());auto it=leases().find(owner);if(it!=leases().end() && it->second.token==token)leases().erase(it);return;}bool expired=false;{std::lock_guard<std::mutex> lock(leaseMutex());auto it=leases().find(c->getObjectID());if(it==leases().end() || it->second.token!=token)return;expired=now()-it->second.touched>60;}Locker lock(c);if(expired || c->getPlayerObject()->isOffline()){try{expire(c);}catch(const std::exception&){watchdog(weak,token);return;}std::lock_guard<std::mutex> guard(leaseMutex());auto it=leases().find(c->getObjectID());if(it!=leases().end() && it->second.token==token)leases().erase(it);return;}try{stage(c);}catch(const std::exception&){}watchdog(weak,token);},"SwgxrJtlCrewLease",1000);}
 static void attach(CreatureObject* c,const std::string& token){SwgxrJtlLifecycle::install(&disconnected);removeFromStage(c);save(c,"boarding_request",Json::object());if(!spaceZoneName(zone(c))){save(c,"parked_ship",Json::object());save(c,"aboard_ship",Json::object());}{std::lock_guard<std::mutex> lock(leaseMutex());leases()[c->getObjectID()]={token,now()};}watchdog(c,token);}
 static void touch(CreatureObject* c,const std::string& token){std::lock_guard<std::mutex> lock(leaseMutex());auto it=leases().find(c->getObjectID());if(it!=leases().end() && it->second.token==token)it->second.touched=now();}
 static void detach(CreatureObject* c){expire(c);std::lock_guard<std::mutex> lock(leaseMutex());leases().erase(c->getObjectID());}
 static void disconnected(CreatureObject* c){if(data(c,"aboard_ship").empty() && data(c,"launch_stage").empty() && data(c,"crew_pilot").empty())return;try{detach(c);}catch(const std::exception& e){c->error(String("JtL disconnect recovery: ")+e.what());}}
 static bool enabled(){return ConfigManager::instance()->isJtlEnabled() && ConfigManager::instance()->getBool("Core3.JTL.SwgxrTesterYachts",false);}
 static bool spaceZoneName(const std::string& name){static const std::set<std::string> zones={"space_corellia","space_dantooine","space_dathomir","space_endor","space_lok","space_naboo","space_tatooine","space_yavin4","space_light1","space_heavy1"};return zones.count(name)!=0;}
 static bool aboard(CreatureObject* c){auto root=c?c->getRootParent():nullptr;return root && root->isShipObject() && c->getZone() && c->getZone()->isSpaceZone() && spaceZoneName(zone(c));}
 static void provision(CreatureObject* c){
  if(!enabled())return;auto account=c->getPlayerObject()->getAccount();if(!account)throw std::runtime_error("jtl_native_account_required");Locker accountLock(account,c);
  if(account->getSwgxrYachtCharacter() && account->getSwgxrYachtCharacter()!=c->getObjectID())return;
  if(account->getSwgxrYachtShip())return; // Never recreate a sold/deleted grant.
  if(!account->getSwgxrYachtCharacter()){
   StringBuffer sql;sql << "SELECT character_oid FROM (SELECT character_oid, creation_date FROM characters WHERE account_id=" << c->getPlayerObject()->getAccountID() << " UNION SELECT character_oid, creation_date FROM characters_dirty WHERE account_id=" << c->getPlayerObject()->getAccountID() << ") AS owned ORDER BY creation_date ASC, character_oid ASC LIMIT 1";
   UniqueReference<ResultSet*> rows(ServerDatabase::instance()->executeQuery(sql));if(!rows || !rows->next())throw std::runtime_error("jtl_first_character_unavailable");if(rows->getUnsignedLong(0)!=c->getObjectID())return;account->setSwgxrYachtCharacter(c->getObjectID());ObjectManager::instance()->updatePersistentObject(account);
  }
  ShipObject* ship=nullptr;auto pad=c->getDatapad();if(!pad)throw std::runtime_error("jtl_datapad_required");
  for(int i=0;i<pad->getContainerObjectsSize();++i){auto o=pad->getContainerObject(i);if(!o || !o->isShipControlDevice())continue;auto controlled=static_cast<ShipControlDevice*>(o.get())->getControlledObject();if(yacht(controlled) && controlled->asShipObject()->getOwnerID()==c->getObjectID()){ship=controlled->asShipObject();break;}}
  if(!ship)ship=ShipManager::instance()->createPlayerShip(c,"object/ship/player/player_sorosuub_space_yacht.iff","",true);
  if(!ship || !yacht(ship))throw std::runtime_error("jtl_native_yacht_creation_failed");ship->setShipName("Luxury Yacht");persist(c,ship);account->setSwgxrYachtShip(ship->getObjectID());ObjectManager::instance()->updatePersistentObject(account);
 }
 static Json snapshot(CreatureObject* c){
  // Original station storage runs asynchronously, outside our explicit store().
  // Rebase ground movement once at its confirmed native arrival, including crew.
  if(!aboard(c) && SwgxrPlanets::supportedName(zone(c)) && !data(c,"aboard_ship").empty()){
   SwgxrMovement::begin(c);c->clearState(CreatureState::SITTINGONCHAIR);c->setPosture(CreaturePosture::UPRIGHT);
   c->getPlayerObject()->setScreenPlayData("swgxr_jtl","station","");save(c,"aboard_ship",Json::object());save(c,"parked_ship",Json::object());
  }
  Json out={{"enabled",enabled()},{"scope","original_sectors"},{"space_active",aboard(c)},{"ships",Json::array()},{"ship",Json::object()},{"launch_stage",Json::object()},{"boarding",Json::object()},{"nearby_ships",Json::array()}};if(!enabled())return out;
  SwgxrSpaceJournal::snapshot(c,out);out["launch_stage"]=stage(c);out["boarding"]=boardingState(c);auto pad=c->getDatapad();if(pad)for(int i=0;i<pad->getContainerObjectsSize();++i){auto d=pad->getContainerObject(i);if(!d || !d->isShipControlDevice())continue;auto controlled=static_cast<ShipControlDevice*>(d.get())->getControlledObject();if(!controlled || !controlled->isShipObject())continue;auto own=controlled->asShipObject();if(own->getOwnerID()!=c->getObjectID())continue;out["ships"].push_back({{"id",id(own)},{"device_id",id(d)},{"template",std::string(own->getObjectTemplate()->getFullTemplateString().toCharArray())},{"name",std::string(own->getDisplayedName().toCharArray())},{"owner_id",id(c)},{"launched",own->isShipLaunched()},{"supported",supported(own)},{"eligible",supported(own) && own->canBePilotedBy(c) && !own->isShipLaunched()},{"reason",!supported(own)?"Original ship assets are not enabled":!own->canBePilotedBy(c)?"Original pilot certification required":own->isShipLaunched()?"Ship already launched":""}});}
  auto s=current(c);if(!s){try{s=owned(c,Json::object());}catch(const std::exception&){return out;}}Locker lock(s,c);if(s->isHyperspacing())eraseMotion(s);Motion offline;auto& motionState=s->isShipLaunched()?motion(s):offline;
  if(aboard(c)){SortedVector<ManagedReference<TreeEntry*>> objects(128,128);c->getZone()->getInRangeObjects(s->getPositionX(),s->getPositionZ(),s->getPositionY(),2048,&objects,true);std::vector<ManagedReference<ShipObject*>> nearby;for(int i=0;i<objects.size();++i){auto o=static_cast<SceneObject*>(objects.get(i).get());if(o!=s && o->isShipObject() && (supported(o->asShipObject()) || o->isShipAiAgent()))nearby.push_back(o->asShipObject());}std::sort(nearby.begin(),nearby.end(),[&](ShipObject* a,ShipObject* b){return s->getPosition().squaredDistanceTo(a->getPosition())<s->getPosition().squaredDistanceTo(b->getPosition());});out["nearby_ships_truncated"]=nearby.size()>32;for(auto targetRef:nearby){if(out["nearby_ships"].size()>=32)break;auto target=targetRef.get();
   // Snapshot holds the pilot and own ship. Never wait on an NPC combat lock:
   // native AI can hold that target while waiting for the player's ship.
   bool held=target->isLockedByCurrentThread();if(!held && !target->tryWLock()){out["nearby_ships_busy"]=true;continue;}
   struct UnlockTarget {ShipObject* ship;~UnlockTarget(){if(ship)ship->unlock();}} unlockTarget{held?nullptr:target};
   auto row=record(target);row["station_comms"]=target->isSpaceStation() && target->asShipAiAgent()->getConversationTemplate()!=0;row["comm_in_range"]=s->checkInConversationRange(target);row["npc"]=target->isShipAiAgent();row["hostile"]=!yacht(s) && target->isAggressiveTo(s);row["speed_mps"]=target->getCurrentSpeed();row["hull"]={{"current",target->getChassisCurrentHealth()},{"maximum",target->getChassisMaxHealth()}};row["name"]=std::string(target->getDisplayedName().toCharArray());row["owner_id"]=std::to_string(target->getOwnerID());row["kind"]=target->isPobShip()?"pob":target->isMultiPassengerShip()?"multiseat":"fighter";bool eligible=true;try{boardingEligible(c,s,target);}catch(const std::exception&){eligible=false;}row["boarding_available"]=eligible;row["distance_m"]=s->getPosition().distanceTo(target->getPosition());row["boarding_reason"]=eligible?"":"Pilot a supported empty small craft and stop within 256 metres of a piloted POB";out["nearby_ships"].push_back(row);}}

  auto row=record(s);row["zone"]=s->getZone()?s->getZone()->getZoneName().toCharArray():"";row["speed_mps"]=s->getCurrentSpeed();row["max_speed_mps"]=s->getActualMaxSpeed();row["kind"]=s->isPobShip()?"pob":s->isMultiPassengerShip()?"multiseat":"fighter";row["owner_id"]=std::to_string(s->getOwnerID());row["capacity"]=capacity(s);row["capacity_source"]=s->isPobShip()?"original_group_launch_limit":"original_seat_arrangements";row["crew"]=crew(s,c);row["station"]=aboard(c)?s->getPilot()==c?"pilot":s->isPobShip()?passengerSeated(c)?"passenger":"interior":"gunner":"ground";row["player_position"]=aboard(c)?s->isPobShip()?s->getPilot()==c?Json::array({-.76,.93,21.14}):point(c):Json::array({0,0,0}):point(c);auto cell=playerCell(c,s);row["cell_index"]=cell?cell->getCellNumber():0;row["cell_id"]=id(cell);row["velocity"]=motionState.state.velocity;row["angular_velocity"]=motionState.state.angular;row["power"]=motionState.power;row["control_sequence"]=motionState.state.sequence;row["walk_sequence"]=motionState.walkers[c->getObjectID()].sequence;row["item_limit"]=s->isPobShip()?s->asPobShip()->getMaximumNumberOfPlayerItems():0;row["item_count"]=s->isPobShip()?s->asPobShip()->getCurrentNumberOfPlayerItems():0;
  out["combat_events"]=SwgxrSpaceEvents::snapshot(s);row["capacitor"]={{"current",s->getCapacitorEnergy()},{"maximum",s->getCapacitorMaxEnergy()}};row["can_furnish"]=s->isPobShip() && s->asPobShip()->isOnAdminList(c);row["hyperspacing"]=s->isHyperspacing();row["hyperspace"]=SwgxrHyperspace::snapshot(s->getObjectID(),s->isHyperspacing());row["hyperspace_delay"]=s->getHyperspaceDelay();row["hull"]={{"current",s->getChassisCurrentHealth()},{"maximum",s->getChassisMaxHealth()}};row["combat_excluded"]=yacht(s);row["shields"]={{"front",s->getFrontShield()},{"rear",s->getRearShield()},{"max_front",s->getMaxFrontShield()},{"max_rear",s->getMaxRearShield()}};row["cells"]=Json::array();row["decorations"]=Json::array();auto pob=s->asPobShip();
  for(int i=0;pob && i<pob->getTotalCellNumber();++i){auto cell=pob->getCell(i);if(!cell)continue;row["cells"].push_back({{"id",id(cell)},{"index",cell->getCellNumber()},{"name",std::string("cell_")+std::to_string(i)}});for(int n=0;n<cell->getContainerObjectsSize() && row["decorations"].size()<400;++n){auto item=cell->getContainerObject(n);if(!item || item->isCreatureObject() || s->containsChildObject(item))continue;auto itemRow=record(item);itemRow["name"]=std::string(item->getDisplayedName().toCharArray());itemRow["cell_index"]=cell->getCellNumber();row["decorations"].push_back(itemRow);}}
  auto chair=s->getPilotChair().get();auto pilot=s->getPilot();row["stations"]=Json::array({{{"id","pilot"},{"object_id",id(chair)},{"cell_index",1},{"position",Json::array({-.76,.43,21.14})},{"occupied_by",id(pilot)}}});if(s->isPobShip())row["stations"].push_back({{"id","passenger"},{"object_id",id(passenger(s))},{"cell_index",1},{"position",Json::array({.75,.43,21.15})},{"occupied_by",passengerOccupant(s,c)}});if(!s->isPobShip())row["stations"]=Json::array({{{"id","pilot"},{"object_id",id(pilot)},{"cell_index",0},{"position",Json::array({0,0,0})},{"occupied_by",id(pilot)}}});row["commands"]=Json::array();
  for(auto cmd:{"shield_front","shield_rear","shield_balance","power_engines","power_balanced"})row["commands"].push_back({{"id",cmd},{"label",cmd},{"available",aboard(c) && pilot==c},{"reason",pilot==c?"":"Pilot station required"}});
  for(auto cmd:{"droidcommand_shieldadjustfrontone","droidcommand_shieldadjustrearone","droidcommand_engineoverloadone","droidcommand_enginenormalize"}){bool available=aboard(c) && pilot==c && s->isComponentFunctional(Components::DROID_INTERFACE) && s->getShipDroidID()!=0 && s->hasDroidCommand(String(cmd).hashCode());row["commands"].push_back({{"id",cmd},{"label",cmd},{"available",available},{"reason",available?"":"Installed interface, assigned droid and program required"}});}
  row["interactions"]=Json::array();auto children=s->getChildObjects();for(int i=0;i<children->size();++i){auto object=children->get(i);auto name=object->getObjectTemplate()->getFullTemplateString();bool up=name=="object/tangible/terminal/terminal_elevator_up.iff",down=name=="object/tangible/terminal/terminal_elevator_down.iff",house=name=="object/tangible/terminal/terminal_pob_ship.iff";if(!up && !down && !house)continue;auto parent=object->getParent().get();if(!parent || !parent->isCellObject())continue;row["interactions"].push_back({{"id",id(object)},{"kind",house?"house":"ship_control"},{"template",std::string(name.toCharArray())},{"quaternion",quat(object)},{"command_id",house?"pob_terminal":up?"elevator_up":"elevator_down"},{"label",house?"Ship housing terminal":up?"Elevator up":"Elevator down"},{"cell_index",static_cast<CellObject*>(parent.get())->getCellNumber()},{"position",point(object)}});}
  auto returnPosition=s->getSpaceLaunchLocation();out["return_location"]={{"zone",std::string(s->getSpaceLaunchZone().toCharArray())},{"position",Json::array({returnPosition.getX(),returnPosition.getZ(),returnPosition.getY()})},{"building_id","0"},{"cell_index",0},{"heading_radians",0}};
  out["station_conversation"]=data(c,"station_conversation");out["ship"]=row;return out;
 }
 static Json finish(CreatureObject* c,const Json& request,Json receipts){auto key=request.at("request_id").get<std::string>();receipts.push_back({{"id",key},{"request",request}});while(receipts.size()>32)receipts.erase(receipts.begin());save(c,"receipts",receipts);c->updateToDatabaseAllObjects(false);return {{"success",true},{"source_kind","core3_jtl"},{"character_id",id(c)},{"action",request.at("action")},{"request_id",key},{"jtl",snapshot(c)}};}
 static Json run(CreatureObject* c,const Json& r){
  if(!enabled())throw std::runtime_error("jtl_disabled");auto action=r.at("action").get<std::string>();if(c->isDead() || c->isIncapacitated() || (c->isInCombat() && !aboard(c)))throw std::runtime_error("jtl_player_unavailable");if(action=="status"){provision(c);return {{"success",true},{"source_kind","core3_jtl"},{"character_id",id(c)},{"jtl",snapshot(c)}};}
  bool mutating=action!="control" && action!="walk";Json receipts=Json::array(),canonical=r;canonical.erase("handshake_receipt_only");auto key=r.value("request_id",std::string());if(mutating){if(key.size()<8 || key.size()>64 || key.find_first_not_of("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")!=std::string::npos)throw std::runtime_error("jtl_request_id_required");auto saved=c->getPlayerObject()->getScreenPlayData("swgxr_jtl","receipts");if(!saved.isEmpty())receipts=Json::parse(saved.toCharArray());for(auto& receipt:receipts)if(receipt.at("id")==key){if(receipt.at("request")!=canonical)throw std::runtime_error("jtl_request_id_reused");return {{"success",true},{"source_kind","core3_jtl"},{"character_id",id(c)},{"replayed",true},{"request_id",key},{"action",action},{"jtl",snapshot(c)}};}}
  if(r.value("handshake_receipt_only",false))throw std::runtime_error("jtl_handshake_receipt_missing");
  if(action=="crew_prepare" || action=="crew_cancel" || action=="crew_remove" || action=="crew_join"){crewAction(c,r);return finish(c,canonical,receipts);}
  if(action=="boarding_request" || action=="boarding_accept" || action=="boarding_decline" || action=="return_ship"){boardingAction(c,r);return finish(c,canonical,receipts);}
  auto s=current(c);if(!s)s=owned(c,r);Locker lock(s,c);if(r.contains("ship_id") && oid(r,"ship_id")!=s->getObjectID())throw std::runtime_error("jtl_owned_ship_required");

  if(action=="launch"){
   auto launchStage=stage(c);if(launchStage.empty() || launchStage.at("pilot_id")!=id(c) || launchStage.at("id")!=r.at("launch_id") || launchStage.at("terminal_id")!=r.at("terminal_id") || launchStage.at("ship_id")!=id(s))throw std::runtime_error("jtl_launch_confirmation_required");auto d=device(c,s);
   if(s->isShipLaunched()){if(!aboard(c))throw std::runtime_error("jtl_ship_already_launched");}
   else{
    if(!SwgxrPlanets::supportedName(zone(c)) || c->isRidingMount())throw std::runtime_error("jtl_launch_ground_required");auto terminal=c->getZoneServer()->getObject(oid(r,"terminal_id"));if(!starshipTerminal(terminal) || terminal->getZone()!=c->getZone() || terminal->getParentID()!=c->getParentID() || !c->isInRange(terminal,8) || !CollisionManager::checkLineOfSight(c,terminal))throw std::runtime_error("jtl_starship_terminal_out_of_reach");auto originalGround=c->getZone();if(!originalGround || !originalGround->getPlanetManager())throw std::runtime_error("jtl_original_launch_point_unavailable");auto spaceName=originalGround->getPlanetManager()->getJtlZoneName();if(!spaceZoneName(spaceName.toCharArray()))throw std::runtime_error("jtl_original_launch_zone_unavailable");auto space=c->getZoneServer()->getZone(spaceName);if(!space)throw std::runtime_error("jtl_space_zone_not_loaded");d->setStoredLocationData(c);auto returnZone=d->getStoredZoneName();auto returnPosition=d->getStoredPosition(false);if(!SwgxrPlanets::supported(returnZone))throw std::runtime_error("jtl_native_landing_point_required");
    s->setSpaceLaunchZone(returnZone);s->setSpaceLaunchLocation(returnPosition);c->getPlayerObject()->setSpaceLaunchZone(returnZone);c->getPlayerObject()->setSpaceLaunchLocation(returnPosition);
    {Locker deviceLock(d,c);auto launch=originalGround->getPlanetManager()->getJtlLaunchLocations();launch.setX(launch.getX()+500);if(d->launchShip(c,spaceName,launch)!=s)throw std::runtime_error("jtl_native_launch_failed");}
    if(yacht(s))s->setOptionBit(OptionBitmask::INVULNERABLE,false);s->setCurrentSpeed(0);eraseMotion(s);motion(s);try{InsertPilotIntoShipTask insert(c,s);insert.run();if(current(c)!=s)throw std::runtime_error("jtl_native_board_failed");c->getPlayerObject()->notifySceneReady();bind(c,s);for(auto& member:launchStage.at("members")){if(member.at("id")==id(c))continue;auto guest=player(c,member.at("id").get<std::string>());if(!guest)throw std::runtime_error("jtl_crew_member_missing");Locker guestLock(guest,c);if(!atTerminal(guest,oid(launchStage,"terminal_id")))throw std::runtime_error("jtl_crew_member_left");insertGuest(guest,s);}}catch(...){store(c,s);cancelStage(c);throw;}cancelStage(c);persist(c,s);
   }
  }else if(action=="land"){
   if(s->isShipLaunched()){requirePilot(c,s);store(c,s);}
  }else if(action=="station"){
   if(!s->isPobShip())throw std::runtime_error("jtl_no_walkable_interior");if(passengerSeated(c))throw std::runtime_error("jtl_leave_station_first");auto cell=interior(c,s);auto station=r.at("station_id").get<std::string>();if(station=="pilot" && s->getOwnerID()!=c->getObjectID())throw std::runtime_error("jtl_captain_required");if(station=="passenger" && passengerOccupant(s,c)!="0")throw std::runtime_error("jtl_station_occupied");if((station!="pilot" && station!="passenger") || cell->getCellNumber()!=1)throw std::runtime_error("jtl_invalid_station");SceneObject* chair=nullptr;if(station=="pilot")chair=s->getPilotChair().get();else chair=passenger(s);if(!chair || !c->isInRange(chair,3) || (station=="pilot" && s->getPilot()!=nullptr && s->getPilot()!=c))throw std::runtime_error("jtl_station_unavailable");if(station=="pilot"){InsertPilotIntoShipTask insert(c,s);insert.run();}else{c->initializePosition(chair->getPositionX(),chair->getPositionZ(),chair->getPositionY());c->setPosture(CreaturePosture::SITTING);c->setState(CreatureState::SITTINGONCHAIR);c->updateZoneWithParent(cell,true);}c->getPlayerObject()->setScreenPlayData("swgxr_jtl","station",String(station.c_str()));c->getPlayerObject()->notifySceneReady();
  }else if(action=="leave"){
   if(!s->isPobShip())throw std::runtime_error("jtl_no_walkable_interior");if(!passengerSeated(c))requirePilot(c,s);auto cell=s->asPobShip()->getCell(0);if(!cell)throw std::runtime_error("jtl_bridge_unavailable");s->setCurrentSpeed(0);swgxr::jtl::stop(motion(s).state);c->clearSpaceStates();c->clearState(CreatureState::SITTINGONCHAIR);c->setPosture(CreaturePosture::UPRIGHT);c->getPlayerObject()->setScreenPlayData("swgxr_jtl","station","");c->switchZone(s->getZone()->getZoneName(),0,.4,20,cell->getObjectID(),false,-1);c->getPlayerObject()->notifySceneReady();motion(s).walkers[c->getObjectID()]={now(),1.5,0};
  }else if(action=="hyperspace" || action=="abort_hyperspace"){
   requirePilot(c,s);std::string destination=r.value("destination",std::string());if(action=="hyperspace"){auto manager=ShipManager::instance();String pointName(destination.c_str());if(!manager->hyperspaceLocationExists(pointName) || !spaceZoneName(manager->getHyperspaceZone(pointName).toCharArray()))throw std::runtime_error("jtl_unknown_hyperspace_destination");}auto q=c->getZoneServer()->getObjectController()->getQueueCommand(action=="hyperspace"?"hyperspace":"aborthyperspace");if(!q || q->doQueueCommand(c,0,UnicodeString(String(destination.c_str())))!=QueueCommand::SUCCESS)throw std::runtime_error("jtl_native_hyperspace_rejected");s->setCurrentSpeed(0);eraseMotion(s);
  }else if(action=="comm_begin" || action=="comm_choose"){
   requirePilot(c,s);auto target=c->getZoneServer()->getObject(oid(r,"station_id"));save(c,"station_conversation",SwgxrStationComms::run(c,s,target,r));
  }else if(action=="control"){
   if(s->isHyperspacing())throw std::runtime_error("jtl_hyperspace_in_progress");
   requirePilot(c,s);swgxr::jtl::Input input;input.throttle=r.at("throttle").get<double>();input.pitch=r.at("pitch").get<double>();input.yaw=r.at("yaw").get<double>();input.roll=r.at("roll").get<double>();input.sequence=r.at("sequence").get<uint64>();auto& m=motion(s);swgxr::jtl::validate(input);if(input.sequence<=m.state.sequence)throw std::runtime_error("jtl_stale_controls");double stamp=now();if(m.input.sequence)applyMotion(s,m,stamp);else m.state.stamp=stamp;m.input=input;m.primaryFire=r.value("primary_fire",false);m.received=stamp;m.state.sequence=input.sequence;if(!m.ticking){m.ticking=true;flightTick(s,m.generation);}
  }else if(action=="walk")walk(c,s,r);
  else if(action=="decorate" || action=="recover")furnish(c,s,r,action=="recover");
  else if(action=="command")command(c,s,r);
  else if(action=="terminal" || action=="terminal_recover")terminalAction(c,s,r);
  else throw std::runtime_error("jtl_unsupported_action");
  if(mutating){persist(c,s);return finish(c,canonical,receipts);}
  return {{"success",true},{"source_kind","core3_jtl"},{"character_id",id(c)},{"action",action},{"request_id",key},{"jtl",snapshot(c)}};
 }
};
