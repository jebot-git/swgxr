#pragma once
#include <array>
#include "server/zone/managers/collision/CollisionManager.h"
// Shared native blast-centre occlusion for certified explosives.
class SwgxrBlastSight {
public:
 static bool clear(CreatureObject* c,TangibleObject* a,const std::array<double,3>& p){
  Vector3 origin(float(p[0]),float(p[2]),float(p[1])+.2f),end=a->getWorldPosition();end.set(end.getX(),end.getY(),end.getZ()+(a->isCreatureObject()?CollisionManager::getRayOriginPoint(a->asCreatureObject()):.8f));double length=origin.distanceTo(end);
  auto parent=a->getParent().get();
  if(parent && parent->isCellObject()){
   auto building=parent->getRootParent();auto layout=building?building->getObjectTemplate()->getPortalLayout():nullptr;int cell=static_cast<CellObject*>(parent.get())->getCellNumber();
   if(!layout || cell<0 || cell>=layout->getAppearanceTemplatesSize())return false;
   auto app=layout->getAppearanceTemplate(cell);if(!app)return false;auto ray=CollisionManager::convertToModelSpace(origin,end,building);float at;Triangle* triangle=nullptr;
   return !app->intersects(ray,length,at,triangle,true);
  }
  SortedVector<TreeEntry*> nearby(64,64);c->getZone()->getInRangeObjects(float(p[0]),float(p[1]),float(p[2]),128,&nearby,true);
  try{for(int i=0;i<nearby.size();++i){auto o=static_cast<SceneObject*>(nearby.get(i));if(o==a || o==c)continue;auto app=CollisionManager::getCollisionAppearance(o,255);if(!app)continue;auto ray=CollisionManager::convertToModelSpace(origin,end,o);float at;Triangle* triangle=nullptr;if(app->intersects(ray,length,at,triangle,true))return false;}}catch(...){return false;}
  return true;
 }
};
