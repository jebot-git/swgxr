#ifndef SWGXR_LEADERSHIP_EXPERIENCE_POLICY_H
#define SWGXR_LEADERSHIP_EXPERIENCE_POLICY_H
#include <string>
#include <cstdint>
class LeadershipExperiencePolicy {
public:
 // combat_general is a second award for the same damage, so never share it.
 // No leadership, crafting, mission cash, pet, pilot or Jedi award can recurse.
 static bool source(const std::string& name){
  return name=="combat_rangedspecialize_pistol" || name=="combat_rangedspecialize_carbine" || name=="combat_rangedspecialize_rifle" || name=="combat_rangedspecialize_heavy" || name=="combat_meleespecialize_unarmed" || name=="combat_meleespecialize_onehand" || name=="combat_meleespecialize_twohand" || name=="combat_meleespecialize_polearm";
 }
 static int share(int actualEarned,int& remainder){
  if(actualEarned<=0)return 0;
  int64_t tenths=int64_t(actualEarned)+(remainder>=0 && remainder<10?remainder:0);
  remainder=int(tenths%10);return int(tenths/10);
 }
};
#endif
