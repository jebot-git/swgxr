#pragma once
#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <stdexcept>
namespace swgxr { namespace jtl {
using Vec=std::array<double,3>;
using Quat=std::array<double,4>; // Original-client coordinates: X, Y-up, Z; XYZW.
inline double clamp(double v,double a,double b){return std::max(a,std::min(b,v));}
inline double length(const Vec& p){return std::sqrt(p[0]*p[0]+p[1]*p[1]+p[2]*p[2]);}
inline Quat multiply(const Quat& a,const Quat& b){return {{a[3]*b[0]+a[0]*b[3]+a[1]*b[2]-a[2]*b[1],a[3]*b[1]-a[0]*b[2]+a[1]*b[3]+a[2]*b[0],a[3]*b[2]+a[0]*b[1]-a[1]*b[0]+a[2]*b[3],a[3]*b[3]-a[0]*b[0]-a[1]*b[1]-a[2]*b[2]}};}
inline Quat normalized(Quat q){double n=0;for(double v:q){if(!std::isfinite(v))throw std::runtime_error("jtl_invalid_quaternion");n+=v*v;}if(n<.0001)throw std::runtime_error("jtl_invalid_quaternion");for(auto& v:q)v/=std::sqrt(n);return q;}
inline Quat axis(int i,double angle){Quat q{{0,0,0,std::cos(angle/2)}};q[i]=std::sin(angle/2);return q;}
struct Input {double throttle=0,pitch=0,yaw=0,roll=0;uint64_t sequence=0;};
struct State {Vec position{{0,0,0}};Quat orientation{{0,0,0,1}};double speed=0,stamp=0;uint64_t sequence=0;Vec velocity{{0,0,0}}, angular{{0,0,0}};};
constexpr double CONTROL_LEASE_SECONDS=1.5;
inline void validate(const Input& i){for(double v:{i.throttle,i.pitch,i.yaw,i.roll})if(!std::isfinite(v) || std::abs(v)>1)throw std::runtime_error("jtl_invalid_controls");if(i.throttle<0 || i.sequence==0)throw std::runtime_error("jtl_invalid_controls");}
// Original ShipDynamicsModel behavior, with authoritative Core3 component stats.
// Angular rates/accelerations are radians, speed is m/s. Controls never supply stats.
struct Dynamics {
 double maxSpeed=0,acceleration=0,deceleration=0;
 Vec rates{{0,0,0}}, angularAcceleration{{0,0,0}}; // pitch, yaw, roll
 double slideDampener=0,halfWidth=8192;
};
inline void validate(const Dynamics& d){
 for(double v:{d.maxSpeed,d.acceleration,d.deceleration,d.slideDampener,d.halfWidth})if(!std::isfinite(v) || v<0)throw std::runtime_error("jtl_invalid_dynamics");
 for(auto values:{d.rates,d.angularAcceleration})for(double v:values)if(!std::isfinite(v) || v<0)throw std::runtime_error("jtl_invalid_dynamics");
 if(d.halfWidth<=32)throw std::runtime_error("jtl_invalid_dynamics");
}
inline double approach(double current,double desired,double up,double down,double dt){return current+clamp(desired-current,-down*dt,up*dt);}
inline void stop(State& s){s.speed=0;s.velocity={{0,0,0}};s.angular={{0,0,0}};}
// Advance held controls on a fixed native clock independently of HTTP arrivals.
inline State integrate(State s,const Input& i,double now,const Dynamics& d){
 validate(i);validate(d);
 if(!std::isfinite(now) || now<s.stamp)throw std::runtime_error("jtl_invalid_clock");
 double dt=clamp(now-s.stamp,0,.05);s.stamp=now;
 s.speed=approach(s.speed,d.maxSpeed*i.throttle,d.acceleration,d.deceleration,dt);
 Vec controls{{i.pitch,i.yaw,i.roll}};
 for(int k=0;k<3;++k)s.angular[k]=approach(s.angular[k],controls[k]*d.rates[k],d.angularAcceleration[k],d.angularAcceleration[k],dt);
 s.orientation=normalized(multiply(s.orientation,multiply(axis(1,s.angular[1]*dt),multiply(axis(0,s.angular[0]*dt),axis(2,s.angular[2]*dt)))));
 auto q=s.orientation;Vec forward{{2*(q[0]*q[2]+q[3]*q[1]),2*(q[1]*q[2]-q[3]*q[0]),1-2*(q[0]*q[0]+q[1]*q[1])}};
 if(d.slideDampener==0){for(int k=0;k<3;++k)s.velocity[k]=forward[k]*s.speed;}
 else{
  for(int k=0;k<3;++k)s.velocity[k]+=forward[k]*s.speed*d.slideDampener*dt;
  double magnitude=length(s.velocity);if(magnitude>s.speed && magnitude>0)for(auto& v:s.velocity)v*=s.speed/magnitude;
 }
 // Original client reserves 32 metres inside the terrain's sector volume.
 for(int k=0;k<3;++k)s.position[k]=clamp(s.position[k]+s.velocity[k]*dt,-d.halfWidth+32,d.halfWidth-32);
 return s;
}
inline State advance(State s,const Input& held,double received,double now,const Dynamics& d){
 if(!std::isfinite(now) || now<s.stamp || !std::isfinite(received))throw std::runtime_error("jtl_invalid_clock");
 double end=std::min(now,received+CONTROL_LEASE_SECONDS);
 while(s.stamp+1e-8<end)s=integrate(s,held,std::min(end,s.stamp+.05),d);
 if(now>=received+CONTROL_LEASE_SECONDS)stop(s);
 s.stamp=now;return s;
}
inline State step(State s,const Input& i,double now,const Dynamics& d){
 validate(i);if(i.sequence<=s.sequence)throw std::runtime_error("jtl_stale_controls");
 s=advance(s,i,s.stamp,now,d);s.sequence=i.sequence;return s;
}
// Transfer existing shield energy, conserving charge and respecting each bank.
inline std::array<double,2> shields(double front,double rear,double maxFront,double maxRear,double ratio){double total=std::max(0.,front)+std::max(0.,rear);double f=clamp(total*clamp(ratio,0,1),std::max(0.,total-maxRear),std::min(total,maxFront));return {{f,total-f}};}
inline bool walkBudget(const Vec& from,const Vec& to,double elapsed,double& credit,double maxSpeed=3.){if(!std::isfinite(elapsed) || elapsed<0)return false;double rate=clamp(maxSpeed,0,10)*1.1;credit=std::min(rate*2+.25,credit+std::min(elapsed,2.)*rate);Vec d{};for(int k=0;k<3;++k){if(!std::isfinite(to[k]) || std::abs(to[k])>64)return false;d[k]=to[k]-from[k];}double distance=length(d);if(distance>credit+.0001)return false;credit-=distance;return true;}
}}
