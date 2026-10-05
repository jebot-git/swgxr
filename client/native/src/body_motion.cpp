#include "body_motion.h"
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/object.hpp>
#include <godot_cpp/core/math.hpp>
#include <cmath>
using namespace godot;

void SwgBodyMotion::_bind_methods() {
    ClassDB::bind_method(D_METHOD("configure","skeleton"),&SwgBodyMotion::configure);
    ClassDB::bind_method(D_METHOD("sample","animation","time","from_animation","from_time","blend","root_bob"),
                        &SwgBodyMotion::sample,DEFVAL(Ref<Animation>()),DEFVAL(0.0),DEFVAL(1.0),DEFVAL(true));
}
bool SwgBodyMotion::configure(Skeleton3D *skeleton) {
    skeleton_id=0;bones.clear();clips.clear();
    if(!skeleton)return false;
    for(const char *name:{"root","spine1","spine2","spine3","lthigh","lshin","lankle","ltoe","rthigh","rshin","rankle","rtoe"}) {
        const int index=skeleton->find_bone(name);
        if(index<0)continue;
        const Transform3D rest=skeleton->get_bone_rest(index);
        bones.push_back({index,String(name),{rest.origin,rest.basis.orthonormalized().get_rotation_quaternion()}});
    }
    if(bones.empty())return false;
    skeleton_id=skeleton->get_instance_id();skeleton_bones=skeleton->get_bone_count();return true;
}
int SwgBodyMotion::read_clip(const Ref<Animation> &animation,double time,std::vector<Pose> &pose) {
    pose.clear();for(const Bone &bone:bones)pose.push_back(bone.rest);
    if(animation.is_null())return 0;
    const uint64_t id=animation->get_instance_id();
    auto found=clips.find(id);
    if(found==clips.end()) {
        Clip clip;clip.resource=animation;
        for(int track=0;track<animation->get_track_count();track++) {
            const auto type=animation->track_get_type(track);
            if(type!=Animation::TYPE_POSITION_3D&&type!=Animation::TYPE_ROTATION_3D)continue;
            const NodePath path=animation->track_get_path(track);
            if(path.get_subname_count()==0)continue;
            const String name=path.get_subname(path.get_subname_count()-1);
            for(size_t bone=0;bone<bones.size();bone++)if(bones[bone].name==name) {
                clip.tracks.push_back({track,static_cast<int>(bone),type});break;
            }
        }
        found=clips.emplace(id,std::move(clip)).first;
    }
    const double length=animation->get_length();
    if(animation->get_loop_mode()==Animation::LOOP_LINEAR&&length>0)time=Math::fposmod(time,length);
    else if(animation->get_loop_mode()==Animation::LOOP_PINGPONG&&length>0) {
        time=Math::fposmod(time,2.0*length);if(time>length)time=2.0*length-time;
    } else time=Math::clamp(time,0.0,length);
    int sampled=0;
    for(const Track &track:found->second.tracks) {
        if(!animation->track_is_enabled(track.track)||animation->track_get_key_count(track.track)==0)continue;
        if(track.type==Animation::TYPE_POSITION_3D) {
            const Vector3 position=animation->position_track_interpolate(track.track,time);
            if(position.is_finite())pose[track.bone].position=position;else continue;
        } else {
            const Quaternion rotation=animation->rotation_track_interpolate(track.track,time);
            if(rotation.is_finite()&&rotation.length_squared()>0.000001)pose[track.bone].rotation=rotation.normalized();else continue;
        }
        sampled++;
    }
    return sampled;
}
Dictionary SwgBodyMotion::sample(const Ref<Animation> &animation,double time,
                                const Ref<Animation> &from_animation,double from_time,double blend,bool root_bob) {
    Dictionary result;result["valid"]=false;
    Skeleton3D *skeleton=Object::cast_to<Skeleton3D>(ObjectDB::get_instance(skeleton_id));
    if(!skeleton||skeleton->get_bone_count()!=skeleton_bones||!std::isfinite(time)||!std::isfinite(from_time)||!std::isfinite(blend))return result;
    blend=Math::clamp(blend,0.0,1.0);
    std::vector<Pose> target,source;
    const int target_tracks=read_clip(animation,time,target);
    const int source_tracks=read_clip(from_animation,from_time,source);
    PackedStringArray written;
    for(size_t i=0;i<bones.size();i++) {
        Vector3 position=source[i].position.lerp(target[i].position,blend);
        const Quaternion rotation=source[i].rotation.slerp(target[i].rotation,blend).normalized();
        if(bones[i].name==String("root")) {
            position.x=bones[i].rest.position.x;position.z=bones[i].rest.position.z;
            if(!root_bob)position.y=bones[i].rest.position.y;
        }
        skeleton->set_bone_pose_position(bones[i].index,position);
        skeleton->set_bone_pose_rotation(bones[i].index,rotation);
        written.push_back(bones[i].name);
    }
    result["valid"]=true;result["bones_written"]=written;result["target_tracks"]=target_tracks;
    result["source_tracks"]=source_tracks;result["blend"]=blend;result["root_bob"]=root_bob;
    result["root_horizontal_motion_suppressed"]=true;return result;
}
