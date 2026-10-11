#pragma once
#include <algorithm>
#include <cmath>
#include <cstdint>
namespace swgxr { namespace jtl {
// The network byte 255 means no requested subsystem; zero is the reactor.
constexpr uint8_t NO_SUBSYSTEM = 255;
struct MissileLock {
 double elapsed=0,last=0; bool acquired=false;
 void reset(){elapsed=0;last=0;acquired=false;}
 void update(double now,bool eligible,double duration){
  if(!eligible || !std::isfinite(duration) || duration<0){reset();return;}
  if(last>0 && now>=last && now-last<=.3)elapsed+=now-last;
  else {elapsed=0;acquired=false;}
  last=now;acquired=elapsed>=duration;
 }
};
inline bool withinAcquisition(double distance,double range,double cosine,double degrees){
 return std::isfinite(distance) && std::isfinite(range) && std::isfinite(cosine) &&
  distance>0 && range>0 && distance<=range && degrees>0 && degrees<=180 &&
  cosine>=std::cos(degrees*3.14159265358979323846/180.);
}
}}
