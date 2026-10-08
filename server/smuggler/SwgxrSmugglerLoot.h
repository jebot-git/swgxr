#ifndef SWGXR_SMUGGLER_LOOT_H
#define SWGXR_SMUGGLER_LOOT_H
#include "conf/ConfigManager.h"
#include "server/zone/ZoneServer.h"
#include "SwgxrSmugglerLootPolicy.h"
#include "server/zone/objects/creature/CreatureObject.h"
#include "server/zone/objects/creature/ai/AiAgent.h"
#include "server/zone/managers/loot/LootManager.h"
#include "server/zone/objects/transaction/TransactionLog.h"

class SwgxrSmugglerLoot {
public:
 // Existing corpse generation calls this once, after the real final blow.
 // It never changes normal loot rolls, ownership or the corpse's death guard.
 static void award(TangibleObject* destructor,AiAgent* victim,SceneObject* inventory) {
  if(!destructor || !destructor->isPlayerCreature() || !victim || !inventory)return;
  auto player=destructor->asCreatureObject();
  bool novice=false;
  {
   Locker playerLock(player,victim);
   novice=player->hasSkill("combat_smuggler_novice");
  }
  const int chance=SwgxrSmugglerLootPolicy::chance(ConfigManager::instance()->getInt("Core3.Smuggler.LockedContainerBonusPercent",20));
  const int roll=System::random(99);
  if(!SwgxrSmugglerLootPolicy::wins(true,novice,victim->isNonPlayerCreatureObject(),victim->isPet(),victim->isEventMob(),chance,roll))return;
  TransactionLog trx(TrxCode::NPCLOOT,victim);
  trx.addState("smugglerLockedContainerBonus",true);
  trx.addState("destructor",destructor->getObjectID());
  trx.addState("bonusChancePercent",chance);
  trx.addState("bonusRoll",roll);
  if(victim->getZoneServer()->getLootManager()->createLoot(trx,inventory,"locked_container",victim->getLevel())!=0)trx.commit(true);
  else if(trx.isEnabled() && !trx.isAborted())trx.abort()<<"Smuggler locked container creation failed.";
 }
};
#endif
