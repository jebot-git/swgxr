#pragma once
#include <mutex>
#include <map>
#include <chrono>
// Presentation state comes from the native task, never a guessed client timer.
class SwgxrHyperspace {
 struct Phase {int iteration;double stamp;};
 static std::map<uint64,Phase>& phases(){static std::map<uint64,Phase> value;return value;}
 static std::mutex& mutex(){static std::mutex value;return value;}
 static double now(){return std::chrono::duration<double>(std::chrono::steady_clock::now().time_since_epoch()).count();}
public:
 static void set(uint64 id,int iteration){std::lock_guard<std::mutex> lock(mutex());double stamp=now();for(auto it=phases().begin();it!=phases().end();)if(stamp-it->second.stamp>120)it=phases().erase(it);else ++it;phases()[id]={iteration,stamp};}
 static JSONSerializationType snapshot(uint64 id,bool active){std::lock_guard<std::mutex> lock(mutex());if(!active){phases().erase(id);return {{"phase","idle"}};}auto it=phases().find(id);if(it==phases().end())return {{"phase","calculating"}};int i=it->second.iteration;return {{"phase",i>=10?"arrival":i==9?"travel":i>=5?"countdown":i==4?"orienting":"calculating"},{"iteration",i},{"age_seconds",now()-it->second.stamp},{"countdown",i>=5 && i<=8?9-i:0}};}
};
