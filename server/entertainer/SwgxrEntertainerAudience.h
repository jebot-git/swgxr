#ifndef SWGXR_ENTERTAINER_AUDIENCE_H
#define SWGXR_ENTERTAINER_AUDIENCE_H
#include "server/zone/Zone.h"
#include "server/zone/managers/player/PlayerManager.h"
#include "server/zone/managers/collision/CollisionManager.h"
#include "server/zone/objects/player/sessions/EntertainingSession.h"

// Radius membership uses the existing native session and its single patron
// channel per performance kind. No client presence, target selector or new timer
// can accrue or deliver benefits. The original session owns costs and effects.
class SwgxrEntertainerAudience {
public:
 static constexpr float RADIUS = 8.f;
 static constexpr int MINIMUM_SECONDS = 60;
 static constexpr int REFRESH_SECONDS = 10;
 static bool available(CreatureObject* creature) {
  return creature && creature->isPlayerCreature() && creature->getZone() &&
   creature->isOnline() && !creature->isDead() && !creature->isIncapacitated() &&
   !creature->isInCombat() && !creature->isInvisible();
 }
 static uint64 sourceID(CreatureObject* patron,bool dancing) {
  return dancing?patron->getWatchToID():patron->getListenID();
 }
 static bool eligible(CreatureObject* performer,CreatureObject* patron,EntertainingSession* session) {
  if(!available(performer) || !available(patron) || performer==patron || !session ||
   (!session->isDancing() && !session->isPlayingMusic()) || !session->canGiveEntertainBuff() ||
   patron->isDancing() || patron->isPlayingMusic() ||
   performer->getZone()!=patron->getZone() || performer->getParentID()!=patron->getParentID() ||
   !performer->isInRange(patron,RADIUS) || session->isInDenyServiceList(patron) ||
   patron->isAttackableBy(performer) || !patron->isHealableBy(performer)) return false;
  return CollisionManager::checkLineOfSight(performer,patron);
 }
 static void detach(CreatureObject* performer,CreatureObject* patron,EntertainingSession* session,bool dancing) {
  // Never redirect native stopWatch/stopListen to an unrelated newer source.
  if(sourceID(patron,dancing)==performer->getObjectID()) {
   auto manager=performer->getZoneServer()->getPlayerManager();
   if(dancing)manager->stopWatch(patron,performer->getObjectID(),true,false,false,true);
   else manager->stopListen(patron,performer->getObjectID(),true,false,false,true);
  }
  session->removePatron(patron);
 }
 static void synchronize(CreatureObject* performer,EntertainingSession* session) {
  if(!performer || !session || !performer->getZone())return;
  const bool dancing=session->isDancing();
  // Snapshot iteration remains valid when native stop removes several patrons.
  auto patrons=session->getPatrons();
  for(int i=0;i<patrons.size();++i) {
   auto patron=patrons.get(i);
   if(!patron)continue;
   Locker locker(patron,performer);
   if(!eligible(performer,patron,session) || sourceID(patron,dancing)!=performer->getObjectID())
    detach(performer,patron,session,dancing);
  }
  if(!available(performer) || (!session->isDancing() && !session->isPlayingMusic()) || !session->canGiveEntertainBuff())return;
  SortedVector<TreeEntry*> nearby(64,64);
  auto position=performer->getWorldPosition();
  performer->getZone()->getInRangeObjects(position.getX(),position.getZ(),position.getY(),RADIUS,&nearby,true);
  auto manager=performer->getZoneServer()->getPlayerManager();
  for(int i=0;i<nearby.size();++i) {
   auto object=static_cast<SceneObject*>(nearby.get(i));
   if(!object || !object->isPlayerCreature())continue;
   auto patron=object->asCreatureObject();
   Locker locker(patron,performer);
   // The current source owns cleanup on its tick/stop path. Do not read or
   // lock a third performer while holding this performer and the patron.
   if(!eligible(performer,patron,session) || sourceID(patron,dancing)!=0)continue;
   if(dancing)manager->startWatch(patron,performer->getObjectID());
   else manager->startListen(patron,performer->getObjectID());
  }
 }
 static void deliver(CreatureObject* performer,CreatureObject* patron,EntertainingSession* session,int performanceType) {
  if(!eligible(performer,patron,session) || sourceID(patron,session->isDancing())!=performer->getObjectID())return;
  if(time(0)-session->getEntertainerBuffStartTime(patron,performanceType)>=MINIMUM_SECONDS)
   session->activateEntertainerBuff(patron,performanceType);
 }
};
#endif
