#include "view_posture.h"
#include <godot_cpp/core/class_db.hpp>
#include <algorithm>
#include <cmath>

using namespace godot;
void SwgViewPosture::_bind_methods() {
    ClassDB::bind_method(D_METHOD("configure_jump", "curve"), &SwgViewPosture::configure_jump);
    ClassDB::bind_method(D_METHOD("reset"), &SwgViewPosture::reset);
    ClassDB::bind_method(D_METHOD("knock_down", "physical_posture"), &SwgViewPosture::knock_down);
    ClassDB::bind_method(D_METHOD("press_jump", "physical_posture", "grounded", "allowed"), &SwgViewPosture::press_jump);
    ClassDB::bind_method(D_METHOD("resolve_recovery", "success"), &SwgViewPosture::resolve_recovery);
    ClassDB::bind_method(D_METHOD("clear_knockdown"), &SwgViewPosture::clear_knockdown);
    ClassDB::bind_method(D_METHOD("advance", "delta", "physical_posture", "eye_height", "tracked"), &SwgViewPosture::advance);
    ClassDB::bind_method(D_METHOD("is_knocked_down"), &SwgViewPosture::is_knocked_down);
    ClassDB::bind_method(D_METHOD("get_view_offset"), &SwgViewPosture::get_view_offset);
    ClassDB::bind_method(D_METHOD("get_jump_time"), &SwgViewPosture::get_jump_time);
}
bool SwgViewPosture::configure_jump(const PackedVector2Array &curve) {
    if (curve.size() < 2 || curve[0].x != 0 || curve[curve.size()-1].x > 10) return false;
    double previous = -1;
    for (int i=0; i<curve.size(); ++i) {
        const Vector2 point = curve[i];
        if (!point.is_finite() || point.x <= previous || std::abs(point.y) > 2) return false;
        previous = point.x;
    }
    jump_curve = curve; return true;
}
void SwgViewPosture::reset() { jump_time = -1; offset = 0; knocked = pending = false; since_attempt = 1; }
bool SwgViewPosture::knock_down(int physical_posture) {
    if (physical_posture == 2 || knocked) return false;
    knocked = true; pending = false; jump_time = -1; since_attempt = 0;
    return true;
}
Dictionary SwgViewPosture::press_jump(int physical_posture, bool grounded, bool allowed) {
    Dictionary result; result["action"] = "none";
    if (!allowed || physical_posture < 0 || physical_posture > 3) return result;
    if (knocked) {
        // The pinned stand command rejects attempts less than 100 ms apart.
        if (pending || since_attempt < 0.1) return result;
        pending = true; since_attempt = 0;
        result["action"] = "recover";
        result["posture"] = physical_posture == 1 ? 1 : physical_posture == 2 ? 2 : 0;
    } else if (grounded && physical_posture == 0 && jump_time < 0 && jump_curve.size() >= 2) {
        jump_time = 0; result["action"] = "jump";
    }
    return result;
}
void SwgViewPosture::resolve_recovery(bool success) {
    if (!pending) return;
    pending = false;
    if (success) knocked = false;
}
Dictionary SwgViewPosture::advance(double delta, int physical_posture, double eye_height, bool tracked) {
    Dictionary result;
    result["auto_prone_recovery"] = false;
    if (!std::isfinite(delta) || delta < 0 || !std::isfinite(eye_height) || eye_height < 0 || !tracked) {
        result["offset"] = offset; result["knocked_down"] = knocked; return result;
    }
    since_attempt += delta;
    if (knocked && physical_posture == 2) {
        knocked = pending = false; result["auto_prone_recovery"] = true;
    }
    double desired = 0;
    if (knocked) desired = std::min(0.0, 0.35 - eye_height);
    else if (jump_time >= 0) {
        jump_time += delta;
        if (jump_time >= jump_curve[jump_curve.size()-1].x) jump_time = -1;
        else for (int i=1; i<jump_curve.size(); ++i) {
            if (jump_time <= jump_curve[i].x) {
                Vector2 a = jump_curve[i-1], b = jump_curve[i];
                desired = a.y + (b.y-a.y)*(jump_time-a.x)/(b.x-a.x); break;
            }
        }
    }
    offset += (desired-offset) * (1.0-std::exp(-18.0*delta));
    if (std::abs(offset) < 0.00001 && desired == 0) offset = 0;
    result["offset"] = offset; result["knocked_down"] = knocked;
    result["jump_time"] = jump_time; result["recovery_pending"] = pending;
    return result;
}
