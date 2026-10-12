#pragma once
#include "engine/util/json_utils.h"
#include "server/zone/Zone.h"
#include "server/zone/objects/creature/CreatureObject.h"
#include <chrono>
#include <deque>
#include <mutex>
// Owner-only receipts for original native space mission text/music. No quest
// state is created here; overlapping snapshots are deduplicated by event ID.
class SwgxrSpaceMessages {
 using Json=JSONSerializationType;
 struct Event {uint64 owner,id;double stamp;Json data;};
 struct Store {std::mutex mutex;std::deque<Event> events;uint64 next=0;};
 static Store& store(){static Store s;return s;}
 static double now(){return std::chrono::duration<double>(std::chrono::steady_clock::now().time_since_epoch()).count();}
public:
 static void capture(CreatureObject* c,Json data){
  if(!c || !c->isPlayerCreature() || !c->getZone() || !c->getZone()->isSpaceZone())return;
  auto& s=store();std::lock_guard<std::mutex> lock(s.mutex);double stamp=now();
  while(!s.events.empty() && (s.events.size()>=2048 || stamp-s.events.front().stamp>30))s.events.pop_front();
  data["id"]=std::to_string(++s.next);s.events.push_back({c->getObjectID(),s.next,stamp,data});
 }
 static Json snapshot(CreatureObject* c){
  Json out=Json::array();if(!c)return out;auto& s=store();std::lock_guard<std::mutex> lock(s.mutex);double stamp=now();
  for(auto it=s.events.rbegin();it!=s.events.rend() && out.size()<32;++it){if(stamp-it->stamp>30)break;if(it->owner!=c->getObjectID())continue;auto row=it->data;row["age_seconds"]=stamp-it->stamp;out.push_back(row);}return out;
 }
};
