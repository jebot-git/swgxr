#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/transform3d.hpp>
namespace godot {
// SWG-style pursuit of the latest native goal; presentation never owns RPG state.
class SwgSnapshotMotion : public RefCounted {
 GDCLASS(SwgSnapshotMotion,RefCounted)
 Transform3D presented,goal;
 Vector3 velocity;
 double stamp=-1,current_speed=0,walk_speed=2.5,run_speed=7;
 bool initialized=false;
protected:
 static void _bind_methods();
public:
 bool push(const Transform3D &pose,double time,bool reset=false);
 bool push_goal(const Transform3D &pose,double time,double walk,double run,double speed,bool reset=false);
 Transform3D advance(double now,double delta);
 Vector3 get_velocity() const {return velocity;}
 double get_delay() const {return 0;}
};
}
