#ifndef SWGXR_MEDIC_DRAG_H
#define SWGXR_MEDIC_DRAG_H
#include "SwgxrVitalFeedback.h"
#include "server/zone/managers/collision/CollisionManager.h"
class SwgxrMedicDrag {
 using Json=JSONSerializationType;
 static Json load(CreatureObject* c){auto s=c->getPlayerObject()->getScreenPlayData("swgxr_medic","drag");return s.isEmpty()?Json::object():Json::parse(s.toCharArray());}
 static void save(CreatureObject* c,const Json& s){c->getPlayerObject()->setScreenPlayData("swgxr_medic","drag",String(s.dump().c_str()));}
 static Vector3 point(const Json& p){if(!p.is_array() || p.size()!=3)throw std::runtime_error("Invalid hand pose");for(auto& v:p)if(!v.is_number() || !std::isfinite(v.get<double>()) || std::abs(v.get<double>())>10000)throw std::runtime_error("Invalid hand pose");return Vector3(p[0].get<float>(),p[2].get<float>(),p[1].get<float>());}
 static Json wire(const Vector3& p){return Json::array({p.getX(),p.getZ(),p.getY()});}
public:
 static void observe(CreatureObject* c,const Json& q){
  auto s=load(c);auto stamp=SwgxrVitalFeedback::now();bool tracked=q.value("tracked",false);auto l=point(q.at("left")),r=point(q.at("right"));
  if(l.distanceTo(c->getWorldPosition())>3.5 || r.distanceTo(c->getWorldPosition())>3.5)tracked=false;
  s["seen"]=stamp;s["blocked"]=!tracked || q.value("crossed",true);s["grips"]=tracked && q.value("grips",false);s["left"]=wire(l);s["right"]=wire(r);
  if(s["blocked"].get<bool>()){s["owner"]="";s["lease"]=0;}
  save(c,s);
 }
 static Json snapshot(CreatureObject* c){auto s=load(c);auto stamp=SwgxrVitalFeedback::now();return {{"blocked",s.value("blocked",true) || stamp-s.value("seen",0.0)>2.0},{"owner",stamp<s.value("lease",0.0)?s.value("owner",std::string()):""},{"revision",s.value("revision",uint64(0))},{"position",wire(c->getWorldPosition())}};}
 static Json run(CreatureObject* c,const Json& q){
  if(!c->hasSkill("science_medic_injury_speed_02") || c->isIncapacitated() || c->isDead())throw std::runtime_error("Native drag skill and conscious doctor required");
  auto id=q.at("target_id").get<std::string>();auto t=c->getZoneServer()->getObject(std::stoull(id)).castTo<CreatureObject*>();
  if(!t || t==c || !t->isPlayerCreature() || t->getZone()!=c->getZone())throw std::runtime_error("Invalid drag target");
  Locker lock(t,c);auto own=load(c),patient=load(t);auto stamp=SwgxrVitalFeedback::now();auto owner=std::to_string(c->getObjectID());
  if(q.value("release",false)){if(patient.value("owner",std::string())==owner){patient["owner"]="";patient["lease"]=0;save(t,patient);}return {{"success",true}};}
  if(!t->isIncapacitated() || t->isDead() || t->getPlayerObject()->isOffline() || !t->isHealableBy(c) || t->isAttackableBy(c))throw std::runtime_error("Only eligible incapacitated players can be dragged");
  if(patient.value("blocked",true) || stamp-patient.value("seen",0.0)>2 || !own.value("grips",false) || stamp-own.value("seen",0.0)>2)throw std::runtime_error("Drag stopped by crossed arms, released hands or stale tracking");
  if(c->getParent().get()!=t->getParent().get() || !c->isInRange(t,3) || !CollisionManager::checkLineOfSight(c,t))throw std::runtime_error("Drag target obstructed or out of reach");
  if(patient.value("lease",0.0)>stamp && patient.value("owner",std::string())!=owner)throw std::runtime_error("Patient already being dragged");
  auto l=point(own.at("left")),r=point(own.at("right"));auto mid=(l+r)*.5f;
  bool start=patient.value("owner",std::string())!=owner || stamp>patient.value("lease",0.0);
  if(start){
   // Client contacts use original avatar bounds; native bounds also reject remote grabs.
   if(l.distanceTo(t->getWorldPosition())>2.2 || r.distanceTo(t->getWorldPosition())>2.2)throw std::runtime_error("Both hands must touch the patient");
  }else{
   auto delta=mid-point(patient.at("midpoint"));auto elapsed=stamp-patient.value("moved",stamp);
   if(delta.length()>std::min(1.5,elapsed*3+.10))throw std::runtime_error("Drag movement exceeds physical reach");
   Vector3 before=t->getWorldPosition(),after=before+delta;
   if(t->getParent().get()!=nullptr)throw std::runtime_error("Native indoor drag floors unavailable");
   IntersectionResults intersections;CollisionManager::getWorldFloorCollisions(after.getX(),after.getY(),t->getZone(),&intersections,(CloseObjectsVector*)t->getCloseObjects());
   float z=t->getZone()->getPlanetManager()->findClosestWorldFloor(after.getX(),after.getY(),before.getZ(),0,&intersections,(CloseObjectsVector*)t->getCloseObjects());
   if(!std::isfinite(z) || std::abs(z-before.getZ())>.4)throw std::runtime_error("Drag floor is not traversable");after.setZ(z);
   // Native movement query samples a quarter of its supplied horizontal segment.
   Vector3 probe=before+(after-before)*4;probe.setZ(z);
   if(!CollisionManager::checkMovementCollision(t,(CloseObjectsVector*)t->getCloseObjects(),t->getZone(),before,probe))throw std::runtime_error("Drag movement blocked");
   if(after.distanceTo(before)>.001){t->teleport(after.getX(),after.getZ(),after.getY(),0);patient["revision"]=patient.value("revision",uint64(0))+1;}
  }
  patient["owner"]=owner;patient["lease"]=stamp+1.5;patient["midpoint"]=wire(mid);patient["moved"]=stamp;save(t,patient);
  return {{"success",true},{"target_id",id},{"started",start},{"position",wire(t->getWorldPosition())}};
 }
};
#endif
