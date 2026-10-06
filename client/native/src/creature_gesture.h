#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/transform3d.hpp>
namespace godot {
class SwgCreatureGesture: public RefCounted {
 GDCLASS(SwgCreatureGesture,RefCounted)
 String target,mode; bool latched=false,have=false,wide=false; int direction=0,strokes=0;
 double elapsed=0,held=0,last_motion=0,extreme=0; Vector3 previous,previous_world; int hand_index=-1;
 void interrupt();
protected: static void _bind_methods();
public:
 void reset();
 Dictionary sample(double dt,const String &id,const String &kind,const Transform3D &head,const Transform3D &left,const Transform3D &right,const Vector3 &anchor,bool tracked,bool allowed,double left_fist,double right_fist);
};
}
