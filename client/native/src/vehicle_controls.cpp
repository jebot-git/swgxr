#include "vehicle_controls.h"
#include <godot_cpp/core/class_db.hpp>
#include <cmath>
#include <algorithm>
using namespace godot;
void SwgVehicleControls::_bind_methods(){
 ClassDB::bind_method(D_METHOD("smooth_pose","target","delta","snap"),&SwgVehicleControls::smooth_pose,DEFVAL(false));
 ClassDB::bind_method(D_METHOD("reset"),&SwgVehicleControls::reset);
 ClassDB::bind_method(D_METHOD("sample_reins","mount","left","right","left_grip","right_grip","left_available","right_available","tracked","joystick"),&SwgVehicleControls::sample_reins);
 ClassDB::bind_method(D_METHOD("sample","kind","vehicle","left","right","left_handle","right_handle","left_grip","right_grip","left_available","right_available","tracked","joystick"),&SwgVehicleControls::sample,DEFVAL(0.0));
 ClassDB::bind_static_method("SwgVehicleControls",D_METHOD("advance","speed","throttle","steer","maximum","reverse","acceleration","turn_rate","delta"),&SwgVehicleControls::advance);
}
void SwgVehicleControls::reset(){for(auto& h:hands)h=Grip();wheel_angle=throttle_offset=twist_angle=0;reference_angle=reference_offset=reference_twist=0;reference_ready=false;}
static double axis(double value,double dead,double limit){if(!std::isfinite(value)||std::abs(value)<=dead)return 0;return std::copysign(std::clamp((std::abs(value)-dead)/(limit-dead),0.0,1.0),value);}
Dictionary SwgVehicleControls::sample_reins(const Transform3D& mount,const Transform3D& left,const Transform3D& right,double lg,double rg,bool la,bool ra,bool tracked,const Vector2& joystick){
 // Share vehicle grip hysteresis and tracking suspension. Rein pose never
 // contributes to locomotion: the locomotion stick supplies speed and yaw.
 auto result=sample("reins",mount,left,right,Vector3(-.2,0,0),Vector3(.2,0,0),lg,rg,la,ra,tracked);
 bool held=result["held"];bool valid=held && joystick.is_finite();
 result["throttle"]=valid?axis(joystick.y,.15,1):0;
 result["steer"]=valid?axis(joystick.x,.15,1):0;
 result["wheel_angle"]=0.0;result["throttle_offset"]=0.0;
 return result;
}
Dictionary SwgVehicleControls::sample(const String& kind,const Transform3D& vehicle,const Transform3D& left,const Transform3D& right,const Vector3& lh,const Vector3& rh,double lg,double rg,bool la,bool ra,bool tracked,double joystick){
 (void)joystick; // Kept in the ABI for old callers; physical controls own input.
 Dictionary result;bool membership_changed=false;int count=0;
 const bool frame_valid=tracked && vehicle.origin.is_finite() && vehicle.basis.is_finite() && std::abs(vehicle.basis.determinant())>.00001 && lh.is_finite() && rh.is_finite();
 auto inverse=frame_valid?vehicle.affine_inverse():Transform3D();
 Transform3D poses[]={inverse*left,inverse*right};double grips[]={lg,rg};bool available[]={la,ra};
 bool valid[2];bool suspended=!frame_valid;
 for(int i=0;i<2;++i){
  valid[i]=frame_valid && poses[i].origin.is_finite() && poses[i].basis.is_finite() && std::abs(poses[i].basis.determinant())>.00001 && std::isfinite(grips[i]);
  bool before=hands[i].held;
  // Release is physical. Missing tracking/focus is a suspension, never release.
  if(valid[i] && grips[i]<.25)hands[i].held=false;
  else if(valid[i] && available[i] && grips[i]>.65)hands[i].held=true;
  membership_changed|=before!=hands[i].held;
  if(hands[i].held){++count;if(!valid[i] || !available[i])suspended=true;}
  result[i==0?"left_held":"right_held"]=hands[i].held;
  result[i==0?"left_handle":"right_handle"]=hands[i].held?i:-1;
 }
 if(!count){wheel_angle=throttle_offset=twist_angle=0;reference_ready=false;}
 else if(suspended)reference_ready=false;
 else if(membership_changed || !reference_ready){
  // A new hand inherits the current control state, regardless of where its
  // controller is held. The other hand's reference is rebased at the same time.
  for(int i=0;i<2;++i)hands[i].reference=poses[i];
  reference_angle=wheel_angle;reference_offset=throttle_offset;reference_twist=twist_angle;reference_ready=true;
 }else if(kind!="reins"){
  const bool bike=kind=="bike";Vector3 pivot=(lh+rh)*.5;
  Basis rotation(bike?Vector3(0,1,0):Vector3(0,0,1),reference_angle);
  Vector3 a,b;double depth=0,twist=0;
  if(count==2){
   a=rotation.xform(rh-lh);
   b=a+(poses[1].origin-hands[1].reference.origin)-(poses[0].origin-hands[0].reference.origin);
  }else{
   int i=hands[0].held?0:1;a=rotation.xform((i==0?lh:rh)-pivot);
   b=a+poses[i].origin-hands[i].reference.origin;
  }
  double delta=bike?std::atan2(a.z*b.x-a.x*b.z,a.x*b.x+a.z*b.z):std::atan2(a.x*b.y-a.y*b.x,a.x*b.x+a.y*b.y);
  if(std::isfinite(delta))wheel_angle=std::clamp(reference_angle+delta,-.65,.65);
  for(int i=0;i<2;++i)if(hands[i].held){
   depth+=(poses[i].origin-hands[i].reference.origin).z;
   Basis change=poses[i].basis*hands[i].reference.basis.inverse();
   twist+=std::atan2(change[1].z,change[1].y);
  }
  if(bike)twist_angle=std::clamp(reference_twist+twist/count,-.55,.55);
  else throttle_offset=std::clamp(reference_offset+depth/count,-.20,.20);
 }
 result["wheel_angle"]=wheel_angle;result["throttle_offset"]=kind=="bike"?0:throttle_offset;
 result["suspended"]=suspended;result["held"]=count>0 && !suspended;
 result["throttle"]=count && !suspended?(kind=="bike"?axis(twist_angle,.07,.55):axis(-throttle_offset,.025,.20)):0;
 result["steer"]=count && !suspended?axis(-wheel_angle,.05,.65):0;
 return result;
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
