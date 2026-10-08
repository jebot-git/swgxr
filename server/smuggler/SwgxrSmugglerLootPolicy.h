#ifndef SWGXR_SMUGGLER_LOOT_POLICY_H
#define SWGXR_SMUGGLER_LOOT_POLICY_H
#include <algorithm>
class SwgxrSmugglerLootPolicy {
public:
 static int chance(int configured) {return std::max(0,std::min(100,configured));}
 static bool wins(bool directPlayer,bool novice,bool npc,bool pet,bool event,int configured,int roll) {
  return directPlayer && novice && npc && !pet && !event && roll>=0 && roll<100 && roll<chance(configured);
 }
};
#endif
