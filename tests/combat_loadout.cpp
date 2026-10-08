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
 std::cout<<"Combat loadout policy: 15 assertions passed\n";
}
