#include "server/combat/CoreCuLoadoutPolicy.h"
#include <cassert>
#include <iostream>
int main(){
 const std::set<std::string> regular={"a","b","c","d","e"},ultimate={"u","v"};
 corecu::CombatLoadout l;assert(l.valid(regular,ultimate));assert(!l.contains(""));
 l.slots={"a","b","c","d"};l.ultimate="u";assert(l.valid(regular,ultimate));assert(l.contains("a"));assert(l.contains("u"));assert(!l.contains("e"));assert(!l.contains("v"));
 l.slots[3]="e";assert(l.valid(regular,ultimate));assert(!l.contains("d"));
 l.slots[3]="a";assert(!l.valid(regular,ultimate));
 l.slots[3]="u";assert(!l.valid(regular,ultimate));
 l.slots[3]="d";l.ultimate="a";assert(!l.valid(regular,ultimate));
 l.ultimate="v";assert(l.valid(regular,ultimate));assert(!l.contains("u"));
 assert(!l.valid({"a","b","c"},ultimate));
 std::set<std::string> skills={"combat_brawler_master","combat_marksman_master"};
 const auto permitted=[&](const std::string& id){return corecu::ultimateAllowed(id,[&](const std::string& skill){return skills.count(skill)>0;});};
 assert(!permitted("charge_blast"));skills.insert("combat_carbine_master");assert(permitted("charge_blast"));skills.erase("combat_carbine_master");
 assert(!permitted("showdown"));skills.insert("combat_pistol_master");assert(permitted("showdown"));skills.erase("combat_pistol_master");
 assert(!permitted("last_ditch"));
 assert(!permitted("berserk"));
 assert(!permitted("center_of_being"));
 assert(!permitted("lethal_shot"));
 skills.insert("combat_rifleman_novice");assert(!permitted("last_ditch"));
 skills.insert("combat_smuggler_novice");assert(permitted("last_ditch"));
 assert(!permitted("unregistered_ultimate"));
 corecu::CombatLoadout advanced;advanced.ultimate="last_ditch";
 auto available=[&](){return permitted("last_ditch")?std::set<std::string>{"last_ditch"}:std::set<std::string>{};};
 assert(advanced.valid({},available()));
 skills.erase("combat_smuggler_novice");
 assert(!permitted("last_ditch"));assert(!advanced.valid({},available()));
 advanced.ultimate="";assert(advanced.valid({},available()));
 std::cout<<"Combat loadout and advanced-profession ultimate policy checks passed\n";
}
