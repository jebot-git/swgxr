#include "performance_gesture.h"
#include <godot_cpp/core/class_db.hpp>
#include <cmath>
using namespace godot;
void SwgPerformanceGesture::_bind_methods() {
    ClassDB::bind_method(D_METHOD("reset"), &SwgPerformanceGesture::reset);
    ClassDB::bind_method(D_METHOD("sample", "delta", "kind", "head", "main", "off", "tracked"), &SwgPerformanceGesture::sample);
}
void SwgPerformanceGesture::reset() {
    have=false; mode=""; elapsed=held=0; last_stroke=-10; direction=0; axis=-1; strokes=0; last_hand=-1;
}
bool SwgPerformanceGesture::sample(double dt, const String &kind, const Transform3D &head, const Transform3D &main, const Transform3D &off, bool tracked) {
    if (!tracked || !std::isfinite(dt) || dt<=0 || dt>0.12 || !head.origin.is_finite() || !main.origin.is_finite() || !off.origin.is_finite() || !head.basis.is_finite() || std::abs(head.basis.determinant())<0.001) { reset(); return false; }
    Vector3 a=head.basis.inverse().xform(main.origin-head.origin), b=head.basis.inverse().xform(off.origin-head.origin);
    if (mode!=kind) { reset(); mode=kind; }
    if (!have) { previous_main=anchor=a; previous_off=b; key_top_main=a.y; key_top_off=b.y; have=true; return false; }
    Vector3 da=a-previous_main, db=b-previous_off;
    previous_main=a; previous_off=b;
    if (da.length()>0.5 || db.length()>0.5 || da.length()/dt>7 || db.length()/dt>7) { reset(); return false; }
    elapsed+=dt;
    if (elapsed-last_stroke>1.5) { strokes=0; direction=0; axis=-1; anchor=a; }
    if (kind=="wind") {
        // Grip/mouth proxy is deliberately forgiving across original horns.
        bool near=a.distance_to(Vector3(0,-0.10,-0.12))<0.24;
        held=near ? held+dt : 0;
        if (held>=0.4) { reset(); return true; }
        return false;
    }
    if (kind=="percussion") {
        double distance=a.distance_to(b);
        if (distance>0.32) held=1;
        if (held>0 && distance<0.25 && (db-da).length()/dt>0.5 && elapsed-last_stroke>0.12) {
            held=0; last_stroke=elapsed; ++strokes;
        }
    } else if (kind=="keyboard") {
        // Two alternating downward taps, one per hand, on the same key plane.
        int hand=da.y < db.y ? 0 : 1;
        double down=hand==0 ? -da.y : -db.y;
        key_top_main=std::max(key_top_main,double(a.y)); key_top_off=std::max(key_top_off,double(b.y));
        double travel=hand==0 ? key_top_main-a.y : key_top_off-b.y;
        if (travel>0.04 && std::abs(a.y-b.y)<0.18 && a.distance_to(b)>0.12 && a.distance_to(b)<0.8 && down/dt>0.25 && hand!=last_hand && elapsed-last_stroke>0.15) {
            last_hand=hand; last_stroke=elapsed; ++strokes;
            if (hand==0) key_top_main=a.y; else key_top_off=b.y;
        }
    } else if (kind=="strings" || kind=="dance") {
        Vector3 point=kind=="strings" ? b-a : a;
        Vector3 velocity=kind=="strings" ? db-da : da;
        if (kind=="strings" && point.length()>0.65) { strokes=0; direction=0; return false; }
        int candidate=kind=="strings" ? 1 : std::abs(velocity.x)>std::abs(velocity.y) ? 0 : 1;
        double speed=velocity[candidate]/dt;
        if (std::abs(speed)>0.2) {
            int next=speed>0 ? 1 : -1;
            if (direction==0 || candidate!=axis) { direction=next; axis=candidate; anchor=point; last_stroke=elapsed; }
            else if (next!=direction && std::abs(point[axis]-anchor[axis])>(kind=="dance" ? 0.14 : 0.06)) {
                ++strokes; direction=next; anchor=point; last_stroke=elapsed;
            }
        }
    }
    if (strokes>=2) { reset(); return true; }
    return false;
}
