#pragma once
#include <array>
#include <set>
#include <string>
namespace corecu {
// An ultimate must belong to a specific advanced profession. Native command
// grants and weapon restrictions remain additional requirements.
inline std::string ultimateProfession(const std::string& id) {
 return id=="fast_blast" ? "combat_bountyhunter_master" : id=="volley_fire" ? "outdoors_squadleader_master" : id=="overdrive" ? "combat_commando_master" : id=="sniper_shot" ? "combat_rifleman_master" : id=="charge_blast" ? "combat_carbine_master" : id=="showdown" ? "combat_pistol_master" : id=="last_ditch" ? "combat_smuggler_novice" : id=="indomitable_focus" ? "combat_unarmed_master" : id=="armour_break" ? "combat_2hsword_master" : id=="flawless_assault" ? "combat_1hsword_master" : id=="whirlwind" ? "combat_polearm_master" : "";
}
template<class HasSkill>
bool ultimateAllowed(const std::string& id,HasSkill hasSkill) {
 const auto profession=ultimateProfession(id);
 return !profession.empty() && hasSkill(profession);
}
struct CombatLoadout {
 std::array<std::string,4> slots{};
 std::string ultimate;
 bool contains(const std::string& id) const {
  if(id.empty())return false;
  if(ultimate==id)return true;
  for(const auto& value:slots)if(value==id)return true;
  return false;
 }
 bool valid(const std::set<std::string>& regular,const std::set<std::string>& ultimates) const {
  std::set<std::string> seen;
  for(const auto& id:slots)if(!id.empty() && (!regular.count(id) || !seen.insert(id).second))return false;
  return ultimate.empty() || ultimates.count(ultimate);
 }
};
}
