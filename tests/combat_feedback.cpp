#include "../server/combat/CombatFeedback.h"
#include <cassert>
int main(){
 using namespace corecu::feedback;
 record(1,2,"miss");assert(current()==nullptr);
 Scope outer(1);record(1,2,"blocked");record(3,2,"miss");
 assert(outer.result(2)=="blocked");assert(outer.result(4).empty());
 {Scope inner(3);record(3,4,"dodged");assert(inner.result(4)=="dodged");assert(inner.result(2).empty());}
 record(1,5,"hit");assert(outer.result(5)=="hit");assert(outer.result(2)=="blocked");
 record(1,5,"hit",30,{{1,2,3}});record(1,5,"blocked",12,{{4,5,6}});
 assert(outer.value.results.at(5).damage==42);assert(outer.value.results.at(5).position[2]==6);
 record(3,5,"hit",100);assert(outer.value.results.at(5).damage==42);
}
