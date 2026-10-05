#include "xr_step_solver.h"
#include <godot_cpp/classes/kinematic_collision3d.hpp>
#include <godot_cpp/classes/physics_direct_space_state3d.hpp>
#include <godot_cpp/classes/physics_ray_query_parameters3d.hpp>
#include <godot_cpp/classes/world3d.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/math.hpp>
#include <cmath>

using namespace godot;
namespace {
constexpr double MARGIN = 0.001;
constexpr double MOTION_EPSILON = 1e-7;
bool valid(CharacterBody3D *body) {
    return body && body->is_inside_tree() && body->get_world_3d().is_valid();
}
Dictionary tread(CharacterBody3D *body, const Vector3 &point, double up, double down) {
    Ref<PhysicsRayQueryParameters3D> query;
    query.instantiate();
    query->set_from(point + Vector3(0, up, 0));
    query->set_to(point - Vector3(0, down, 0));
    query->set_collision_mask(body->get_collision_mask());
    TypedArray<RID> excluded;
    excluded.push_back(body->get_rid());
    query->set_exclude(excluded);
    return body->get_world_3d()->get_direct_space_state()->intersect_ray(query);
}
bool walkable(CharacterBody3D *body, const Dictionary &hit) {
    if (hit.is_empty()) return false;
    const Vector3 normal = hit["normal"];
    return normal.y >= Math::cos(body->get_floor_max_angle());
}
}

void SwgXRStepSolver::_bind_methods() {
    ClassDB::bind_method(D_METHOD("has_support", "body", "distance"), &SwgXRStepSolver::has_support, DEFVAL(0.1));
    ClassDB::bind_method(D_METHOD("step_up", "body", "motion", "maximum"), &SwgXRStepSolver::step_up, DEFVAL(0.35));
    ClassDB::bind_method(D_METHOD("step_down", "body", "maximum"), &SwgXRStepSolver::step_down, DEFVAL(0.35));
}

bool SwgXRStepSolver::has_support(CharacterBody3D *body, double distance) const {
    if (!valid(body) || !std::isfinite(distance)) return false;
    distance = Math::clamp(distance, 0.0, 0.15);
    Ref<KinematicCollision3D> support;
    support.instantiate();
    if (!body->test_move(body->get_global_transform(), Vector3(0, -distance, 0), support, MARGIN)) return false;
    // A rounded capsule toe may report a diagonal contact normal. Check the
    // original floor face at that contact instead of accepting a vertical wall.
    const Dictionary hit = tread(body, support->get_position(), distance + MARGIN, distance + MARGIN);
    if (!walkable(body, hit)) return false;
    const Vector3 position = hit["position"];
    return body->get_global_position().y - position.y <= distance + MARGIN;
}

bool SwgXRStepSolver::step_up(CharacterBody3D *body, const Vector3 &input_motion, double maximum) const {
    if (!valid(body) || !std::isfinite(maximum) || !input_motion.is_finite()) return false;
    maximum = Math::clamp(maximum, 0.0, 0.35);
    Vector3 motion(input_motion.x, 0, input_motion.z);
    if (motion.length_squared() < MOTION_EPSILON * MOTION_EPSILON || maximum <= MOTION_EPSILON) return false;
    const Transform3D start = body->get_global_transform();
    Ref<KinematicCollision3D> ceiling;
    ceiling.instantiate();
    double lift = maximum;
    if (body->test_move(start, Vector3(0, lift, 0), ceiling, MARGIN))
        lift = MAX(0.0, ceiling->get_travel().y - MARGIN);
    if (lift <= MOTION_EPSILON) return false;
    Transform3D raised = start;
    raised.origin.y += lift;
    if (body->test_move(raised, motion, Ref<KinematicCollision3D>(), MARGIN)) return false;
    raised.origin += motion;
    Ref<KinematicCollision3D> support;
    support.instantiate();
    if (!body->test_move(raised, Vector3(0, -lift - 0.1, 0), support, MARGIN)) return false;
    const Vector3 toe = support->get_position() + motion.normalized() * 0.04;
    const Dictionary hit = tread(body, toe, maximum + MARGIN, maximum + 0.1);
    if (!walkable(body, hit)) return false;
    const Vector3 floor = hit["position"];
    const Vector3 target = raised.origin + support->get_travel();
    const double tread_rise = floor.y - start.origin.y;
    const double rise = target.y - start.origin.y;
    if (tread_rise <= MOTION_EPSILON || tread_rise > lift + MARGIN ||
        rise < -body->get_safe_margin() || rise > maximum + MARGIN) return false;
    Transform3D landed = start;
    landed.origin = target;
    body->set_global_transform(landed);
    return true;
}

bool SwgXRStepSolver::step_down(CharacterBody3D *body, double maximum) const {
    if (!valid(body) || !std::isfinite(maximum)) return false;
    maximum = Math::clamp(maximum, 0.0, 0.35);
    if (maximum <= MOTION_EPSILON) return false;
    Ref<KinematicCollision3D> support;
    support.instantiate();
    const Transform3D start = body->get_global_transform();
    if (!body->test_move(start, Vector3(0, -maximum, 0), support, MARGIN)) return false;
    const Dictionary hit = tread(body, support->get_position(), maximum + MARGIN, maximum + MARGIN);
    if (!walkable(body, hit)) return false;
    const Vector3 movement = support->get_travel();
    if (movement.y >= -MOTION_EPSILON || movement.y < -maximum - MARGIN) return false;
    Transform3D landed = start;
    landed.origin += movement;
    body->set_global_transform(landed);
    return true;
}
