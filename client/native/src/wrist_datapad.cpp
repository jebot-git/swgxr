#include "wrist_datapad.h"
#include <godot_cpp/core/class_db.hpp>
#include <algorithm>
#include <cmath>
using namespace godot;
void SwgWristDatapad::_bind_methods() {
    ClassDB::bind_method(D_METHOD("reset"), &SwgWristDatapad::reset);
    ClassDB::bind_method(D_METHOD("follow_view","head","size","delta","distance","frozen"), &SwgWristDatapad::follow_view, DEFVAL(0.75), DEFVAL(false));
    ClassDB::bind_method(D_METHOD("follow","mount","viewer","delta","pitch_limit","response"), &SwgWristDatapad::follow, DEFVAL(0.4363323129985824), DEFVAL(12.0));
    ClassDB::bind_method(D_METHOD("point","screen","size","pixels","tip","direction","reach","touch_depth"), &SwgWristDatapad::point, DEFVAL(0.65), DEFVAL(0.018));
}
void SwgWristDatapad::reset() { yaw=0;pitch=0;view_ready=false; }
Dictionary SwgWristDatapad::follow_view(const Transform3D &head,const Vector2 &size,double delta,double distance,bool frozen) {
    Dictionary out;out["valid"]=false;
    if(!head.origin.is_finite() || !head.basis.is_finite() || std::abs(head.basis.determinant())<1e-6 ||
       !size.is_finite() || size.x<=0 || size.y<=0 || !std::isfinite(delta) || !std::isfinite(distance) || distance<0.3)return out;
    const Vector3 forward=-head.basis.orthonormalized().get_column(2);
    const double heading=std::hypot(forward.x,forward.z)>1e-5?std::atan2(-forward.x,-forward.z):(view_ready?view_yaw:0);
    const double elevation=std::clamp(std::asin(std::clamp<double>(forward.y,-1,1)),-0.7853981634,0.7853981634);
    // Include every panel edge plus ten horizontal / eight vertical degrees.
    // A downward reading offset is also included in the vertical allowance.
    const double panel_pitch=view_ready?view_pitch:elevation;
    const double horizontal_depth=std::max(0.1,distance*std::cos(panel_pitch)-(size.y*.5+0.08)*std::abs(std::sin(panel_pitch)));
    const double yaw_limit=std::atan2(size.x*.5,horizontal_depth)+0.1745329252;
    const double pitch_limit=std::atan2(size.y*.5+0.08,distance)+0.1396263402;
    if(!view_ready) {view_anchor=head.origin;view_yaw=heading;view_pitch=elevation;view_ready=true;}
    else if(!frozen) {
        const double alpha=1-std::exp(-3.0*std::clamp(delta,0.0,0.1));
        const double turn=std::remainder(heading-view_yaw,6.28318530717958647692);
        const double tilt=elevation-view_pitch;
        view_yaw=std::remainder(view_yaw+(turn-std::clamp(turn,-yaw_limit,yaw_limit))*alpha,6.28318530717958647692);
        view_pitch+=(tilt-std::clamp(tilt,-pitch_limit,pitch_limit))*alpha;
        // Small head translations remain free; walking draws the panel along.
        const Vector3 offset=head.origin-view_anchor;
        if(offset.length()>0.12)view_anchor+=offset*(1-0.12/offset.length())*alpha;
    }
    const Basis facing=Basis(Vector3(0,1,0),view_yaw)*Basis(Vector3(1,0,0),view_pitch);
    out["valid"]=true;
    out["transform"]=Transform3D(facing,view_anchor-facing.get_column(2)*distance+Vector3(0,-0.08,0));
    out["anchor"]=view_anchor;out["yaw_limit"]=yaw_limit;out["pitch_limit"]=pitch_limit;
    return out;
}
Dictionary SwgWristDatapad::follow(const Transform3D &mount,const Vector3 &viewer,double delta,double limit,double response) {
    Dictionary out;out["valid"]=false;
    if(!mount.origin.is_finite()||!mount.basis.is_finite()||!viewer.is_finite()||std::abs(mount.basis.determinant())<1e-6||!std::isfinite(delta)||!std::isfinite(limit)||!std::isfinite(response))return out;
    const Basis base=mount.basis.orthonormalized();
    const Vector3 local=base.inverse().xform(viewer-mount.origin);
    if(local.length_squared()>1e-8) {
        const double desired_yaw=std::atan2(local.x,local.z);
        const double desired_pitch=std::clamp<double>(-std::atan2(local.y,std::hypot(local.x,local.z)),-std::abs(limit),std::abs(limit));
        const double alpha=1-std::exp(-std::max(0.0,response)*std::clamp(delta,0.0,0.1));
        yaw += std::remainder(desired_yaw-yaw,6.28318530717958647692)*alpha;
        yaw=std::remainder(yaw,6.28318530717958647692);
        pitch += (desired_pitch-pitch)*alpha;
    }
    out["valid"]=true;
    out["transform"]=Transform3D(base*Basis(Vector3(0,1,0),yaw)*Basis(Vector3(1,0,0),pitch),mount.origin);
    out["pitch"]=pitch;out["yaw"]=yaw;out["roll"]=0.0;
    return out;
}
Dictionary SwgWristDatapad::point(const Transform3D &screen,const Vector2 &size,const Vector2 &pixels,const Vector3 &tip,const Vector3 &direction,double reach,double depth) const {
    Dictionary out;out["valid"]=false;
    if(!size.is_finite()||!pixels.is_finite()||!std::isfinite(reach)||!std::isfinite(depth)||reach<0||depth<0||!tip.is_finite()||!direction.is_finite()||!screen.origin.is_finite()||!screen.basis.is_finite()||std::abs(screen.basis.determinant())<1e-6||size.x<=0||size.y<=0||pixels.x<=0||pixels.y<=0)return out;
    const Transform3D inverse=screen.affine_inverse();
    const Vector3 p=inverse.xform(tip), d=inverse.basis.xform(direction.normalized());
    Vector3 hit;double distance=0;bool touching=false;
    if(std::abs(p.z)<=depth&&std::abs(p.x)<=size.x*.5&&std::abs(p.y)<=size.y*.5) {hit=Vector3(p.x,p.y,0);touching=true;}
    else {
        if(p.z<0||d.z>=-1e-6)return out;
        distance=-p.z/d.z;
        if(distance<0||distance>reach)return out;
        hit=p+d*distance;
        if(std::abs(hit.x)>size.x*.5||std::abs(hit.y)>size.y*.5)return out;
    }
    out["valid"]=true;out["touching"]=touching;out["distance"]=distance;
    out["pixel"]=Vector2((hit.x/size.x+.5)*pixels.x,(.5-hit.y/size.y)*pixels.y);
    out["world"]=screen.xform(hit);return out;
}
