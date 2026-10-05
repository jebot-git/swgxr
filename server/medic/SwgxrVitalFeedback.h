#ifndef SWGXR_VITAL_FEEDBACK_H
#define SWGXR_VITAL_FEEDBACK_H
#include "engine/util/JSONSerializationType.h"
#include <chrono>
#include <map>
#include <mutex>
#include <cstdint>
// Transient presentation events, never HAM authority. No pointers or foreign data.
class SwgxrVitalFeedback {
 struct Entry {uint64_t damage=0,heal=0;double touched=0;};
 static auto& entries(){static std::map<uint64_t,Entry> value;return value;}
 static auto& mutex(){static std::mutex value;return value;}
 static int& healingDepth(){static thread_local int value=0;return value;}
public:
 struct MedicalAction {MedicalAction(){++healingDepth();}~MedicalAction(){--healingDepth();}};
 static bool medical(){return healingDepth()>0;}
 static double now(){return std::chrono::duration<double>(std::chrono::steady_clock::now().time_since_epoch()).count();}
 static void record(uint64_t id,bool heal){
  std::lock_guard<std::mutex> lock(mutex());auto stamp=now();auto& list=entries();
  for(auto it=list.begin();it!=list.end();)if(stamp-it->second.touched>120)it=list.erase(it);else ++it;
  if(!list.count(id) && list.size()>=128)return;
  static uint64_t sequence=0;auto& item=list[id];(heal?item.heal:item.damage)=++sequence;item.touched=stamp;
 }
 static JSONSerializationType snapshot(uint64_t id){
  std::lock_guard<std::mutex> lock(mutex());auto found=entries().find(id);
  if(found==entries().end())return {{"damage",0},{"heal",0},{"age_seconds",0}};
  return {{"damage",found->second.damage},{"heal",found->second.heal},{"age_seconds",now()-found->second.touched}};
 }
};
#endif
