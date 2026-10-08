#ifndef SWGXR_SLICING_REWARDS_H
#define SWGXR_SLICING_REWARDS_H
#include "server/zone/objects/creature/CreatureObject.h"
#include "server/zone/objects/player/PlayerObject.h"
#include "server/zone/objects/group/GroupObject.h"
#include "server/zone/objects/mission/MissionObject.h"
#include "server/zone/objects/tangible/terminal/mission/MissionTerminal.h"

// One persistent credit per party member, consumed by an accepted terminal job.
// The mission's normal native payout continues to control group sharing.
class SwgxrSlicingRewards {
 static void grant(CreatureObject* player) {
  auto ghost=player->getPlayerObject();
  if(ghost==nullptr)return;
  ghost->setScreenPlayData("swgxr_slicing_rewards","pending","1");
  ghost->updateToDatabase();
  player->sendSystemMessage("Your next accepted mission-terminal job will pay 50% more credits.");
 }
public:
 static bool pending(CreatureObject* player) {
  return player && player->getPlayerObject()!=nullptr && player->getPlayerObject()->getScreenPlayData("swgxr_slicing_rewards","pending")=="1";
 }
 static void terminalSuccess(CreatureObject* player) {
  if(!player || !player->isPlayerCreature())return;
  Vector<ManagedReference<CreatureObject*>> members;
  members.add(player);
  auto group=player->getGroup();
  if(group!=nullptr){
   Locker groupLock(group,player);
   for(int i=0;i<group->getGroupSize();++i){
    auto member=group->getGroupMember(i);
    if(member!=nullptr && member!=player && member->isPlayerCreature())members.add(member);
   }
  }
  for(int i=0;i<members.size();++i){
   auto member=members.get(i);
   if(member==player)grant(player);
   else {Locker memberLock(member,player);grant(member);}
  }
 }
 static void missionAccepted(CreatureObject* player,MissionTerminal* terminal,MissionObject* mission) {
  if(!pending(player) || !terminal || !mission || terminal->isBountyTerminal() ||
     !(terminal->isGeneralTerminal() || terminal->isArtisanTerminal() || terminal->isEntertainerTerminal() || terminal->isScoutTerminal() || terminal->isImperialTerminal() || terminal->isRebelTerminal()) ||
     mission->getParent().get()!=player->getSlottedObject("datapad") || mission->getMissionObjective()==nullptr || mission->getRewardCredits()<=0)return;
  const int original=mission->getRewardCredits();
  const int rewarded=int(std::min<int64>(INT_MAX,int64(original)*3/2));
  mission->setRewardCredits(rewarded,true);
  mission->updateToDatabase();
  auto ghost=player->getPlayerObject();
  ghost->setScreenPlayData("swgxr_slicing_rewards","pending","0");
  ghost->setScreenPlayData("swgxr_slicing_rewards","last_mission_id",String::valueOf(mission->getObjectID()));
  ghost->updateToDatabase();
 }
};
#endif
