#include "ranger_gesture.h"
#include <godot_cpp/core/class_db.hpp>
#include <cmath>
#include <algorithm>
using namespace godot;
void SwgRangerGesture::_bind_methods(){ClassDB::bind_method(D_METHOD("sample","delta","kind","target","head","left","right","pointing","tracked","allowed"),&SwgRangerGesture::sample);ClassDB::bind_method(D_METHOD("reset"),&SwgRangerGesture::reset);}
void SwgRangerGesture::interrupt(){held=0;have=false;mode="";target="";yaw=low=high=travel=0;direction=0;reversed=false;}
void SwgRangerGesture::reset(){interrupt();latched=false;}
Dictionary SwgRangerGesture::sample(double dt,const String &kind,const String &id,const Transform3D &head,const Vector3 &left,const Vector3 &right,bool pointing,bool tracked,bool allowed){
 Dictionary out;out["action"]="";out["progress"]=0.;out["latched"]=latched;
 if(!tracked||!std::isfinite(dt)||dt<=0||dt>.12||!head.origin.is_finite()||!head.basis.is_finite()||!left.is_finite()||!right.is_finite()){interrupt();return out;}
 auto inv=head.affine_inverse();auto l=inv.xform(left),r=inv.xform(right);
 auto brow=[](Vector3 p){return p.y>.015&&p.y<.24&&std::abs(p.x)<.4&&p.z<-.02&&p.z>-.38;};
 bool shade=brow(l)||brow(r);
 if(!pointing&&!shade)latched=false;
 if(!allowed||latched){interrupt();out["latched"]=latched;return out;}
 bool valid=kind=="rescue"?pointing&&!id.is_empty():kind=="area_track"&&shade;
 if(!valid){interrupt();return out;}
 if(mode!=kind||target!=id){interrupt();mode=kind;target=id;}
 held+=dt;
 if(kind=="area_track"){
  Vector3 forward=-head.basis.get_column(2);double current=std::atan2(forward.x,-forward.z);
  if(!have){last_yaw=current;have=true;}
  double change=std::remainder(current-last_yaw,6.283185307179586);last_yaw=current;
  if(std::abs(change)>5.*dt){interrupt();return out;}
  yaw+=change;low=std::min(low,yaw);high=std::max(high,yaw);travel+=std::abs(change);
  if(direction==0&&std::abs(yaw)>.15)direction=yaw>0?1:-1;
  if((direction>0&&high-yaw>.174533)||(direction<0&&yaw-low>.174533))reversed=true;
  out["progress"]=std::min({1.,held/2.,(high-low)/.872665,travel/1.22173});
  if(held<2.||high-low<.872665||travel<1.22173||!reversed)return out;
 }else{out["progress"]=std::min(1.,held);if(held+1e-5<1.)return out;}
 out["action"]=kind;latched=true;out["latched"]=true;return out;
}
