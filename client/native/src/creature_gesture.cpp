#include "creature_gesture.h"
#include <godot_cpp/core/class_db.hpp>
#include <cmath>
#include <algorithm>
using namespace godot;
void SwgCreatureGesture::_bind_methods(){ClassDB::bind_method(D_METHOD("sample","delta","target","kind","head","left","right","anchor","tracked","allowed","left_fist","right_fist"),&SwgCreatureGesture::sample);ClassDB::bind_method(D_METHOD("reset"),&SwgCreatureGesture::reset);}
void SwgCreatureGesture::interrupt(){have=false;wide=false;direction=0;strokes=0;held=0;elapsed=0;last_motion=0;mode="";target="";hand_index=-1;}
void SwgCreatureGesture::reset(){interrupt();latched=false;}
Dictionary SwgCreatureGesture::sample(double dt,const String &id,const String &kind,const Transform3D &head,const Transform3D &left,const Transform3D &right,const Vector3 &anchor,bool tracked,bool allowed,double lf,double rf){
 Dictionary out;out["action"]="";out["progress"]=0.;out["mode"]="";out["latched"]=latched;
 if(!tracked||!std::isfinite(dt)||dt<=0||dt>.12||!head.origin.is_finite()||!left.origin.is_finite()||!right.origin.is_finite()||!head.basis.is_finite()||!left.basis.is_finite()||!right.basis.is_finite()||!std::isfinite(lf)||!std::isfinite(rf)){interrupt();return out;}
 Vector3 forward=-head.basis.get_column(2);forward.y=0;forward=forward.normalized();
 Vector3 l=left.origin-head.origin,r=right.origin-head.origin;
 bool fists=lf>=.7&&rf>=.7;
 bool up=fists&&l.y>.08&&r.y>.08&&l.y<.85&&r.y<.85&&left.origin.distance_to(right.origin)>.25;
 bool front=fists&&l.dot(forward)>.25&&r.dot(forward)>.25&&l.dot(forward)<.85&&r.dot(forward)<.85&&l.y>-.65&&r.y>-.65&&l.y<.05&&r.y<.05;
 bool neutral=!fists&&l.y<-.55&&r.y<-.55;
 if(neutral)latched=false;
 if(!allowed||id.is_empty()||latched){interrupt();out["latched"]=latched;return out;}
 String next=kind; double duration=10;
 if(kind=="buff") {next=up?"ch_enrage":front?"ch_embolden":"";duration=1;}
 if(kind=="mount"){next="ch_train_mount";duration=5;}
 if(next.is_empty()){interrupt();return out;}
 if(target!=id||mode!=next){interrupt();target=id;mode=next;}
 elapsed+=dt;bool valid=true,moved=false;
 if(kind=="tame"){
  bool lzone=l.y>-.65&&l.y<.2&&l.dot(forward)>.1&&l.length()<1.1;
  bool rzone=r.y>-.65&&r.y<.2&&r.dot(forward)>.1&&r.length()<1.1;
  bool zone=lzone||rzone;
  if(!zone||fists){interrupt();return out;}
  double separation=left.origin.distance_to(right.origin);
  if(lzone&&rzone&&separation>.4)wide=true;
  if(lzone&&rzone&&separation<.18&&wide){moved=true;wide=false;}
  // Beckoning requires repeated fore/aft reversals, never a stationary raised hand.
  double depth=(rzone?r:l).dot(forward);
  if(!have){extreme=depth;have=true;}
  if(direction==0&&std::abs(depth-extreme)>.14){direction=depth>extreme?1:-1;extreme=depth;moved=true;}
  else if(direction>0){if(depth>extreme)extreme=depth;else if(extreme-depth>.14){direction=-1;extreme=depth;moved=true;}}
  else if(direction<0){if(depth<extreme)extreme=depth;else if(depth-extreme>.14){direction=1;extreme=depth;moved=true;}}
 }else if(kind=="mount"){
  double ld=left.origin.distance_to(anchor),rd=right.origin.distance_to(anchor);
  Vector3 hand=ld<rd?left.origin:right.origin;valid=anchor.is_finite()&&std::min(ld,rd)<.25&&((ld<rd?lf:rf)<.5);
  if(!valid){interrupt();return out;}
  int chosen=ld<rd?0:1;
  if(hand_index>=0&&chosen!=hand_index){interrupt();return out;}hand_index=chosen;
  Vector3 relative=hand-anchor;
  if(!have){previous=relative;previous_world=hand;have=true;}
  // Accumulate meaningful stroking displacement; submillimetre tracking jitter is ignored.
  double travel=relative.distance_to(previous);
  double physical_travel=hand.distance_to(previous_world);
  if(travel>.07&&travel<.3&&physical_travel>.07&&physical_travel<.3){moved=true;previous=relative;previous_world=hand;}
  else if(travel>=.3){interrupt();return out;}
 }
 if(kind=="buff"){held+=dt;}
 else{
  if(moved){last_motion=elapsed;strokes++;}
  if(strokes==0||elapsed-last_motion>1.0){held=0;if(elapsed-last_motion>1.)strokes=0;}
  else held+=dt;
 }
 out["mode"]=mode;out["progress"]=std::min(1.,held/duration);
 if(held+1e-5>=duration&&(kind=="buff"||strokes>=(kind=="mount"?6:10))){out["action"]=kind=="tame"?String("ch_tame"):mode;latched=true;out["latched"]=true;}
 return out;
}
