#include "medic_drag.h"
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/aabb.hpp>
#include <cmath>
using namespace godot;
void SwgMedicDrag::_bind_methods(){
 ClassDB::bind_static_method("SwgMedicDrag",D_METHOD("crossed","head","left","right","tracked"),&SwgMedicDrag::crossed);
 ClassDB::bind_static_method("SwgMedicDrag",D_METHOD("both_touch","boxes","left","right"),&SwgMedicDrag::both_touch);
 ClassDB::bind_method(D_METHOD("sample","midpoint","grips","eligible","delta"),&SwgMedicDrag::sample);
 ClassDB::bind_method(D_METHOD("reset"),&SwgMedicDrag::reset);
}
bool SwgMedicDrag::crossed(const Transform3D &head,const Vector3 &left,const Vector3 &right,bool tracked){
 if(!tracked || !left.is_finite() || !right.is_finite() || !head.origin.is_finite())return false;
 auto inv=head.affine_inverse();auto l=inv.xform(left),r=inv.xform(right);
 // Head-local chest volume follows upright, kneeling and incapacitated viewpoints.
 return l.x>0.035 && r.x<-0.035 && l.x<0.45 && r.x>-0.45 &&
  l.y<-.12 && r.y<-.12 && l.y>-.65 && r.y>-.65 &&
  l.z<.08 && r.z<.08 && l.z>-.48 && r.z>-.48;
}
bool SwgMedicDrag::both_touch(const Array &boxes,const Vector3 &left,const Vector3 &right){
 if(!left.is_finite() || !right.is_finite())return false;
 bool a=false,b=false;for(int i=0;i<boxes.size() && i<96;++i){if(boxes[i].get_type()!=Variant::AABB)continue;AABB box=boxes[i];box=box.grow(.08);a|=box.has_point(left);b|=box.has_point(right);}
 return a && b;
}
Dictionary SwgMedicDrag::sample(const Vector3 &mid,bool grips,bool eligible,double dt){
 Dictionary out;out["start"]=false;out["active"]=false;out["delta"]=Vector3();
 if(!mid.is_finite() || !grips || !eligible || !std::isfinite(dt) || dt<=0 || dt>.25){engaged=false;return out;}
 if(!engaged){engaged=true;previous=mid;out["start"]=true;}else{Vector3 movement=mid-previous;previous=mid;
  if(movement.length()>float(3*dt+.05)){engaged=false;return out;}out["delta"]=movement;}
 out["active"]=true;return out;
}
