#include "finger_retargeter.h"
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/object.hpp>
#include <godot_cpp/core/math.hpp>
#include <cmath>
using namespace godot;
namespace {
void set_global_basis(Skeleton3D *s, int bone, const Basis &basis) {
    const int parent=s->get_bone_parent(bone);
    const Basis parent_basis=parent>=0?s->get_bone_global_pose(parent).basis:Basis();
    s->set_bone_pose_rotation(bone,(parent_basis.inverse()*basis).orthonormalized().get_rotation_quaternion());
}
bool frame(const Vector3 &radial, const Vector3 &forward, Basis &output) {
    if (!radial.is_finite() || !forward.is_finite() || forward.length_squared()<1e-9) return false;
    const Vector3 y=forward.normalized();
    const Vector3 x=radial.slide(y).normalized();
    if(x.length_squared()<0.5) return false;
    output=Basis(x,y,x.cross(y));
    return true;
}
double input(const Dictionary &d,const char *key,double fallback=0) {
    const double value=d.get(key,fallback);
    return std::isfinite(value)?Math::clamp(value,0.0,1.0):fallback;
}
}
void SwgFingerRetargeter::_bind_methods() {
    ClassDB::bind_method(D_METHOD("configure","skeleton"),&SwgFingerRetargeter::configure);
    ClassDB::bind_method(D_METHOD("apply_controller","left","right"),&SwgFingerRetargeter::apply_controller);
    ClassDB::bind_method(D_METHOD("apply_hand_joints","side","joints"),&SwgFingerRetargeter::apply_hand_joints);
}
bool SwgFingerRetargeter::configure(Skeleton3D *s) {
    skeleton_id=0;
    if(!s)return false;
    for(int side=0;side<2;side++) {
        Hand &hand=side==0?left:right;
        const String prefix=side==0?"l":"r";
        hand.wrist=s->find_bone(prefix+String("wrist"));
        if(hand.wrist<0)return false;
        const Transform3D wrist=s->get_bone_global_pose(hand.wrist);
        const char *names[]={"thumb","index","ring"};
        Finger *fingers[]={&hand.thumb,&hand.index,&hand.ring};
        for(int i=0;i<3;i++) {
            Finger &f=*fingers[i];
            f.first=s->find_bone(prefix+String(names[i])+String("01")); f.second=s->find_bone(prefix+String(names[i])+String("02"));
            if(f.first<0||f.second<0||s->get_bone_parent(f.first)!=hand.wrist||s->get_bone_parent(f.second)!=f.first)return false;
            f.rest_first=s->get_bone_pose_rotation(f.first);f.rest_second=s->get_bone_pose_rotation(f.second);
            const Transform3D first=s->get_bone_global_pose(f.first),second=s->get_bone_global_pose(f.second);
            const Vector3 direction=(second.origin-first.origin).normalized();
            if(direction.length_squared()<0.5)return false;
            f.direction_first=first.basis.inverse().xform(direction).normalized();
            // The original rig has no distal/tip joint. Its terminal joint
            // therefore represents the combined final phalanges.
            f.direction_second=second.basis.inverse().xform(direction).normalized();
        }
        const Vector3 index=s->get_bone_global_pose(hand.index.first).origin;
        const Vector3 ring=s->get_bone_global_pose(hand.ring.first).origin;
        const Vector3 forward=(index+ring)*0.5-wrist.origin;
        if(!frame(wrist.basis.inverse().xform(index-ring),wrist.basis.inverse().xform(forward),hand.anatomy))return false;
        // Handedness is anatomical, not a species-specific Euler convention.
        hand.inward=hand.anatomy.get_column(2)*(side==0?-1.0:1.0);
    }
    skeleton_id=s->get_instance_id();return true;
}
Dictionary SwgFingerRetargeter::controller_hand(Skeleton3D *s,Hand &hand,const Dictionary &values) {
    const double grip=input(values,"grip"),trigger=input(values,"trigger");
    const double index=Math::clamp(trigger+(1.0-trigger)*input(values,"trigger_touch")*0.12,0.0,1.0);
    const double thumb=input(values,"thumb_curl",input(values,"thumb_touch"));
    Finger *fingers[]={&hand.thumb,&hand.index,&hand.ring};
    const double amounts[]={thumb,index,grip};
    const Transform3D wrist=s->get_bone_global_pose(hand.wrist);
    const Vector3 inward=wrist.basis.xform(hand.inward).normalized();
    for(int i=0;i<3;i++) {
        Finger &f=*fingers[i];
        s->set_bone_pose_rotation(f.first,f.rest_first);s->set_bone_pose_rotation(f.second,f.rest_second);
        const Transform3D first=s->get_bone_global_pose(f.first),second=s->get_bone_global_pose(f.second);
        const Vector3 direction=(second.origin-first.origin).normalized();
        Vector3 toward=inward;
        if(i==0) {
            const Vector3 palm=(s->get_bone_global_pose(hand.index.first).origin+s->get_bone_global_pose(hand.ring.first).origin)*0.5;
            toward=(palm-first.origin).normalized()+inward*0.6;
        }
        Vector3 axis=direction.cross(toward).normalized();
        if(axis.length_squared()<0.5)axis=wrist.basis.xform(hand.anatomy.get_column(0));
        set_global_basis(s,f.first,Basis(axis,amounts[i]*(i==0?0.65:1.22))*first.basis);
        const Basis second_basis=s->get_bone_global_pose(f.second).basis;
        set_global_basis(s,f.second,Basis(axis,amounts[i]*(i==0?1.0:1.5))*second_basis);
    }
    Dictionary result;result["thumb_curl"]=thumb;result["index_curl"]=index;result["ring_curl"]=grip;result["valid"]=true;return result;
}
Dictionary SwgFingerRetargeter::apply_controller(const Dictionary &left_input,const Dictionary &right_input) {
    Dictionary result;
    Skeleton3D *s=Object::cast_to<Skeleton3D>(ObjectDB::get_instance(skeleton_id));
    if(!s){result["valid"]=false;return result;}
    result["valid"]=true;result["left"]=controller_hand(s,left,left_input);result["right"]=controller_hand(s,right,right_input);
    result["independent_fingers"]=PackedStringArray({"thumb","index","ring"});
    result["unavailable_fingers"]=PackedStringArray({"middle","little"});return result;
}
Dictionary SwgFingerRetargeter::apply_hand_joints(const String &side,const Dictionary &joints) {
    Dictionary result;result["valid"]=false;
    Skeleton3D *s=Object::cast_to<Skeleton3D>(ObjectDB::get_instance(skeleton_id));
    if(!s||(side!="left"&&side!="right"))return result;
    Hand &hand=side=="left"?left:right;
    for(const char *name:{"index_proximal","index_intermediate","ring_proximal","ring_intermediate"})if(!joints.has(name)||joints[name].get_type()!=Variant::VECTOR3)return result;
    const Vector3 ip=joints["index_proximal"],rp=joints["ring_proximal"];
    Basis tracked;
    if(!frame(ip-rp,(ip+rp)*0.5,tracked))return result;
    const Basis target_map=s->get_bone_global_pose(hand.wrist).basis*hand.anatomy*tracked.inverse();
    const char *names[]={"thumb","index","ring"};
    Finger *fingers[]={&hand.thumb,&hand.index,&hand.ring};
    int applied=0;
    for(int i=0;i<3;i++) {
        Finger &f=*fingers[i];const String name=names[i];
        const String first_key=name+String(i==0?"_metacarpal":"_proximal"),second_key=name+String(i==0?"_proximal":"_intermediate"),last_key=name+String("_tip");
        if(!joints.has(first_key)||!joints.has(second_key)||!joints.has(last_key))continue;
        if(joints[first_key].get_type()!=Variant::VECTOR3||joints[second_key].get_type()!=Variant::VECTOR3||joints[last_key].get_type()!=Variant::VECTOR3)continue;
        const Vector3 first=joints[first_key],second=joints[second_key],last=joints[last_key];
        if(!first.is_finite()||!second.is_finite()||!last.is_finite()||first.distance_squared_to(second)<1e-9||second.distance_squared_to(last)<1e-9)continue;
        s->set_bone_pose_rotation(f.first,f.rest_first);s->set_bone_pose_rotation(f.second,f.rest_second);
        Basis basis=s->get_bone_global_pose(f.first).basis;
        Vector3 current=basis.xform(f.direction_first).normalized(),desired=target_map.xform(second-first).normalized();
        set_global_basis(s,f.first,Basis(Quaternion(current,desired))*basis);
        basis=s->get_bone_global_pose(f.second).basis;
        current=basis.xform(f.direction_second).normalized();desired=target_map.xform(last-second).normalized();
        set_global_basis(s,f.second,Basis(Quaternion(current,desired))*basis);
        applied++;
    }
    result["valid"]=applied>0;result["fingers_applied"]=applied;result["source"]="tracked_joint_positions";
    result["unavailable_fingers"]=PackedStringArray({"middle","little"});return result;
}
