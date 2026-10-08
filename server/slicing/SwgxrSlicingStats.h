#ifndef SWGXR_SLICING_STATS_H
#define SWGXR_SLICING_STATS_H
#include "SwgxrSlicingData.h"
#include "server/zone/packets/scene/AttributeListMessage.h"
#include <set>
#include <map>
#include <cmath>

// Derived from immutable crafted values plus the persistent slice outcome.
// Repeated examine/equip/login calls never write modified base statistics.
class SwgxrSlicingStats {
public:
 static double percent(SceneObject* item,const char* key) {
  const double value=SwgxrSlicingData::bonus(item,key);
  return std::isfinite(value)?std::max(0.0,std::min(100.0,value)):0.0;
 }
 static double factor(SceneObject* item,const char* key) {return 1.0+percent(item,key)/100.0;}
 static void describe(AttributeListMessage* attributes,SceneObject* item) {
  const auto bonuses=SwgxrSlicingData::bonuses(item);
  for(const auto& entry:bonuses.items()) {
   static const std::map<std::string,std::string> labels={
    {"capacity_pct","Capacity"},{"rof_pct","Rate of fire"},{"power_pct","Power"},
    {"stance_recovery_pct","Stance recovery"},{"range_pct","Range modifier"},
    {"min_damage_pct","Minimum damage"},{"max_damage_pct","Maximum damage"},
    {"protection_pct","Protection"},{"sac_health_pct","Health attack cost"},
    {"sac_action_pct","Action attack cost"},{"sac_mind_pct","Mind attack cost"}};
   auto found=labels.find(entry.key());if(found==labels.end())continue;
   const bool cost=entry.key().find("sac_")==0;
   attributes->insertAttribute(String(("Slice: "+found->second).c_str()),String(cost?"-":"+")+String::valueOf(entry.value().get<double>())+(entry.key()=="range_pct"?" points":"%"));
  }
 }
 static double costScale(CreatureObject* player,int pool) {
  if(!player)return 1.0;
  const char* key=pool==0?"sac_health_pct":pool==3?"sac_action_pct":"sac_mind_pct";
  std::set<uint64> seen;double total=0;
  for(int i=0;i<player->getSlottedObjectsSize();++i){
   auto item=player->getSlottedObject(i);
   if(item!=nullptr && item->isWearableObject() && seen.insert(item->getObjectID()).second)
    total+=percent(item,key);
  }
  return 1.0-std::min(80.0,total)/100.0;
 }
};
#endif
