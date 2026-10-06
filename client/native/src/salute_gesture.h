#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/transform3d.hpp>
namespace godot {
class SwgSaluteGesture: public RefCounted {
 GDCLASS(SwgSaluteGesture,RefCounted)
 String target;double held=0;bool latched=false;Vector3 facing;
 void interrupt();
protected:static void _bind_methods();
public:void reset();Dictionary sample(double dt,const String &id,const Transform3D &head,const Vector3 &hand,bool right_hand,bool open_hand,bool tracked,bool allowed);
};
}
