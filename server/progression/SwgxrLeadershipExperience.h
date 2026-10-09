#ifndef SWGXR_LEADERSHIP_EXPERIENCE_H
#define SWGXR_LEADERSHIP_EXPERIENCE_H
#include "LeadershipExperiencePolicy.h"
#include "server/zone/objects/creature/CreatureObject.h"
#include "server/zone/objects/group/GroupObject.h"
#include "server/zone/objects/player/PlayerObject.h"
#include "server/zone/managers/player/PlayerManager.h"
#include "server/zone/ZoneServer.h"
#include <vector>
// Reward source is native cap-clamped XP, never a client receipt or damage claim.
class SwgxrLeadershipExperience {
 static bool eligible(CreatureObject* source,CreatureObject* leader,GroupObject* group){
  if(!source || !leader || source==leader || !group || !leader->isPlayerCreature() || !leader->isOnline() || leader->getZone()==nullptr || leader->getZone()!=source->getZone() || leader->getGroup()!=group || source->getGroup()!=group || !leader->hasSkill("outdoors_squadleader_novice"))return false;
  auto a=source->getPlayerObject();auto b=leader->getPlayerObject();return a && b && a->getAccountID()!=b->getAccountID();
 }
public:
 static void earned(CreatureObject* source,const String& xpType,int actualEarned){
  if(!source || actualEarned<=0 || !LeadershipExperiencePolicy::source(xpType.toCharArray()) || !source->isPlayerCreature())return;
  ManagedReference<GroupObject*> group=source->getGroup();if(!group)return;
  ManagedReference<CreatureObject*> earner=source;
  // Capture recipients at earning time. New joiners cannot claim older awards.
  std::vector<ManagedReference<CreatureObject*>> recipients;
  {Locker groupLock(group,source);for(int i=0;i<group->getGroupSize();++i){auto member=group->getGroupMember(i);if(eligible(source,member,group))recipients.push_back(member);}}
  if(recipients.empty())return;
  // PlayerManager callers can hold victim/player locks. Defer cross-player writes
  // to avoid acquiring party member locks while those combat locks are held.
  Core::getTaskManager()->executeTask([earner,group,recipients,actualEarned](){
   Locker sourceLock(earner);
   for(const auto& member:recipients){Locker memberLock(member,earner);if(!eligible(earner,member,group))continue;
    auto ghost=member->getPlayerObject();auto saved=ghost->getScreenPlayData("swgxr_leadership","tenths");int remainder=0;
    if(saved.length()==1 && saved.charAt(0)>='0' && saved.charAt(0)<='9')remainder=saved.charAt(0)-'0';
    int award=LeadershipExperiencePolicy::share(actualEarned,remainder);
    ghost->setScreenPlayData("swgxr_leadership","tenths",String(std::to_string(remainder).c_str()));
    if(award>0)member->getZoneServer()->getPlayerManager()->awardExperience(member,"squadleader",award,true,1.f,false,false);
   }
  },"SwgxrLeadershipExperience");
 }
};
#endif
