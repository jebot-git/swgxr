#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/transform3d.hpp>
namespace godot {
class SwgRangerGesture:public RefCounted{
 GDCLASS(SwgRangerGesture,RefCounted)
 String mode,target;bool latched=false,have=false,reversed=false;int direction=0;double held=0,last_yaw=0,yaw=0,low=0,high=0,travel=0;
 void interrupt();
protected:static void _bind_methods();
public:void reset();Dictionary sample(double delta,const String &kind,const String &id,const Transform3D &head,const Vector3 &left,const Vector3 &right,bool pointing,bool tracked,bool allowed);
};
}
