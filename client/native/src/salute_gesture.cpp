#include "salute_gesture.h"
#include <godot_cpp/core/class_db.hpp>
#include <cmath>
#include <algorithm>
using namespace godot;
void SwgSaluteGesture::_bind_methods(){ClassDB::bind_method(D_METHOD("sample","delta","target","head","hand","right_hand","open_hand","tracked","allowed"),&SwgSaluteGesture::sample);ClassDB::bind_method(D_METHOD("reset"),&SwgSaluteGesture::reset);}
void SwgSaluteGesture::interrupt(){held=0;target="";facing=Vector3();}
void SwgSaluteGesture::reset(){interrupt();latched=false;}
Dictionary SwgSaluteGesture::sample(double dt,const String &id,const Transform3D &head,const Vector3 &hand,bool right_hand,bool open_hand,bool tracked,bool allowed){
 Dictionary result;result["action"]="";result["progress"]=0.;result["latched"]=latched;
 if(!tracked||!std::isfinite(dt)||dt<=0||dt>.12||!head.origin.is_finite()||!head.basis.is_finite()||std::abs(head.basis.determinant())<.000001||!hand.is_finite()){interrupt();return result;}
 Vector3 p=head.affine_inverse().xform(hand);double side=right_hand?p.x:-p.x;
 bool temple=side>.14&&side<.36&&p.y>-.08&&p.y<.13&&p.z>-.22&&p.z<.10;
 bool release=side<.06||side>.46||p.y<-.20||p.y>.24||p.z<-.35||p.z>.22;
 if(release)latched=false;
 if(!allowed||latched||!open_hand||!temple||id.is_empty()){interrupt();result["latched"]=latched;return result;}
 Vector3 forward=-head.basis.get_column(2).normalized();
 if(target!=id){interrupt();target=id;facing=forward;}
 // A deliberate steady salute is distinct from Ranger's left/right scouting sweep.
 if(facing.dot(forward)<std::cos(.174533)){interrupt();return result;}
 held+=dt;result["progress"]=std::min(1.,held);
 if(held+1e-5>=1.){latched=true;result["latched"]=true;result["action"]="salute";}
 return result;
}
