#pragma once
#include <deque>
#include <mutex>
#include <chrono>
// Bounded presentation receipts emitted by the actual native combat manager.
// They never feed back into collision, damage, threat attribution or loot rolls.
class SwgxrSpaceEvents {
 using Json=JSONSerializationType;
 struct Event {uint64 id;double stamp;std::string zone;Vector3 position;Json data;};
 struct Store {std::mutex mutex;std::deque<Event> events;uint64 next=0;};
 static Store& store(){static Store value;return value;}
 static double now(){return std::chrono::duration<double>(std::chrono::steady_clock::now().time_since_epoch()).count();}
 static Json vector(const Vector3& v){return Json::array({v.getX(),v.getZ(),v.getY()});}
 static void push(ShipObject* ship,const Vector3& position,Json data){
  if(!ship || !ship->getZone())return;auto& s=store();std::lock_guard<std::mutex> lock(s.mutex);double stamp=now();
  data["id"]=std::to_string(++s.next);data["ship_id"]=std::to_string(ship->getObjectID());data["position"]=vector(position);
  while(!s.events.empty() && (s.events.size()>=1024 || stamp-s.events.front().stamp>5))s.events.pop_front();
  s.events.push_back({s.next,stamp,ship->getZone()->getZoneName().toCharArray(),position,data});
 }
public:
 static void projectile(ShipObject* ship,const ShipProjectile* p){if(p)push(ship,p->getThisPosition(),{{"kind","projectile"},{"direction",vector(p->getDirection())},{"speed",p->getSpeed()},{"range",p->getRange()},{"projectile_type",p->getProjectileType()}});}
 static void missile(ShipObject* ship,const ShipMissile* p,bool done=false){if(p)push(ship,p->getThisPosition(),{{"kind","missile"},{"missile_id",std::to_string(p->getUniqueID())},{"done",done}});}
 static void hit(ShipObject* ship,const Vector3& position,int type){push(ship,position,{{"kind","hit"},{"hit_type",type}});}
 static Json snapshot(ShipObject* observer){
  Json out=Json::array();if(!observer || !observer->getZone())return out;auto& s=store();std::lock_guard<std::mutex> lock(s.mutex);double stamp=now();
  for(auto it=s.events.rbegin();it!=s.events.rend() && out.size()<128;++it){if(stamp-it->stamp>5)break;if(it->zone!=observer->getZone()->getZoneName().toCharArray() || it->position.squaredDistanceTo(observer->getPosition())>4096.f*4096.f)continue;auto row=it->data;row["age_seconds"]=stamp-it->stamp;out.push_back(row);}return out;
 }
};
