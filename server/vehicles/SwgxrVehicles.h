#ifndef SWGXR_VEHICLES_H
#define SWGXR_VEHICLES_H
#include "server/zone/objects/intangible/VehicleControlDevice.h"
#include "server/zone/objects/creature/VehicleObject.h"
#include "server/zone/managers/collision/CollisionManager.h"
#include "templates/creature/SharedCreatureObjectTemplate.h"
#include <fstream>
#include <mutex>
#include <chrono>
// VR seating is independent of the legacy single rider containment slot.
// Core3 control devices, ownership, decay and locomotion statistics remain native.
class SwgxrVehicles {
 using Json=JSONSerializationType;
 struct Rider {uint64 vehicle=0;std::string seat;double seen=0;};
 struct Motion {double speed=0,throttle=0,steer=0,seen=0,tick=0;uint64 driver=0;};
 static auto& mutex(){static std::recursive_mutex value;return value;}
 static auto& riders(){static std::map<uint64,Rider> value;return value;}
 static auto& motions(){static std::map<uint64,Motion> value;return value;}
 static auto& ejections(){static std::map<uint64,Json> value;return value;}
 static double clamp(double v,double lo,double hi){return std::max(lo,std::min(hi,v));}
 static double now(){return std::chrono::duration<double>(std::chrono::steady_clock::now().time_since_epoch()).count();}
 static std::string id(SceneObject* o){return o?std::to_string(o->getObjectID()):"";}
 static Json wire(const Vector3& p){return Json::array({p.getX(),p.getZ(),p.getY()});}
 static Vector3 point(const Json& p){if(!p.is_array() || p.size()!=3)throw std::runtime_error("Invalid vehicle pose");for(auto& v:p)if(!v.is_number() || !std::isfinite(v.get<double>()) || std::abs(v.get<double>())>10000)throw std::runtime_error("Invalid vehicle pose");return Vector3(p[0].get<float>(),p[2].get<float>(),p[1].get<float>());}
 static Json descriptor(CreatureObject* v){
  static Json catalog=[](){std::ifstream f("/workspace/runtime/assets/vehicles/catalog.json");Json data; if(f)f>>data;return data;}();
  auto name=std::string(v->getObjectTemplate()->getFullTemplateString().toCharArray());
  if(!catalog.contains("items") || !catalog["items"].contains(name))throw std::runtime_error("Original vehicle asset not prepared");return catalog["items"][name];
 }
 static Vector3 local(CreatureObject* v,const Json& p){
  // Manifest has Godot -Z forward; Core3 is +Y forward, Z vertical.
  double x=p[0].get<double>(),y=-p[2].get<double>(),a=v->getDirection()->getRadians();
  auto w=v->getWorldPosition();return Vector3(w.getX()+x*std::cos(a)+y*std::sin(a),w.getY()-x*std::sin(a)+y*std::cos(a),w.getZ()+p[1].get<double>());
 }
 static Json seat(const Json& d,const std::string& key){for(auto& s:d["seats"])if(s["id"]==key)return s;throw std::runtime_error("Seat unavailable");}
 static VehicleControlDevice* owned(CreatureObject* c,const std::string& key){auto o=c->getZoneServer()->getObject(std::stoull(key));if(!o || !o->isVehicleControlDevice() || !o->isASubChildOf(c) || o->getParent().get()!=c->getSlottedObject("datapad"))throw std::runtime_error("Owned datapad vehicle required");return static_cast<VehicleControlDevice*>(o.get());}
 static CreatureObject* vehicle(CreatureObject* c,uint64 key){auto o=c->getZoneServer()->getObject(key);if(!o || !o->isVehicleObject() || o->getZone()!=c->getZone())throw std::runtime_error("Vehicle unavailable");return o->asCreatureObject();}
 static double turn(CreatureObject* v){auto t=dynamic_cast<SharedCreatureObjectTemplate*>(v->getObjectTemplate());auto values=t->getTurnRate();return values.size()?values.get(0)*M_PI/180.0:1.0;}
 static bool floor(CreatureObject* c,CreatureObject* v,const Vector3& before,Vector3& after){
  if(std::abs(after.getX())>8191 || std::abs(after.getY())>8191)return false;
  IntersectionResults hits;auto zone=v->getZone();auto close=(CloseObjectsVector*)v->getCloseObjects();
  CollisionManager::getWorldFloorCollisions(after.getX(),after.getY(),zone,&hits,close);
  float z=zone->getPlanetManager()->findClosestWorldFloor(after.getX(),after.getY(),before.getZ(),0,&hits,close);
  if(!std::isfinite(z) || std::abs(z-before.getZ())>.55)return false;after.setZ(z);
  // The source movement query samples 1/4 of its supplied horizontal vector.
  Vector3 probe=before+(after-before)*4;probe.setZ(z);
  return CollisionManager::checkMovementCollision(c,close,zone,before,probe);
 }
 static void place(CreatureObject* c,CreatureObject* v,const Rider& r){auto p=local(v,seat(descriptor(v),r.seat)["position"]);c->setDirection(v->getDirection()->getRadians());c->teleport(p.getX(),p.getZ(),p.getY(),0);}
 static void tick(CreatureObject* c,CreatureObject* v){
  auto it=motions().find(v->getObjectID());if(it==motions().end())return;auto& m=it->second;double stamp=now(),dt=clamp(stamp-m.tick,0.0,.4);m.tick=stamp;
  bool drive=m.driver && stamp-m.seen<.75 && !v->isDisabled();double throttle=drive?m.throttle:0;
  double maximum=std::max(0.f,v->getRunSpeed()*v->getSpeedMultiplierMod()),reverse=std::max(0.f,v->getWalkSpeed());
  double accel=std::max(.1f,v->getRunAcceleration()*v->getAccelerationMultiplierMod());
  auto d=descriptor(v);
  int steps=std::max(1,int(std::ceil(dt/.02)));double step=dt/steps;
  for(int i=0;i<steps;++i){
   double target=throttle*(throttle<0?reverse:maximum);double rate=accel*((m.speed*throttle<0 || std::abs(throttle)<.05)?2.0:1.0);
   double old=m.speed;m.speed+=clamp(target-m.speed,-rate*step,rate*step);
   if(old*target<0 && old*m.speed<0)m.speed=0; // Brake through zero before reversing.
   double a=v->getDirection()->getRadians()+(drive?m.steer:0)*turn(v)*clamp(m.speed/3.0,-1.0,1.0)*step;
   Vector3 before=v->getWorldPosition(),after=before+Vector3(std::sin(a)*m.speed*step,std::cos(a)*m.speed*step,0);
   bool clear=floor(c,v,before,after);
   // Sweep all four corners of the actual source hull, including rotation.
   // Native character-sized sweeps alone would let a long nose enter walls.
   double oldAngle=v->getDirection()->getRadians();auto close=(CloseObjectsVector*)v->getCloseObjects();
   for(double x:{d["bounds_min"][0].get<double>(),d["bounds_max"][0].get<double>()})for(double z:{d["bounds_min"][2].get<double>(),d["bounds_max"][2].get<double>()}){
    Vector3 cornerBefore=before+Vector3(x*std::cos(oldAngle)-z*std::sin(oldAngle),-x*std::sin(oldAngle)-z*std::cos(oldAngle),0);
    Vector3 cornerAfter=after+Vector3(x*std::cos(a)-z*std::sin(a),-x*std::sin(a)-z*std::cos(a),0);
    Vector3 probe=cornerBefore+(cornerAfter-cornerBefore)*4;probe.setZ(cornerAfter.getZ());
    if(!CollisionManager::checkMovementCollision(c,close,v->getZone(),cornerBefore,probe))clear=false;
   }
   if(!clear){m.speed=0;break;}
   if(std::abs(m.speed)>.0001){v->setDirection(a);v->teleport(after.getX(),after.getZ(),after.getY(),0);}
  }
  v->setCurrentSpeed(std::abs(m.speed));
  for(auto& entry:riders())if(entry.second.vehicle==v->getObjectID()){
   auto p=c->getZoneServer()->getObject(entry.first).castTo<CreatureObject*>();if(!p)continue;Locker lock(p,c);if(!p->isDead() && !p->isIncapacitated())place(p,v,entry.second);
  }
 }
 static void eject(CreatureObject* observer,CreatureObject* p,const Rider& r,const std::string& reason){
  if(!p || !p->getZone())return;Locker pl(p,observer);
  auto object=p->getZoneServer()->getObject(r.vehicle).castTo<CreatureObject*>();Vector3 exit=p->getWorldPosition();
  if(object && object->getZone()==p->getZone()){
   Locker vl(object,p);auto d=descriptor(object);auto start=object->getWorldPosition();bool found=false;
   for(double side:{r.seat=="driver"?-1.0:1.0,r.seat=="driver"?1.0:-1.0}){
    double width=std::max(std::abs(d["bounds_min"][0].get<double>()),std::abs(d["bounds_max"][0].get<double>()))+.65;
    exit=local(object,Json::array({side*width,0,0}));if(floor(p,object,start,exit)){found=true;break;}
   }
   if(!found)exit=start; // Legacy Core3 dismount fallback: ground under mount.
  }
  IntersectionResults hits;auto close=(CloseObjectsVector*)p->getCloseObjects();
  CollisionManager::getWorldFloorCollisions(exit.getX(),exit.getY(),p->getZone(),&hits,close);
  float ground=p->getZone()->getPlanetManager()->findClosestWorldFloor(exit.getX(),exit.getY(),exit.getZ(),0,&hits,close);
  if(std::isfinite(ground))exit.setZ(ground);
  p->teleport(exit.getX(),exit.getZ(),exit.getY(),0);
  static uint64 revision=0;ejections()[p->getObjectID()]={{"revision",++revision},{"reason",reason},{"position",wire(exit)},{"vehicle_id",std::to_string(r.vehicle)},{"time",now()}};
 }
 static void cleanup(CreatureObject* c){
  auto stamp=now();for(auto it=riders().begin();it!=riders().end();){auto p=c->getZoneServer()->getObject(it->first).castTo<CreatureObject*>();
   auto v=c->getZoneServer()->getObject(it->second.vehicle).castTo<CreatureObject*>();
   bool missing=!v || !p || v->getZone()==nullptr || v->getZone()!=p->getZone();
   bool lostOwner=!missing && it->second.seat=="driver" && (!v->getControlDevice().get() || !v->getControlDevice().get()->isASubChildOf(p));
   if(!p || !p->getZone() || missing || lostOwner || p->isDead() || p->isIncapacitated() || stamp-it->second.seen>4){if(p && p->getZone())eject(c,p,it->second,p->isDead()?"dead":p->isIncapacitated()?"incapacitated":missing?"vehicle_unavailable":lostOwner?"ownership_changed":"disconnected");auto m=motions().find(it->second.vehicle);if(m!=motions().end() && m->second.driver==it->first){m->second.driver=0;m->second.throttle=0;m->second.speed=0;}it=riders().erase(it);}else ++it;}
  for(auto it=ejections().begin();it!=ejections().end();)if(stamp-it->second["time"].get<double>()>120)it=ejections().erase(it);else ++it;
  for(auto it=motions().begin();it!=motions().end();)if(stamp-it->second.tick>60 && !it->second.driver)it=motions().erase(it);else ++it;
 }
 static Json describe(CreatureObject* c,CreatureObject* v){
  auto d=descriptor(v);Json seats=Json::array();for(auto& s:d["seats"]){auto out=s;out["occupant_id"]="";for(auto& entry:riders())if(entry.second.vehicle==v->getObjectID() && entry.second.seat==s["id"])out["occupant_id"]=std::to_string(entry.first);seats.push_back(out);}
  auto cd=v->getControlDevice().get();auto m=motions().find(v->getObjectID());
  return {{"id",id(v)},{"template",std::string(v->getObjectTemplate()->getFullTemplateString().toCharArray())},{"name",std::string(v->getDisplayedName().toCharArray())},{"position",wire(v->getWorldPosition())},{"heading_radians",v->getDirection()->getRadians()},{"owned",cd && cd->isASubChildOf(c)},{"device_id",cd?id(cd):""},{"disabled",v->isDisabled()},{"kind",d["kind"]},{"seats",seats},{"controls",d["controls"]},{"speed",m==motions().end()?0:m->second.speed},{"max_speed",v->getRunSpeed()*v->getSpeedMultiplierMod()},{"reverse_speed",v->getWalkSpeed()},{"acceleration",v->getRunAcceleration()*v->getAccelerationMultiplierMod()},{"turn_rate",turn(v)},{"condition",v->getMaxCondition()-v->getConditionDamage()},{"max_condition",v->getMaxCondition()}};
 }
public:
 static double launchReach(CreatureObject* c){std::lock_guard<std::recursive_mutex> lock(mutex());auto r=riders().find(c->getObjectID());if(r==riders().end())return 3.5;auto m=motions().find(r->second.vehicle);return 3.5+(m==motions().end()?0:std::abs(m->second.speed)*.75);}
 static bool seated(CreatureObject* c){std::lock_guard<std::recursive_mutex> lock(mutex());return riders().count(c->getObjectID());}
 static void detach(CreatureObject* c,bool forced=true){std::lock_guard<std::recursive_mutex> lock(mutex());auto it=riders().find(c->getObjectID());if(it!=riders().end()){auto& m=motions()[it->second.vehicle];if(m.driver==c->getObjectID()){m.speed=0;m.throttle=0;m.driver=0;}if(forced)eject(c,c,it->second,"disconnected");riders().erase(it);}}
 static bool update(CreatureObject* c,const Json& input){
  std::lock_guard<std::recursive_mutex> lock(mutex());auto it=riders().find(c->getObjectID());if(it==riders().end())return false;it->second.seen=now();cleanup(c);it=riders().find(c->getObjectID());if(it==riders().end())return false;
  auto v=vehicle(c,it->second.vehicle);Locker vl(v,c);auto& m=motions()[v->getObjectID()];
  if(it->second.seat=="driver"){
   double throttle=input.value("throttle",0.0),steer=input.value("steer",0.0);if(!std::isfinite(throttle) || !std::isfinite(steer) || std::abs(throttle)>1 || std::abs(steer)>1)throw std::runtime_error("Invalid vehicle controls");
   bool held=input.value("held",false);m.driver=c->getObjectID();m.throttle=held?throttle:0;m.steer=held?steer:0;m.seen=now();
  }
  tick(c,v);place(c,v,it->second);return true;
 }
 static Json snapshot(CreatureObject* c){
  std::lock_guard<std::recursive_mutex> lock(mutex());auto ownSeen=riders().find(c->getObjectID());if(ownSeen!=riders().end())ownSeen->second.seen=now();cleanup(c);Json out={{"character_id",id(c)},{"source_kind","core3_vehicles"},{"vehicles",Json::array()},{"datapad",Json::array()},{"seat",Json::object()},{"position",wire(c->getWorldPosition())}};
  auto ejection=ejections().find(c->getObjectID());if(ejection!=ejections().end())out["forced_exit"]=ejection->second;
  auto own=riders().find(c->getObjectID());if(own!=riders().end())out["seat"]={{"vehicle_id",std::to_string(own->second.vehicle)},{"id",own->second.seat}};
  auto pad=c->getSlottedObject("datapad");if(pad)for(int i=0;i<pad->getContainerObjectsSize() && out["datapad"].size()<32;++i){auto item=pad->getContainerObject(i);if(!item->isVehicleControlDevice())continue;auto cd=static_cast<VehicleControlDevice*>(item.get());auto controlled=cd->getControlledObject();if(!controlled || !controlled->isVehicleObject())continue;auto v=controlled->asCreatureObject();
   try{descriptor(v);}catch(...){continue;}
   out["datapad"].push_back({{"id",id(cd)},{"vehicle_id",id(v)},{"name",std::string(v->getDisplayedName().toCharArray())},{"template",std::string(v->getObjectTemplate()->getFullTemplateString().toCharArray())},{"spawned",v->getZone()!=nullptr}});
  }
  SortedVector<TreeEntry*> objects(128,128);c->getZone()->getInRangeObjects(c->getWorldPositionX(),c->getWorldPositionZ(),c->getWorldPositionY(),128,&objects,true);
  for(int i=0;i<objects.size() && out["vehicles"].size()<32;++i){auto o=static_cast<SceneObject*>(objects.get(i));if(!o->isVehicleObject())continue;auto v=o->asCreatureObject();Locker vl(v,c);try{descriptor(v);tick(c,v);out["vehicles"].push_back(describe(c,v));}catch(const std::exception&){} }
  out["position"]=wire(c->getWorldPosition());return out;
 }
 static Json run(CreatureObject* c,const Json& q){
  std::lock_guard<std::recursive_mutex> lock(mutex());if(!c || !c->getZone() || !c->getPlayerObject())throw std::runtime_error("Native player required");cleanup(c);
  auto action=q.value("action",std::string("status"));Json mutation={{"success",true},{"action",action}};
  if(action=="call"){
   if(c->isDead() || c->isIncapacitated() || c->getParent().get()!=nullptr || c->isInCombat())throw std::runtime_error("Call a vehicle while alive, outside and at peace");
   if(seated(c))throw std::runtime_error("Dismount first");auto cd=owned(c,q.at("device_id").get<std::string>());auto controlled=cd->getControlledObject();if(!controlled || !controlled->isVehicleObject())throw std::runtime_error("Invalid native vehicle");descriptor(controlled->asCreatureObject());cd->generateObject(c);if(controlled->getZone()==nullptr && c->getPendingTask("call_mount")==nullptr)throw std::runtime_error("Core3 could not call this vehicle");mutation["pending"]=controlled->getZone()==nullptr;
  }else if(action=="board"){
   if(c->isDead() || c->isIncapacitated() || c->getParent().get()!=nullptr || c->isRidingMount() || seated(c))throw std::runtime_error("Player cannot board");
   auto v=vehicle(c,std::stoull(q.at("vehicle_id").get<std::string>()));Locker vl(v,c);auto name=q.at("seat").get<std::string>();auto d=descriptor(v);auto s=seat(d,name);auto& m=motions()[v->getObjectID()];
   if(v->isDisabled() || std::abs(m.speed)>.25 || !c->isInRange(v,7) || !CollisionManager::checkLineOfSight(c,v))throw std::runtime_error("Park within reach to board");
   auto cd=v->getControlDevice().get();if(!cd || (name=="driver" && !cd->isASubChildOf(c)))throw std::runtime_error("Only owner can drive");
   auto owner=c->getZoneServer()->getObject(v->getCreatureLinkID()).castTo<CreatureObject*>();if(owner && c->isAttackableBy(owner))throw std::runtime_error("Hostile passengers cannot board");
   for(auto& r:riders())if(r.second.vehicle==v->getObjectID() && r.second.seat==name)throw std::runtime_error("Seat occupied");
   auto hand=point(q.at("hand"));if(hand.distanceTo(c->getWorldPosition())>3.5 || hand.distanceTo(local(v,s["position"]))>.32)throw std::runtime_error("Touch intended seat to board");
   Rider r;r.vehicle=v->getObjectID();r.seat=name;r.seen=now();riders()[c->getObjectID()]=r;ejections().erase(c->getObjectID());m.tick=now();if(name=="driver")m.driver=c->getObjectID();place(c,v,r);
  }else if(action=="dismount"){
   auto it=riders().find(c->getObjectID());if(it!=riders().end()){
    auto v=vehicle(c,it->second.vehicle);Locker vl(v,c);auto d=descriptor(v);Vector3 exit;bool found=false;auto start=v->getWorldPosition();
    for(double side:{-1.0,1.0}){double width=std::max(std::abs(d["bounds_min"][0].get<double>()),std::abs(d["bounds_max"][0].get<double>()))+.65;exit=local(v,Json::array({side*width,0,0}));if(floor(c,v,start,exit)){found=true;break;}}
    if(!found)throw std::runtime_error("No clear dismount position");detach(c,false);c->teleport(exit.getX(),exit.getZ(),exit.getY(),0);mutation["position"]=wire(exit);
   }
  }else if(action=="store"){
   auto cd=owned(c,q.at("device_id").get<std::string>());auto controlled=cd->getControlledObject();if(!controlled || !controlled->isVehicleObject() || controlled->getZone()!=c->getZone())throw std::runtime_error("Parked owned vehicle required");auto v=controlled->asCreatureObject();Locker vl(v,c);auto& m=motions()[v->getObjectID()];
   for(auto& r:riders())if(r.second.vehicle==v->getObjectID())throw std::runtime_error("Occupied vehicle cannot be stored");
   if(std::abs(m.speed)>.1 || c->isInCombat() || !c->isInRange(v,7) || !CollisionManager::checkLineOfSight(c,v))throw std::runtime_error("Parked vehicle within reach required");auto d=descriptor(v);
   for(auto key:{"left","right"}){auto h=point(q.at(key));if(h.distanceTo(c->getWorldPosition())>3.5)throw std::runtime_error("Both hands must touch vehicle");auto rel=h-v->getWorldPosition();double a=v->getDirection()->getRadians(),x=rel.getX()*std::cos(a)-rel.getY()*std::sin(a),z=-(rel.getX()*std::sin(a)+rel.getY()*std::cos(a));double vals[]={x,rel.getZ(),z};for(int i=0;i<3;++i)if(vals[i]<d["bounds_min"][i].get<double>()-.15 || vals[i]>d["bounds_max"][i].get<double>()+.15)throw std::runtime_error("Both hands must touch vehicle");}
   vl.release();cd->storeObject(c);if(v->getZone()!=nullptr)throw std::runtime_error("Core3 refused vehicle storage");motions().erase(v->getObjectID());
  }else if(action!="status")throw std::runtime_error("Unsupported vehicle action");
  return {{"backend","core3"},{"source_kind","core3_vehicles"},{"character_id",id(c)},{"state",snapshot(c)},{"mutation",mutation}};
 }
};
#endif
