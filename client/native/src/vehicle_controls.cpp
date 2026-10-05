#include "vehicle_controls.h"
#include <godot_cpp/core/class_db.hpp>
#include <cmath>
#include <algorithm>
using namespace godot;
void SwgVehicleControls::_bind_methods(){
 ClassDB::bind_method(D_METHOD("smooth_pose","target","delta","snap"),&SwgVehicleControls::smooth_pose,DEFVAL(false));
 ClassDB::bind_method(D_METHOD("reset"),&SwgVehicleControls::reset);
 ClassDB::bind_method(D_METHOD("sample","kind","vehicle","left","right","left_handle","right_handle","left_grip","right_grip","left_available","right_available","tracked","joystick"),&SwgVehicleControls::sample,DEFVAL(0.0));
 ClassDB::bind_static_method("SwgVehicleControls",D_METHOD("advance","speed","throttle","steer","maximum","reverse","acceleration","turn_rate","delta"),&SwgVehicleControls::advance);
}
void SwgVehicleControls::reset(){for(auto& h:hands)h=Grip();wheel_angle=0;}
static double axis(double value,double dead,double limit){if(!std::isfinite(value)||std::abs(value)<=dead)return 0;return std::copysign(std::clamp((std::abs(value)-dead)/(limit-dead),0.0,1.0),value);}
Dictionary SwgVehicleControls::sample(const String& kind,const Transform3D& vehicle,const Transform3D& left,const Transform3D& right,const Vector3& lh,const Vector3& rh,double lg,double rg,bool la,bool ra,bool tracked,double joystick){
 Dictionary result;double throttle=0,steer=0,angle=0;int count=0;auto inverse=vehicle.affine_inverse();Transform3D poses[]={inverse*left,inverse*right};double grips[]={lg,rg};bool available[]={la,ra};Vector3 handles[]={lh,rh};Vector3 pivot=(lh+rh)*.5;Vector3 acquire[]={lh,rh};
 if(kind!="bike")for(int i=0;i<2;++i)acquire[i]=pivot+Basis(Vector3(0,0,1),wheel_angle).xform(handles[i]-pivot);
 for(int i=0;i<2;++i){auto& h=hands[i];auto p=poses[i];bool valid=tracked && available[i] && p.origin.is_finite() && p.basis.is_finite() && std::isfinite(grips[i]);
  if(!valid || grips[i]<.25){h.held=false;if(valid && grips[i]<.25)h.armed=true;else h.armed=false;}
  else if(grips[i]>.65 && h.armed && !h.held){h.armed=false;int handle=p.origin.distance_to(acquire[0])<p.origin.distance_to(acquire[1])?0:1;if(p.origin.distance_to(acquire[handle])<.24 && (!hands[1-i].held || hands[1-i].handle!=handle)){h.held=true;h.neutral=p;if(kind!="bike")h.neutral.origin=pivot+Basis(Vector3(0,0,1),-wheel_angle).xform(p.origin-pivot);h.pivot=pivot;h.handle=handle;}}
  if(h.held && p.origin.distance_to(h.neutral.origin)>.65){h.held=false;h.armed=false;}
  result[i==0?"left_held":"right_held"]=h.held;result[i==0?"left_handle":"right_handle"]=h.held?h.handle:-1;
  if(!h.held)continue;
  Basis change=p.basis*h.neutral.basis.inverse();double input=0,rotation=0;
  if(kind=="bike"){
   // Roll forward about the vehicle's left/right handle axis, independent of
   // OpenXR controller-specific neutral grip orientation.
   input=axis(std::atan2(change[1].z,change[1].y),.07,.55);
   auto a=h.neutral.origin-h.pivot,b=p.origin-h.pivot;
   rotation=std::atan2(a.z*b.x-a.x*b.z,a.x*b.x+a.z*b.z);
   steer+=axis(-rotation,.05,.60);
  }else{
   // Landspeeder speed uses precise main-hand analog input, never reach depth.
   input=axis(joystick,.12,1.0);
   // Steering follows the grabbed rim around the wheel's vertical plane,
   // not wrist roll or a lateral hand/controller direction. With both hands
   // held, the rim-to-rim vector removes common translation of the hands.
   auto a=h.neutral.origin-h.pivot,b=p.origin-h.pivot;
   if(hands[1-i].held){
    a=h.neutral.origin-hands[1-i].neutral.origin;
    b=p.origin-poses[1-i].origin;
   }
   rotation=std::atan2(a.y*b.x-a.x*b.y,a.x*b.x+a.y*b.y);
   steer+=axis(rotation,.05,.65);angle+=std::clamp(-rotation,-.65,.65);
  }
  throttle+=input;++count;
 }
 wheel_angle=count && kind!="bike"?angle/count:0;result["wheel_angle"]=wheel_angle;
 result["held"]=count>0;result["throttle"]=count?throttle/count:0;result["steer"]=count?steer/count:0;return result;
}
Dictionary SwgVehicleControls::advance(double speed,double throttle,double steer,double maximum,double reverse,double accel,double turn,double dt){
 Dictionary out;out["speed"]=0.0;out["distance"]=0.0;out["yaw"]=0.0;
 for(double v:{speed,throttle,steer,maximum,reverse,accel,turn,dt})if(!std::isfinite(v))return out;
 dt=std::clamp(dt,0.0,.1);throttle=std::clamp(throttle,-1.0,1.0);steer=std::clamp(steer,-1.0,1.0);
 double target=throttle*std::max(0.0,throttle<0?reverse:maximum);double rate=std::max(.1,accel)*((speed*throttle<0||std::abs(throttle)<.05)?2:1);
 double next=speed+std::clamp(target-speed,-rate*dt,rate*dt);if(speed*target<0 && speed*next<0)next=0;
 out["speed"]=next;out["distance"]=next*dt;out["yaw"]=steer*std::max(0.0,turn)*std::clamp(next/3.0,-1.0,1.0)*dt;return out;
}

Transform3D SwgVehicleControls::smooth_pose(const Transform3D& target,double dt,bool snap){
 if(!target.origin.is_finite() || !target.basis.is_finite() || !std::isfinite(dt))return view;
 if(!view_ready || snap){view=target;view_velocity=Vector3();view_yaw_velocity=0;view_ready=true;return view;}
 // Critically damp the vehicle frame only. Never filter tracked head/hand poses.
 // Bounded substeps and acceleration avoid correction impulses at packet edges.
 dt=std::clamp(dt,0.0,.1);int steps=std::max(1,int(std::ceil(dt/.005)));double h=dt/steps;
 double yaw=view.basis.get_euler().y,goal=target.basis.get_euler().y;
 for(int i=0;i<steps;++i){
  Vector3 acceleration=(target.origin-view.origin)*100-view_velocity*20;
  if(acceleration.length()>30)acceleration=acceleration.normalized()*30;
  view_velocity+=acceleration*h;view.origin+=view_velocity*h;
  double error=std::atan2(std::sin(goal-yaw),std::cos(goal-yaw));
  double angular=std::clamp(error*100-view_yaw_velocity*20,-8.0,8.0);
  view_yaw_velocity+=angular*h;yaw+=view_yaw_velocity*h;
 }
 view.basis=Basis(Vector3(0,1,0),yaw);return view;
}
