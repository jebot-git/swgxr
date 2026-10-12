#pragma once
#include "FlightCollisionPolicy.h"
#include "templates/appearance/AppearanceTemplate.h"
#include "server/zone/objects/ship/ShipObject.h"
#include "server/zone/Zone.h"
#include <fstream>
// Original native object volumes plus deterministic original asteroid extents.
// The private sector file is produced from the same source seed as the renderer.
class SwgxrFlightCollision {
 using Vec=swgxr::jtl::Vec;
 using Json=JSONSerializationType;
 struct Rock {Vec point;double radius;};
 static const std::map<std::string,std::vector<Rock>>& fields(){
  static const auto data=[](){std::map<std::string,std::vector<Rock>> out;
   std::ifstream input("conf/swgxr-space-collision.json");if(!input)return out;
   Json file;input>>file;for(auto it=file.at("sectors").begin();it!=file.at("sectors").end();++it)
    for(auto& row:it.value())out[it.key()].push_back({row.at("position").get<Vec>(),row.at("radius").get<double>()});
   return out;
  }();return data;
 }
 static bool sphereOverlap(const Vector3& p,double r,const Sphere& sphere){return p.squaredDistanceTo(sphere.getCenter())<=Math::sqr(r+sphere.getRadius());}
 static bool boxOverlap(const Vector3& p,double r,const AABB& box){auto lo=box.getMinBound(),hi=box.getMaxBound();double sum=0;for(int k=0;k<3;++k){double d=p[k]-swgxr::jtl::clamp(p[k],(*lo)[k],(*hi)[k]);sum+=d*d;}return sum<=r*r;}
public:
 static bool ready(const std::string& zone){return fields().count(zone)!=0;}
 struct Hit {double fraction=1;std::string object;};
 static Hit sweep(ShipObject* ship,const Vec& from,const Vec& to){
  Hit hit;auto zone=ship->getZone();if(!zone)return hit;
  double radius=std::max(.5,double(ship->getBoundingRadius()));
  auto all=fields().find(zone->getZoneName().toCharArray());
  if(all!=fields().end())for(auto& rock:all->second){double f=swgxr::jtl::sphereSweep(from,to,rock.point,radius+rock.radius);if(f<hit.fraction)hit={f,"asteroid"};}
  SortedVector<ManagedReference<TreeEntry*>> objects(128,128);
  zone->getInRangeObjects(from[0],from[1],from[2],swgxr::jtl::length(swgxr::jtl::sub(to,from))+radius+2048,&objects,true);
  for(int i=0;i<objects.size();++i){auto object=static_cast<SceneObject*>(objects.get(i).get());if(!object || object==ship || object->getParentID()!=0)continue;
   auto type=object->getGameObjectType();if(!object->isShipObject() && type!=SceneObjectType::ASTEROID && type!=SceneObjectType::SPACEOBJECT)continue;
   auto appearance=object->getAppearanceTemplate();if(!appearance || !appearance->getBoundingVolume())continue;
   Vec center{{object->getPositionX(),object->getPositionZ(),object->getPositionY()}};
   auto bounds=appearance->getBoundingVolume()->getBoundingSphere();double broad=radius+bounds.getRadius()+bounds.getCenter().length();
   if(swgxr::jtl::sphereSweep(from,to,center,broad)>=1 && swgxr::jtl::length(swgxr::jtl::sub(from,center))>broad)continue;
   Matrix4 rotation;rotation.setRotationMatrix(object->getDirection()->toMatrix3());
   auto volume=appearance->getCollisionVolume();
   auto overlaps=[&](const Vec& point,double r){Vector3 p(point[0]-center[0],point[1]-center[1],point[2]-center[2]);p=p*rotation;
    if(volume && volume->isBoundingSphere())return sphereOverlap(p,r,volume->getBoundingSphere());
    if(volume && volume->isBoundingBox())return boxOverlap(p,r,volume->getBoundingBox());
    return appearance->testCollide(Sphere(p,r));
   };
   // An initial overlap may be a launch/undock placement; let it separate.
   if(overlaps(from,radius) && swgxr::jtl::dot(swgxr::jtl::sub(from,center),swgxr::jtl::sub(to,from))>=0)continue;
   double f=swgxr::jtl::volumeSweep(from,to,radius,overlaps);if(f<hit.fraction)hit={f,std::to_string(object->getObjectID())};
  }
  return hit;
 }
};
