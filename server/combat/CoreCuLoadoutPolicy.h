#pragma once
#include <array>
#include <set>
#include <string>
namespace corecu {
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
