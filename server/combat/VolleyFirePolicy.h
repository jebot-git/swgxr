#pragma once
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <map>
#include <mutex>
#include <set>
#include <string>
namespace corecu { namespace volley {
constexpr double Duration=12, Cooldown=120, CastRange=64;
constexpr int Action=80, Mind=40;
// Group departures invalidate captured charges even if the same character rejoins
// before the next combat snapshot. No player or group object lock is taken here.
inline std::mutex& epochMutex(){static std::mutex value;return value;}
inline std::map<uint64_t,uint64_t>& epochs(){static std::map<uint64_t,uint64_t> value;return value;}
inline uint64_t epoch(uint64_t member){std::lock_guard<std::mutex> lock(epochMutex());return epochs()[member];}
inline void leave(uint64_t member){std::lock_guard<std::mutex> lock(epochMutex());++epochs()[member];}
struct Mark {
 std::string id;uint64_t group=0,caster=0,target=0,zone=0,casterEpoch=0;double expires=0;
 std::map<uint64_t,uint64_t> members;std::set<uint64_t> spent;
 bool permits(uint64_t member,uint64_t actualGroup,uint64_t actualZone,double now)const{
  auto found=members.find(member);return now<expires && actualGroup==group && actualZone==zone &&
   found!=members.end() && found->second==epoch(member) && casterEpoch==epoch(caster) && !spent.count(member);
 }
 bool consume(uint64_t member,uint64_t actualGroup,uint64_t actualZone,double now){if(!permits(member,actualGroup,actualZone,now))return false;spent.insert(member);return true;}
};
struct Context {uint64_t attacker=0,target=0;bool resolved=false;};
inline Context*& current(){static thread_local Context* value=nullptr;return value;}
class Scope {
 Context context;Context* previous;
public:
 Scope(uint64_t attacker,uint64_t target):context{attacker,target,false},previous(current()){current()=&context;}
 ~Scope(){current()=previous;}
 bool resolved()const{return context.resolved;}
};
inline bool guaranteed(uint64_t attacker,uint64_t target){auto p=current();return p && p->attacker==attacker && p->target==target;}
inline bool hitAvailable(uint64_t attacker,uint64_t target){return guaranteed(attacker,target) && !current()->resolved;}
inline bool claimHit(uint64_t attacker,uint64_t target){if(!hitAvailable(attacker,target))return false;current()->resolved=true;return true;}
inline void resolved(uint64_t attacker,uint64_t target){if(guaranteed(attacker,target))current()->resolved=true;}
inline uint64_t target(uint64_t attacker){auto p=current();return p && p->attacker==attacker?p->target:0;}
inline bool inRange(double distance,double range){return std::isfinite(distance) && std::isfinite(range) && distance>=0 && range>0 && distance<=range;}
}}
