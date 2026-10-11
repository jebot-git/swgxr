#pragma once
#include "TargetingPolicy.h"
#include "server/zone/managers/spacecombat/projectile/ShipMissile.h"
#include "server/zone/objects/ship/transform/SpaceMath.h"
// Per-pilot ephemeral selection. Core3 remains authoritative for components,
// lock eligibility, projectiles, inspection, docking and quest observers.
class SwgxrJtlTargeting {
 using Json=JSONSerializationType;
public:
 struct State {
  uint64 target=0; int component=-1,missileSlot=-1; bool active=false;
  swgxr::jtl::MissileLock lock; std::string reason="Select a target";
 };
 static bool valid(ShipObject* own,ShipObject* target){
  return own && target && own!=target && own->getZone()!=nullptr && own->getZone()==target->getZone() &&
   !target->isShipDestroyed() && !target->isHyperspacing() && own->getPosition().squaredDistanceTo(target->getPosition())<=2048.f*2048.f;
 }
 static ManagedReference<ShipObject*> resolve(ShipObject* own,const State& state){
  if(!state.target || !own->getZoneServer())return nullptr;
  auto object=own->getZoneServer()->getObject(state.target);
  return object && object->isShipObject()?object->asShipObject():nullptr;
 }
 // Snapshot/tick already holds the pilot/own ship. Never wait on an AI lock
 // while it might be trying to acquire the own ship for native combat.
 static Vector3 localComponent(ShipObject* target,int slot){
  if(slot<0)return Vector3(0,0,0);
  auto data=ShipManager::instance()->getCollisionData(target);
  if(!data)return Vector3(0,0,0);
  auto crc=target->getShipComponentMap()->get(slot);
  const auto& points=data->getHardpoints(Components::shipComponentSlotToString(slot));
  if(!points.contains(crc))return Vector3(0,0,0);
  return points.get(crc).getSphere().getCenter();
 }
 static Vector3 aimPoint(ShipObject* target,int slot){return target->getPosition()+SpaceMath::getGlobalVector(localComponent(target,slot),*target->getConjugateMatrix());}
 static Json point(const Vector3& p){return Json::array({p.getX(),p.getZ(),p.getY()});}
 static void clear(CreatureObject* pilot,ShipObject* ship,State& state){state.target=0;state.component=-1;state.lock.reset();state.reason="Select a target";if(pilot)pilot->setTargetID(0);ship->setShipTargetID(0);ship->setShipTargetSlot(Components::SIZE);}
 static void select(CreatureObject* pilot,ShipObject* ship,State& state,uint64 id,int component,bool subsystem){
  if(subsystem && id!=state.target)throw std::runtime_error("jtl_target_changed");
  if(!id){if(subsystem)throw std::runtime_error("jtl_target_required");clear(pilot,ship,state);return;}
  State requested=state;requested.target=id;auto target=resolve(ship,requested);
  if(!target)throw std::runtime_error("jtl_target_unavailable");
  bool held=target->isLockedByCurrentThread();if(!held && !target->tryWLock())throw std::runtime_error("jtl_target_busy");
  struct Unlock{ShipObject* s;~Unlock(){if(s)s->unlock();}} guard{held?nullptr:target.get()};
  if(!valid(ship,target))throw std::runtime_error("jtl_target_out_of_range");
  if(component<-1 || component>Components::CAPITALSLOTMAX || (component>=0 && !target->isComponentTargetable(component)))throw std::runtime_error("jtl_subsystem_unavailable");
  if(state.target!=id || state.component!=component)state.lock.reset();
  state.target=id;state.component=component;pilot->setTargetID(id);ship->setShipTargetID(id);ship->setShipTargetSlot(component<0?Components::SIZE:component);
 }
 static const ShipProjectileData* missile(ShipObject* ship,int slot){
  if(slot<Components::WEAPON_START || slot>Components::FIGHTERSLOTMAX || !ship->isComponentFunctional(slot))return nullptr;
  auto data=ShipManager::instance()->getProjectileData(ship->getShipComponentMap()->get(slot));
  return data && data->isMissile()?data:nullptr;
 }
 static void selectMissile(ShipObject* ship,State& state,int slot){
  if(!missile(ship,slot))throw std::runtime_error("jtl_missile_launcher_unavailable");
  if(state.missileSlot!=slot){state.missileSlot=slot;state.lock.reset();}
 }
 static std::string eligibility(ShipObject* ship,ShipObject* target,const State& state){
  if(!valid(ship,target))return "Target unavailable";
  // This integration is ground/space PvE only. Neutral ships remain selectable
  // for inspection and docking, but must be natively attackable for firing.
  if(!target->isShipAiAgent() || !target->isAttackableBy(ship))return "Target is not attackable";
  if(state.component>=0 && !target->isComponentTargetable(state.component))return "Subsystem unavailable";
  if(target->isSlotTargetable(Components::BRIDGE) && state.component<0)return "Select a capital-ship subsystem";
  auto data=missile(ship,state.missileSlot);if(!data)return "Select a missile launcher";
  if(ship->getCurrentAmmoMap()->get(state.missileSlot)<1)return "No missiles";
  auto md=ShipManager::instance()->getMissileData(ship->getAmmoClassMap()->get(state.missileSlot));if(!md)return "Missile data unavailable";
  Vector3 delta=aimPoint(target,state.component)-ship->getPosition();double distance=delta.length();
  auto forward=SpaceMath::matrixToVelocity(*ship->getConjugateMatrix());
  double dot=distance>0?(delta.getX()*forward.getX()+delta.getY()*forward.getY()+delta.getZ()*forward.getZ())/distance:-1;
  if(distance>data->getRange())return "Missile target out of range";
  if(!swgxr::jtl::withinAcquisition(distance,data->getRange(),dot,md->getTargetAquisitionAngle()))return "Keep target inside the forward acquisition cone";
  return "";
 }
 static void update(ShipObject* ship,State& state,double stamp,bool fresh){
  auto target=resolve(ship,state);
  if(!target){state.lock.reset();state.reason="Select a target";if(state.target)clear(ship->getPilot(),ship,state);return;}
  bool held=target->isLockedByCurrentThread();if(!held && !target->tryWLock()){state.lock.reset();state.reason="Updating target";return;}
  struct Unlock{ShipObject* s;~Unlock(){if(s)s->unlock();}} guard{held?nullptr:target.get()};
  if(!valid(ship,target)){clear(ship->getPilot(),ship,state);return;}
  if(state.component>=0 && !target->isComponentTargetable(state.component)){state.lock.reset();state.reason="Subsystem unavailable · choose another subsystem";return;}
  state.reason=eligibility(ship,target,state);
  if(!fresh || !state.active || ship->isHyperspacing() || ship->isShipDocking()){state.lock.reset();state.reason="Flight controls inactive";return;}
  auto md=ShipManager::instance()->getMissileData(ship->getAmmoClassMap()->get(state.missileSlot));
  state.lock.update(stamp,state.reason.empty() && md,md?md->getTargetAquisitionTime():0);
 }
 static uint8 componentByte(const State& state){return state.target && state.component>=0?uint8(state.component):swgxr::jtl::NO_SUBSYSTEM;}
 static Json describeTarget(ShipObject* own,ShipObject* target,const State& state){
  Json row={{"id",std::to_string(target->getObjectID())},{"name",std::string(target->getDisplayedName().toCharArray())},{"position",point(target->getPosition())},{"aim_position",point(aimPoint(target,state.component))},{"component_slot",state.component},{"components",Json::array()},{"distance_m",own->getPosition().distanceTo(target->getPosition())},{"hostile",target->isAggressiveTo(own)},{"attackable",target->isShipAiAgent() && target->isAttackableBy(own)},{"radius",target->getBoundingRadius()}};
  row["velocity"]=point(SpaceMath::matrixToVelocity(*target->getConjugateMatrix())*target->getCurrentSpeed());
  row["hull"]={{"current",target->getChassisCurrentHealth()},{"maximum",target->getChassisMaxHealth()}};
  row["shields"]={{"front",target->getFrontShield()},{"rear",target->getRearShield()},{"max_front",target->getMaxFrontShield()},{"max_rear",target->getMaxRearShield()}};
  for(int slot=0;slot<=Components::CAPITALSLOTMAX;++slot){
   if(!target->getShipComponentMap()->get(slot) || !target->isSlotTargetable(slot))continue;
   row["components"].push_back({{"slot",slot},{"name",std::string(Components::shipComponentSlotToString(slot).toCharArray())},{"available",target->isComponentTargetable(slot)},{"health",target->getCurrentHitpointsMap()->get(slot)},{"maximum",target->getMaxHitpointsMap()->get(slot)},{"position",point(aimPoint(target,slot))}});
  }
  return row;
 }
 static Json snapshot(ShipObject* ship,State& state,double stamp){
  Json out={{"target_id",std::to_string(state.target)},{"component_slot",state.component},{"target",Json::object()},{"weapons",Json::array()},{"missile_slot",state.missileSlot},{"lock_acquired",state.lock.acquired && state.lock.last>0 && stamp-state.lock.last<=.3},{"lock_seconds",state.lock.elapsed},{"lock_reason",state.reason}};
  auto target=resolve(ship,state);
  if(target){bool held=target->isLockedByCurrentThread();if(held || target->tryWLock()){
   struct Unlock{ShipObject* s;~Unlock(){if(s)s->unlock();}} guard{held?nullptr:target.get()};
   if(valid(ship,target))out["target"]=describeTarget(ship,target,state);else clear(ship->getPilot(),ship,state);
  }else out["busy"]=true;}
  for(int slot=Components::WEAPON_START;slot<=Components::FIGHTERSLOTMAX;++slot){
   if(!ship->getShipComponentMap()->get(slot))continue;
   auto data=ShipManager::instance()->getProjectileData(ship->getShipComponentMap()->get(slot));if(!data)continue;
   bool turret=ShipManager::instance()->getShipTurretData(ship->getShipChassisName(),slot-Components::WEAPON_START)!=nullptr;
   bool primary=!turret && !data->isMissile() && !data->isCountermeasure() && !data->isMiningLaser() && !data->isTractorBeam() && !data->consumesAmmo();
   Json w={{"slot",slot},{"primary",primary},{"missile",data->isMissile()},{"available",ship->isComponentFunctional(slot) && !turret},{"speed",data->getSpeed()},{"range",data->getRange()},{"ammo",ship->getCurrentAmmoMap()->get(slot)}};
   if(data->isMissile()){auto md=ShipManager::instance()->getMissileData(ship->getAmmoClassMap()->get(slot));if(md){w["acquisition_seconds"]=md->getTargetAquisitionTime();w["acquisition_degrees"]=md->getTargetAquisitionAngle();}}
   out["weapons"].push_back(w);
  }
  out["target_id"]=std::to_string(state.target);out["component_slot"]=state.component;out["lock_acquired"]=state.lock.acquired && state.lock.last>0 && stamp-state.lock.last<=.3;out["lock_seconds"]=state.lock.elapsed;out["lock_reason"]=state.reason;return out;
 }
 static void fireMissile(CreatureObject* pilot,ShipObject* ship,State& state,double stamp,double received,std::map<int,double>& nextShot,const Json& request){
  if(ship->isShipDocking())throw std::runtime_error("jtl_ship_docking");
  if(request.at("target_id")!=std::to_string(state.target) || request.at("component_slot").get<int>()!=state.component || request.at("weapon_slot").get<int>()!=state.missileSlot)throw std::runtime_error("jtl_target_changed");
  if(!state.active || stamp-received>=swgxr::jtl::CONTROL_LEASE_SECONDS || !state.lock.acquired || stamp-state.lock.last>.3)throw std::runtime_error("jtl_missile_lock_required");
  auto target=resolve(ship,state);if(!target)throw std::runtime_error("jtl_target_unavailable");
  bool held=target->isLockedByCurrentThread();if(!held && !target->tryWLock())throw std::runtime_error("jtl_target_busy");
  struct Unlock{ShipObject* s;~Unlock(){if(s)s->unlock();}} guard{held?nullptr:target.get()};
  if(!eligibility(ship,target,state).empty()){state.lock.reset();throw std::runtime_error("jtl_missile_lock_lost");}
  int slot=state.missileSlot;auto data=missile(ship,slot);auto md=ShipManager::instance()->getMissileData(ship->getAmmoClassMap()->get(slot));
  if(nextShot[slot]>stamp)throw std::runtime_error("jtl_weapon_recharging");
  float cost=std::max(0.f,ship->getEnergyPerShotMap()->get(slot))/swgxr::jtl::clamp(ship->getComponentEnergyEfficiencyMap()->get(slot),.1,10);
  if(ship->getCapacitorEnergy()<cost)throw std::runtime_error("jtl_capacitor_empty");
  auto delta=ship->getDeltaVector();if(!delta)throw std::runtime_error("jtl_ship_unavailable");
  auto direction=SpaceMath::matrixToVelocity(*ship->getConjugateMatrix());
  auto projectile=new ShipMissile(ship,slot-Components::WEAPON_START,data->getIndex(),componentByte(state),ship->getPosition(),direction*7800.f,data->getSpeed(),data->getRange(),1.f,System::getMiliTime());
  projectile->readProjectileData(data);projectile->readMissileData(md);projectile->setTarget(target);projectile->setComponentTargetID(state.target);projectile->setHardpointTranslation(localComponent(target,state.component));projectile->calculateTimeToHit();
  ship->setCurrentAmmo(slot,ship->getCurrentAmmoMap()->get(slot)-1,nullptr,DeltaMapCommands::SET,delta);delta->sendMessages(ship);ship->setCapacitorEnergy(ship->getCapacitorEnergy()-cost,true);
  nextShot[slot]=stamp+std::max(.05,double(ship->getComponentRefireRate()->get(slot))/swgxr::jtl::clamp(ship->getComponentRefireEfficiency()->get(slot),.1,10));state.lock.reset();
  SpaceCombatManager::instance()->addMissile(ship,projectile);
 }
};
