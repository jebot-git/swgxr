#include "snapshot_motion.h"
#include <godot_cpp/core/class_db.hpp>
#include <algorithm>
#include <cmath>
using namespace godot;
void SwgSnapshotMotion::_bind_methods(){
 ClassDB::bind_method(D_METHOD("push","pose","stamp","reset"),&SwgSnapshotMotion::push,DEFVAL(false));
 ClassDB::bind_method(D_METHOD("push_goal","pose","stamp","walk","run","speed","reset"),&SwgSnapshotMotion::push_goal,DEFVAL(false));
 ClassDB::bind_method(D_METHOD("advance","now","delta"),&SwgSnapshotMotion::advance);
 ClassDB::bind_method(D_METHOD("get_velocity"),&SwgSnapshotMotion::get_velocity);
 ClassDB::bind_method(D_METHOD("get_delay"),&SwgSnapshotMotion::get_delay);
}
bool SwgSnapshotMotion::push(const Transform3D &pose,double time,bool reset){
 return push_goal(pose,time,walk_speed,run_speed,0,reset);
}
bool SwgSnapshotMotion::push_goal(const Transform3D &pose,double time,double walk,double run,double speed,bool reset){
 if(!pose.origin.is_finite() || !pose.basis.is_finite() || !std::isfinite(time) || !std::isfinite(walk) || !std::isfinite(run) || !std::isfinite(speed))return false;
 if(!reset && initialized && time<=stamp)return false;
 walk_speed=std::clamp(walk,.1,30.);run_speed=std::clamp(std::max(run,speed),walk_speed,60.);
 if(reset || !initialized){presented=pose;velocity=Vector3();current_speed=0;}
 goal=pose;stamp=time;initialized=true;return true;
}
Transform3D SwgSnapshotMotion::advance(double now,double delta){
 if(!initialized || !std::isfinite(now) || !std::isfinite(delta) || delta<=0)return presented;
 // Bound frame-hitch displacement. Never integrate beyond a confirmed endpoint.
 const double dt=std::min(delta,.05);
 Vector3 offset=goal.origin-presented.origin;
 const double distance=offset.length();
 const double horizontal=Vector2(offset.x,offset.z).length();
 const double tolerance=std::max(32.,run_speed*6.+current_speed*2.);
 if(distance>tolerance || (horizontal<.05 && std::abs(offset.y)>4.5)){
  presented=goal;velocity=Vector3();current_speed=0;return presented;
 }
 // Original RemoteCreatureController: walk near goal, run further away, and
 // bounded catch-up for a delayed goal. Acceleration avoids packet-sized jumps.
 double desired=distance<.01?0:distance<walk_speed?distance:distance<run_speed?run_speed:std::min(distance,run_speed*4.);
 double acceleration=run_speed*(desired>current_speed?3.:6.);
 current_speed+=std::clamp(desired-current_speed,-acceleration*dt,acceleration*dt);
 Vector3 step=distance>0?offset*(std::min(distance,current_speed*dt)/distance):Vector3();
 if(distance<.01){step=offset;current_speed=0;}
 presented.origin+=step;
 presented.basis=presented.basis.slerp(goal.basis,1-std::exp(-dt*12));
 velocity=step/dt;return presented;
}
