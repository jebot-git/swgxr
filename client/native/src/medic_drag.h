#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/transform3d.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/array.hpp>
namespace godot {
class SwgMedicDrag : public RefCounted {
 GDCLASS(SwgMedicDrag, RefCounted)
 bool engaged=false;
 Vector3 previous;
protected: static void _bind_methods();
public:
 static bool crossed(const Transform3D &head,const Vector3 &left,const Vector3 &right,bool tracked);
 static bool both_touch(const Array &boxes,const Vector3 &left,const Vector3 &right);
 Dictionary sample(const Vector3 &midpoint,bool grips,bool eligible,double delta);
 void reset(){engaged=false;}
};
}
