#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/skeleton3d.hpp>
#include <godot_cpp/classes/animation.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <unordered_map>
#include <vector>
namespace godot {
// Stateless, masked source animation blending. It deliberately never reads the
// current posed bones, which may already contain downstream tracking/foot IK.
class SwgBodyMotion : public RefCounted {
    GDCLASS(SwgBodyMotion, RefCounted)
    struct Pose { Vector3 position; Quaternion rotation; };
    struct Bone { int index; String name; Pose rest; };
    struct Track { int track; int bone; Animation::TrackType type; };
    struct Clip { Ref<Animation> resource; std::vector<Track> tracks; };
    uint64_t skeleton_id=0;
    int skeleton_bones=0;
    std::vector<Bone> bones;
    std::unordered_map<uint64_t,Clip> clips;
    int read_clip(const Ref<Animation> &animation, double time, std::vector<Pose> &pose);
protected:
    static void _bind_methods();
public:
    bool configure(Skeleton3D *skeleton);
    Dictionary sample(const Ref<Animation> &animation, double time,
                      const Ref<Animation> &from_animation=Ref<Animation>(), double from_time=0,
                      double blend=1, bool root_bob=true);
};
}
