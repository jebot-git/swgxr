#include "tracked_ik.h"
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/object.hpp>
#include <godot_cpp/core/math.hpp>
#include <cmath>

using namespace godot;
namespace {
int mapped(Skeleton3D *skeleton, const Dictionary &mapping, const char *key, const char *fallback) {
    return skeleton->find_bone(String(mapping.get(key, fallback)));
}
bool descends(Skeleton3D *skeleton, int child, int ancestor) {
    while (child >= 0) {
        child = skeleton->get_bone_parent(child);
        if (child == ancestor) return true;
    }
    return false;
}
void global_rotation(Skeleton3D *skeleton, int bone, const Basis &rotation) {
    const int parent = skeleton->get_bone_parent(bone);
    Basis local = rotation;
    if (parent >= 0) local = skeleton->get_bone_global_pose(parent).basis.inverse() * rotation;
    skeleton->set_bone_pose_rotation(bone, local.orthonormalized().get_rotation_quaternion());
}
bool valid_target(const Transform3D &target) {
    return target.origin.is_finite() && target.basis.is_finite() && Math::abs(target.basis.determinant()) > 0.00001;
}
}

void SwgTrackedIK::_bind_methods() {
    ClassDB::bind_method(D_METHOD("configure", "skeleton", "mapping"), &SwgTrackedIK::configure, DEFVAL(Dictionary()));
    ClassDB::bind_method(D_METHOD("solve", "targets", "delta"), &SwgTrackedIK::solve);
    ClassDB::bind_method(D_METHOD("limit_hand_pair", "side", "target", "support"), &SwgTrackedIK::limit_hand_pair);
    ClassDB::bind_method(D_METHOD("limit_hand_target", "side", "target"), &SwgTrackedIK::limit_hand_target);
    ClassDB::bind_method(D_METHOD("reset_smoothing"), &SwgTrackedIK::reset_smoothing);
}
bool SwgTrackedIK::configure(Skeleton3D *skeleton, const Dictionary &mapping) {
    skeleton_id = 0;
    left = Arm();
    right = Arm();
    if (!skeleton) return false;
    head = mapped(skeleton, mapping, "head", "head");
    left.upper = mapped(skeleton, mapping, "left_upper", "larm");
    left.lower = mapped(skeleton, mapping, "left_lower", "lforearm");
    left.hand = mapped(skeleton, mapping, "left_hand", "lwrist");
    right.upper = mapped(skeleton, mapping, "right_upper", "rarm");
    right.lower = mapped(skeleton, mapping, "right_lower", "rforearm");
    right.hand = mapped(skeleton, mapping, "right_hand", "rwrist");
    if (head < 0) return false;
    for (Arm *arm : {&left, &right}) {
        if (arm->upper < 0 || arm->lower < 0 || arm->hand < 0 ||
            !descends(skeleton, arm->lower, arm->upper) || !descends(skeleton, arm->hand, arm->lower)) return false;
        arm->first_length = skeleton->get_bone_global_rest(arm->upper).origin.distance_to(skeleton->get_bone_global_rest(arm->lower).origin);
        arm->second_length = skeleton->get_bone_global_rest(arm->lower).origin.distance_to(skeleton->get_bone_global_rest(arm->hand).origin);
        arm->upper_pose = skeleton->get_bone_pose_rotation(arm->upper);
        arm->lower_pose = skeleton->get_bone_pose_rotation(arm->lower);
        arm->attached = false;
    }
    skeleton_id = skeleton->get_instance_id();
    return true;
}
Transform3D SwgTrackedIK::limit_hand_target(const String &side, const Transform3D &target) const {
    Skeleton3D *skeleton = Object::cast_to<Skeleton3D>(ObjectDB::get_instance(skeleton_id));
    if (!skeleton || !valid_target(target) || (side != "left" && side != "right")) return target;
    const Arm &arm = side == "left" ? left : right;
    if (arm.first_length < 0.0001 || arm.second_length < 0.0001) return target;
    const Vector3 shoulder = skeleton->get_bone_global_pose(arm.upper).origin;
    const Vector3 offset = target.origin - shoulder;
    const double requested = offset.length();
    const double reach = Math::clamp(requested, Math::abs(arm.first_length-arm.second_length)+0.0001,
                                     arm.first_length+arm.second_length-0.0001);
    Transform3D result = target;
    result.origin = shoulder + (requested > 0.00001 ? offset/requested : Vector3(0,0,-1))*reach;
    return result;
}
Transform3D SwgTrackedIK::limit_hand_pair(const String &side, const Transform3D &target, const Transform3D &support) const {
    if (!valid_target(target) || !valid_target(support)) return target;
    const String other = side == "left" ? "right" : "left";
    Vector3 shift;
    // Translate a rigid two-grip item into the intersection of both anatomical
    // reach volumes. Neither wrist, bone length nor weapon grip spacing changes.
    for (int i = 0; i < 64; ++i) {
        Transform3D main = target; main.origin += shift;
        shift += limit_hand_target(side, main).origin - main.origin;
        Transform3D off = support; off.origin += shift;
        const Vector3 correction = limit_hand_target(other, off).origin - off.origin;
        shift += correction;
        if (correction.length_squared() < 1e-12) break;
    }
    Transform3D result = target; result.origin += shift;
    return limit_hand_target(side, result);
}
void SwgTrackedIK::reset_smoothing() {
    left.have_bend = right.have_bend = false;
}
Dictionary SwgTrackedIK::solve_arm(Skeleton3D *skeleton, Arm &arm, const Transform3D &target,
                                 const Vector3 &pole, double delta, bool attached) {
    Dictionary result;
    if (arm.attached) {
        skeleton->set_bone_pose_position(arm.hand, arm.free_hand_position);
        arm.attached = false;
    }
    if (!valid_target(target) || !pole.is_finite()) { result["valid"] = false; return result; }
    // Start from the calibrated neutral arm every time: accumulated shortest
    // arc rotations otherwise introduce axial twist when targets circle around.
    skeleton->set_bone_pose_rotation(arm.upper, arm.upper_pose);
    skeleton->set_bone_pose_rotation(arm.lower, arm.lower_pose);
    Transform3D upper = skeleton->get_bone_global_pose(arm.upper);
    Transform3D lower = skeleton->get_bone_global_pose(arm.lower);
    Transform3D hand = skeleton->get_bone_global_pose(arm.hand);
    const double first = upper.origin.distance_to(lower.origin);
    const double second = lower.origin.distance_to(hand.origin);
    if (first < 0.0001 || second < 0.0001) { result["valid"] = false; return result; }
    const Vector3 difference = target.origin - upper.origin;
    const double requested = difference.length();
    const Vector3 direction = requested > 0.00001 ? difference / requested : Vector3(0, 0, -1);
    // Keep a tiny bend at full extension and avoid the folded zero-distance
    // singularity. No source bone translation or scale is changed.
    const double reach = Math::clamp(requested, Math::abs(first - second) + 0.0001, first + second - 0.0001);
    Vector3 bend = (pole - upper.origin).slide(direction);
    Vector3 previous = arm.bend.slide(direction);
    if (bend.length_squared() < 0.000001) bend = previous;
    if (bend.length_squared() < 0.000001) bend = Vector3(0, -1, 0).slide(direction);
    if (bend.length_squared() < 0.000001) bend = Vector3(1, 0, 0).slide(direction);
    bend.normalize();
    if (arm.have_bend && previous.length_squared() > 0.000001) {
        previous.normalize();
        const double alpha = 1.0 - std::exp(-18.0 * Math::clamp(delta, 0.0, 0.1));
        // Avoid a singular zero-vector lerp for exactly opposing poles.
        if (previous.dot(bend) > -0.95) bend = previous.lerp(bend, alpha).normalized();
        else bend = previous;
    }
    arm.bend = bend;
    arm.have_bend = true;
    const double along = (first * first - second * second + reach * reach) / (2.0 * reach);
    const double perpendicular = std::sqrt(MAX(0.0, first * first - along * along));
    const Vector3 elbow = upper.origin + direction * along + bend * perpendicular;
    const Vector3 endpoint = upper.origin + direction * reach;
    const Quaternion rotate_upper((lower.origin - upper.origin).normalized(), (elbow - upper.origin).normalized());
    global_rotation(skeleton, arm.upper, Basis(rotate_upper) * upper.basis);
    lower = skeleton->get_bone_global_pose(arm.lower);
    hand = skeleton->get_bone_global_pose(arm.hand);
    const Quaternion rotate_lower((hand.origin - lower.origin).normalized(), (endpoint - lower.origin).normalized());
    global_rotation(skeleton, arm.lower, Basis(rotate_lower) * lower.basis);
    global_rotation(skeleton, arm.hand, target.basis.orthonormalized());
    const double solver_error = skeleton->get_bone_global_pose(arm.hand).origin.distance_to(endpoint);
    if (attached) {
        // A mounted vehicle cannot move into the avatar's reach volume like a
        // held weapon. Preserve the solved elbow, but let the visual forearm
        // extend to its rigid grip. This never writes tracking or body physics.
        arm.free_hand_position = skeleton->get_bone_pose_position(arm.hand);
        const int parent = skeleton->get_bone_parent(arm.hand);
        const Transform3D parent_pose = parent >= 0 ? skeleton->get_bone_global_pose(parent) : Transform3D();
        skeleton->set_bone_pose_position(arm.hand, parent_pose.affine_inverse().xform(target.origin));
        arm.attached = true;
    }
    const Transform3D actual = skeleton->get_bone_global_pose(arm.hand);
    result["valid"] = true;
    result["clamped"] = Math::abs(reach - requested) > 0.00001;
    result["error"] = actual.origin.distance_to(target.origin);
    result["solver_error"] = solver_error;
    result["attached"] = attached;
    result["upper_length"] = first;
    result["lower_length"] = second;
    result["elbow"] = skeleton->get_bone_global_pose(arm.lower).origin;
    result["hand"] = actual;
    return result;
}
Dictionary SwgTrackedIK::solve(const Dictionary &targets, double delta) {
    Dictionary result;
    Skeleton3D *skeleton = Object::cast_to<Skeleton3D>(ObjectDB::get_instance(skeleton_id));
    if (!skeleton || !std::isfinite(delta)) { result["valid"] = false; return result; }
    result["valid"] = true;
    if (bool(targets.get("head_tracked", true)) && targets.has("head")) {
        Transform3D target = targets["head"];
        if (valid_target(target)) global_rotation(skeleton, head, target.basis.orthonormalized());
        else result["valid"] = false;
    }
    if (bool(targets.get("left_tracked", true)) && targets.has("left_hand")) {
        const Vector3 shoulder = skeleton->get_bone_global_pose(left.upper).origin;
        result["left"] = solve_arm(skeleton, left, targets["left_hand"], targets.get("left_pole", shoulder + Vector3(-0.35, -0.5, 0.1)), delta, bool(targets.get("left_hand_attached", false)));
    }
    if (bool(targets.get("right_tracked", true)) && targets.has("right_hand")) {
        const Vector3 shoulder = skeleton->get_bone_global_pose(right.upper).origin;
        result["right"] = solve_arm(skeleton, right, targets["right_hand"], targets.get("right_pole", shoulder + Vector3(0.35, -0.5, 0.1)), delta, bool(targets.get("right_hand_attached", false)));
    }
    return result;
}
