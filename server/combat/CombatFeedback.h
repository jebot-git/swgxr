#pragma once
#include <cstdint>
#include <map>
#include <array>
#include <string>
namespace corecu { namespace feedback {
// Capture native secondary-defense results during one authenticated attack.
// Thread-local scoped ownership prevents other players/counterattacks leaking in.
struct Result {std::string resolution;int damage=0;std::array<double,3> position{{0,0,0}};};
struct Capture {uint64_t attacker;std::map<uint64_t,Result> results;};
inline Capture*& current(){static thread_local Capture* value=nullptr;return value;}
struct Scope {
 Capture value;Capture* previous;
 explicit Scope(uint64_t attacker):value{attacker,{}},previous(current()){current()=&value;}
 ~Scope(){current()=previous;}
 std::string result(uint64_t target) const {auto i=value.results.find(target);return i==value.results.end()?"":i->second.resolution;}
};
inline void record(uint64_t attacker,uint64_t defender,const char* result,int damage=0,std::array<double,3> position={{0,0,0}}){auto c=current();if(c&&c->attacker==attacker){auto& r=c->results[defender];r.resolution=result;r.damage+=damage;r.position=position;}}
} }
