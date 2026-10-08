#ifndef SWGXR_PARTY_POLICY_H
#define SWGXR_PARTY_POLICY_H
#include "server/zone/objects/creature/CreatureObject.h"
#include "server/zone/objects/group/GroupObject.h"
// Existing GroupObject remains membership, leadership, modifier and chat authority.
class SwgxrPartyPolicy {
public:
 static bool squadLeader(CreatureObject* c){return c && c->isPlayerCreature() && c->hasSkill("outdoors_squadleader_novice");}
 static CreatureObject* initialLeader(CreatureObject* a,CreatureObject* b){
  if(squadLeader(a)!=squadLeader(b))return squadLeader(a)?a:b;
  if(a->getLevel()!=b->getLevel())return a->getLevel()>b->getLevel()?a:b;
  return a->getObjectID()<b->getObjectID()?a:b;
 }
 // Pre: group locked. Preserve ordinary incumbent; choose strongest SL, retain
 // current SL on equal CL, then use object ID as stable final tie breaker.
 static CreatureObject* preferredSquadLeader(GroupObject* group){
  auto incumbent=group->getLeader();CreatureObject* best=squadLeader(incumbent)?incumbent:nullptr;
  for(int i=0;i<group->getGroupSize();++i){auto member=group->getGroupMember(i);if(!squadLeader(member))continue;
   if(!best || member->getLevel()>best->getLevel() || (member->getLevel()==best->getLevel() && best!=incumbent && member->getObjectID()<best->getObjectID()))best=member;
  }return best;
 }
 static void reconcile(GroupObject* group){
  if(!group || group->getGroupSize()<2)return;auto best=preferredSquadLeader(group);
  if(best && best!=group->getLeader()){Locker lock(best,group);group->makeLeader(best);}
 }
};
#endif
