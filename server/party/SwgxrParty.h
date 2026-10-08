#ifndef SWGXR_PARTY_H
#define SWGXR_PARTY_H
#include "SwgxrPartyPolicy.h"
#include "server/zone/managers/group/GroupManager.h"
#include "server/zone/managers/collision/CollisionManager.h"
#include "server/zone/objects/player/PlayerObject.h"
class SwgxrParty {
 using Json=JSONSerializationType;
public:
 static Json snapshot(CreatureObject* c){
  Json out={{"id","0"},{"leader_id","0"},{"members",Json::array()}};auto group=c->getGroup();if(!group)return out;
  Locker lock(group,c);SwgxrPartyPolicy::reconcile(group);
  out["id"]=std::to_string(group->getObjectID());out["leader_id"]=std::to_string(group->getLeaderID());
  for(int i=0;i<group->getGroupSize();++i){auto member=group->getGroupMember(i);if(member && member->isPlayerCreature())out["members"].push_back({{"id",std::to_string(member->getObjectID())},{"name",std::string(member->getFirstName().toCharArray())},{"combat_level",member->getLevel()},{"squad_leader",SwgxrPartyPolicy::squadLeader(member)}});}
  return out;
 }
 // Caller owns actor lock. Native joinGroup expressly requires no locks. Keep
 // references alive and restore the caller lock on every success/error path.
 static void bump(CreatureObject* actor,const Json& q){
  if(!q.value("group_bump_authorized",false))throw std::runtime_error("mutual_fist_bump_required");
  ManagedReference<CreatureObject*> peer=actor->getZoneServer()->getObject(std::stoull(q.at("target_id").get<std::string>())).castTo<CreatureObject*>();
  if(!peer || peer==actor || !peer->isPlayerCreature())throw std::runtime_error("nearby_group_player_required");
  actor->unlock();
  try{
   ManagedReference<CreatureObject*> inviter,joiner;
   {
    Locker lock(actor);Locker peerLock(peer,actor);
    if(actor->isDead() || actor->isIncapacitated() || peer->isDead() || peer->isIncapacitated() || actor->isInCombat() || peer->isInCombat())throw std::runtime_error("native_player_unavailable");
    if(peer->getZone()!=actor->getZone() || peer->getParentID()!=actor->getParentID() || !actor->isInRange(peer,3) || !CollisionManager::checkLineOfSight(actor,peer))throw std::runtime_error("nearby_group_player_required");
    if(actor->getPlayerObject()->isIgnoring(peer->getFirstName()) || peer->getPlayerObject()->isIgnoring(actor->getFirstName()))throw std::runtime_error("group_player_ignored");
    if(actor->isGrouped() && peer->isGrouped()){
     if(actor->getGroupID()!=peer->getGroupID())throw std::runtime_error("cannot_merge_existing_parties");
    }else if(actor->isGrouped() || peer->isGrouped()){
     auto member=actor->isGrouped()?actor:peer.get();auto group=member->getGroup();Locker groupLock(group,actor);
     if(group->getGroupSize()>=20)throw std::runtime_error("native_group_full");
     inviter=group->getLeader();joiner=actor->isGrouped()?peer.get():actor;
    }else{inviter=SwgxrPartyPolicy::initialLeader(actor,peer);joiner=inviter==actor?peer.get():actor;}
   }
   if(inviter && joiner){
    {Locker lock(inviter);GroupManager::instance()->inviteToGroup(inviter,joiner);if(joiner->getGroupInviterID()!=inviter->getObjectID())throw std::runtime_error("native_group_invitation_rejected");}
    GroupManager::instance()->joinGroup(joiner);
    if(!actor->isGrouped() || actor->getGroupID()!=peer->getGroupID())throw std::runtime_error("native_group_join_rejected");
   }
  }catch(...){actor->wlock();throw;}
  actor->wlock();
 }
};
#endif
