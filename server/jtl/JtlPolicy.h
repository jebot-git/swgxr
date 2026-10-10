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
struct State {Vec position{{0,0,0}};Quat orientation{{0,0,0,1}};double speed=0,stamp=0;uint64_t sequence=0;};
constexpr double CONTROL_LEASE_SECONDS=1.5;
inline void validate(const Input& i){for(double v:{i.throttle,i.pitch,i.yaw,i.roll})if(!std::isfinite(v) || std::abs(v)>1)throw std::runtime_error("jtl_invalid_controls");if(i.throttle<0 || i.sequence==0)throw std::runtime_error("jtl_invalid_controls");}
// Control packets supply inputs, never pose, velocity, elapsed time or ship stats.
// Advance held controls on the native clock, independently of HTTP arrivals.
inline State integrate(State s,const Input& i,double now,double maxSpeed,double acceleration,double pitchRate,double yawRate,double rollRate){
 validate(i);
 if(!std::isfinite(now) || now<s.stamp)throw std::runtime_error("jtl_invalid_clock");
 double dt=clamp(now-s.stamp,0,.05);s.stamp=now;
 double desired=clamp(maxSpeed,0,100)*i.throttle,delta=clamp(acceleration,1,30)*dt;
 s.speed+=clamp(desired-s.speed,-delta,delta);
 const double rad=3.141592653589793/180;
 s.orientation=normalized(multiply(s.orientation,multiply(axis(1,i.yaw*clamp(yawRate,0,60)*rad*dt),multiply(axis(0,i.pitch*clamp(pitchRate,0,60)*rad*dt),axis(2,i.roll*clamp(rollRate,0,60)*rad*dt)))));
 auto q=s.orientation;Vec forward{{2*(q[0]*q[2]+q[3]*q[1]),2*(q[1]*q[2]-q[3]*q[0]),1-2*(q[0]*q[0]+q[1]*q[1])}};
 for(int k=0;k<3;++k){s.position[k]+=forward[k]*s.speed*dt;if(std::abs(s.position[k])>7000){s.position[k]=clamp(s.position[k],-7000,7000);s.speed=0;}}
 return s;
}
inline State advance(State s,const Input& held,double received,double now,double maxSpeed,double acceleration,double pitchRate,double yawRate,double rollRate){
 if(!std::isfinite(now) || now<s.stamp)throw std::runtime_error("jtl_invalid_clock");
 double end=std::min(now,received+CONTROL_LEASE_SECONDS);
 while(s.stamp+1e-8<end)s=integrate(s,held,std::min(end,s.stamp+.05),maxSpeed,acceleration,pitchRate,yawRate,rollRate);
 if(now>=received+CONTROL_LEASE_SECONDS)s.speed=0;
 s.stamp=now;return s;
}
inline State step(State s,const Input& i,double now,double maxSpeed,double acceleration,double pitchRate,double yawRate,double rollRate){
 validate(i);if(i.sequence<=s.sequence)throw std::runtime_error("jtl_stale_controls");
 s=advance(s,i,s.stamp,now,maxSpeed,acceleration,pitchRate,yawRate,rollRate);s.sequence=i.sequence;return s;
}
// Transfer existing shield energy, conserving charge and respecting each bank.
inline std::array<double,2> shields(double front,double rear,double maxFront,double maxRear,double ratio){double total=std::max(0.,front)+std::max(0.,rear);double f=clamp(total*clamp(ratio,0,1),std::max(0.,total-maxRear),std::min(total,maxFront));return {{f,total-f}};}
inline bool walkBudget(const Vec& from,const Vec& to,double elapsed,double& credit,double maxSpeed=3.){if(!std::isfinite(elapsed) || elapsed<0)return false;double rate=clamp(maxSpeed,0,10)*1.1;credit=std::min(rate*2+.25,credit+std::min(elapsed,2.)*rate);Vec d{};for(int k=0;k<3;++k){if(!std::isfinite(to[k]) || std::abs(to[k])>64)return false;d[k]=to[k]-from[k];}double distance=length(d);if(distance>credit+.0001)return false;credit-=distance;return true;}
}}
