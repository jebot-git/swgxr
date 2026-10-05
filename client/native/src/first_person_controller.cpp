#include "first_person_controller.h"
#include "ground_support.h"
#include <godot_cpp/core/object.hpp>
#include <cmath>

#include <godot_cpp/classes/capsule_shape3d.hpp>
#include <godot_cpp/classes/collision_shape3d.hpp>
#include <godot_cpp/classes/input.hpp>
#include <godot_cpp/classes/input_event_mouse_motion.hpp>
#include <godot_cpp/classes/kinematic_collision3d.hpp>
#include <godot_cpp/classes/physics_direct_space_state3d.hpp>
#include <godot_cpp/classes/physics_ray_query_parameters3d.hpp>
#include <godot_cpp/classes/world3d.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/math.hpp>

namespace godot {

void SwgFirstPersonController::_bind_methods() {
    ClassDB::bind_method(D_METHOD("get_ground_provider"), &SwgFirstPersonController::get_ground_provider);
    ClassDB::bind_method(D_METHOD("set_ground_provider", "provider"), &SwgFirstPersonController::set_ground_provider);
    ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "ground_provider", PROPERTY_HINT_NODE_TYPE, "Node3D"), "set_ground_provider", "get_ground_provider");
    ClassDB::bind_method(D_METHOD("reset_spawn"), &SwgFirstPersonController::reset_spawn);
    ClassDB::bind_method(D_METHOD("get_camera"), &SwgFirstPersonController::get_camera);
    ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "camera", PROPERTY_HINT_NODE_TYPE, "Camera3D"), "", "get_camera");
#define BIND_SETTING(type, field) \
    ClassDB::bind_method(D_METHOD("get_" #field), &SwgFirstPersonController::get_##field); \
    ClassDB::bind_method(D_METHOD("set_" #field, "value"), &SwgFirstPersonController::set_##field); \
    ADD_PROPERTY(PropertyInfo(type, #field), "set_" #field, "get_" #field);
    BIND_SETTING(Variant::BOOL, active)
    BIND_SETTING(Variant::BOOL, testing)
    BIND_SETTING(Variant::FLOAT, camera_pitch)
    BIND_SETTING(Variant::BOOL, third_person)
    BIND_SETTING(Variant::FLOAT, avatar_height)
    BIND_SETTING(Variant::INT, posture)
    ClassDB::bind_method(D_METHOD("request_posture", "posture"), &SwgFirstPersonController::request_posture);
    BIND_SETTING(Variant::FLOAT, camera_orbit_yaw)
    BIND_SETTING(Variant::FLOAT, presentation_height)
    BIND_SETTING(Variant::BOOL, movement_locked)
    ADD_SIGNAL(MethodInfo("cosmetic_jump_requested"));
    ADD_SIGNAL(MethodInfo("spawn_reset"));
    BIND_SETTING(Variant::FLOAT, speed)
    BIND_SETTING(Variant::FLOAT, max_step_height)
    BIND_SETTING(Variant::FLOAT, mouse_sensitivity)
    BIND_SETTING(Variant::VECTOR3, spawn_point)
    BIND_SETTING(Variant::FLOAT, spawn_yaw)
    BIND_SETTING(Variant::FLOAT, void_floor_y)
    ClassDB::bind_method(D_METHOD("clear_void_floor"), &SwgFirstPersonController::clear_void_floor);
    BIND_SETTING(Variant::VECTOR2, test_input)
#undef BIND_SETTING
    ClassDB::bind_method(D_METHOD("get_steps_taken"), &SwgFirstPersonController::get_steps_taken);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "steps_taken"), "", "get_steps_taken");
}

Node3D *SwgFirstPersonController::get_ground_provider() const {
    return Object::cast_to<Node3D>(ObjectDB::get_instance(ground_provider_id));
}
void SwgFirstPersonController::set_ground_provider(Node3D *value) {
    ground_provider_id=value?value->get_instance_id():0;
}

void SwgFirstPersonController::_ready() {
    set_name("Player");
    set_floor_snap_length(0.35);
    set_safe_margin(0.02);
    set_max_slides(12);
    set_floor_max_angle(Math::deg_to_rad(48.0));

    capsule.instantiate();
    capsule->set_radius(0.32);
    capsule->set_height(1.8);
    auto *collision = memnew(CollisionShape3D);
    collision->set_shape(capsule);
    collision->set_position(Vector3(0.0, 0.9, 0.0));
    add_child(collision);
    body_shape = collision;

    camera = memnew(Camera3D);
    camera->set_position(Vector3(0.0, 1.65, 0.0));
    camera->set_fov(78.0);
    camera->set_near(0.06);
    camera->set_far(3000.0);
    add_child(camera);
    camera->set_current(true);
    set_avatar_height(avatar_height);
    update_camera();
}

void SwgFirstPersonController::reset_spawn() {
    presentation_height = 0.0;
    movement_locked = false;
    stepped_last_frame = false;
    posture = 0;
    set_avatar_height(avatar_height);
    set_position(spawn_point);
    Vector3 rotation = get_rotation();
    rotation.y = spawn_yaw;
    set_rotation(rotation);
    pitch = 0.0;
    camera_orbit_yaw = 0.0;
    if (camera) {
        camera->set_rotation(Vector3());
    }
    set_velocity(Vector3());
    update_camera();
    emit_signal("spawn_reset");
}

void SwgFirstPersonController::_unhandled_input(const Ref<InputEvent> &event) {
    Ref<InputEventMouseMotion> motion = event;
    if (!active || motion.is_null() || !camera || Input::get_singleton()->get_mouse_mode() != Input::MOUSE_MODE_CAPTURED) {
        return;
    }
    const Vector2 relative = motion->get_relative();
    if (third_person && Input::get_singleton()->is_physical_key_pressed(KEY_ALT)) {
        camera_orbit_yaw -= relative.x * mouse_sensitivity;
    } else {
        rotate_y(-relative.x * mouse_sensitivity);
    }
    pitch = Math::clamp(pitch - relative.y * mouse_sensitivity, -1.48, 1.48);
    update_camera();
}

void SwgFirstPersonController::_physics_process(double delta) {
    if (!active) {
        update_camera();
        return;
    }
    Input *input = Input::get_singleton();
    const Vector2 move = testing ? test_input : input->get_vector("move_left", "move_right", "move_forward", "move_back");
    const Vector3 direction = get_global_transform().basis.xform(Vector3(move.x, 0.0, move.y));
    const double posture_speed = posture == 1 ? 0.4 : posture == 2 ? 0.18 : posture == 3 ? 0.0 : 1.0;
    const double actual_speed = movement_locked ? 0.0 : speed * posture_speed * (posture == 0 && !testing && input->is_action_pressed("sprint") ? 1.8 : 1.0);
    Vector3 velocity = get_velocity();
    velocity.x = direction.x * actual_speed;
    velocity.z = direction.z * actual_speed;
    const bool supported = is_on_floor() || stepped_last_frame;
    if (!supported) {
        velocity.y -= 20.0 * delta;
    } else {
        velocity.y = MIN(velocity.y, 0.0);
    }
    if (!testing && input->is_action_just_pressed("jump")) emit_signal("cosmetic_jump_requested");
    Vector3 horizontal_motion(velocity.x * delta, 0.0, velocity.z * delta);
    if (supported && velocity.y<=0.0 && delta>0.0) {
        Node3D *provider=get_ground_provider();
        if(provider && provider->has_method("collision_context")) {
            const Dictionary context=provider->call("collision_context",get_global_position()+horizontal_motion);
            const Array allowed=context.get("allowed_cell_ids",Array());
            Object *object=provider->get("ground_support");
            SwgGroundSupport *support=Object::cast_to<SwgGroundSupport>(object);
            if(support&&!allowed.is_empty()) {
                const Dictionary constraint=support->constrain_motion(get_global_position(),horizontal_motion,allowed,capsule->get_radius(),max_step_height);
                horizontal_motion=constraint.get("motion",horizontal_motion);
                velocity.x=horizontal_motion.x/delta;velocity.z=horizontal_motion.z/delta;
            }
        }
    }
    const Vector3 start_position = get_global_position();
    set_velocity(velocity);
    move_and_slide();
    // Detect actual blocked travel, including mesh-edge recovery contacts that
    // a standalone forward sweep can legitimately report as unobstructed.
    // Ordinary slopes and free walking stay on the engine's normal path.
    Vector3 travelled = get_global_position() - start_position;
    travelled.y = 0.0;
    const Vector3 direction_horizontal = horizontal_motion.normalized();
    const double blocked_distance = horizontal_motion.length() - travelled.dot(direction_horizontal);
    stepped_last_frame = false;
    if (supported && velocity.y <= 0.0 && blocked_distance > 0.005) {
        stepped_last_frame = try_step_up(direction_horizontal * blocked_distance);
    }
    if (stepped_last_frame) {
        Vector3 resumed = get_velocity();
        resumed.x = velocity.x;
        resumed.z = velocity.z;
        set_velocity(resumed);
    }
    update_camera();
    if (get_position().y < get_void_floor_y()) {
        reset_spawn();
    }
}

void SwgFirstPersonController::set_void_floor_y(double value) {
    if (!std::isfinite(value)) return;
    void_floor_y = value;
    custom_void_floor = true;
}

void SwgFirstPersonController::set_max_step_height(double value) {
    max_step_height = Math::clamp(value, 0.0, 0.6);
}

bool SwgFirstPersonController::try_step_up(const Vector3 &horizontal_motion) {
    if (max_step_height <= 0.0 || horizontal_motion.length_squared() < 0.00000001) {
        return false;
    }
    constexpr double clearance_margin = 0.005;
    const Transform3D start = get_global_transform();
    Ref<KinematicCollision3D> ceiling;
    ceiling.instantiate();
    double lift = max_step_height;
    if (test_move(start, Vector3(0.0, lift, 0.0), ceiling, clearance_margin)) {
        lift = MAX(0.0, ceiling->get_travel().y - clearance_margin);
    }
    if (lift <= clearance_margin) {
        return false;
    }
    Transform3D raised = start;
    raised.origin.y += lift;
    // Full capsule sweep rejects tall walls and obstructed head/shoulder space.
    if (test_move(raised, horizontal_motion, Ref<KinematicCollision3D>(), clearance_margin)) {
        return false;
    }
    raised.origin += horizontal_motion;
    Ref<KinematicCollision3D> support;
    support.instantiate();
    if (!test_move(raised, Vector3(0.0, -lift - get_floor_snap_length(), 0.0), support, clearance_margin)) {
        return false; // Never turn an unsupported ledge into a flying step.
    }
    // Capsule contacts at a tread edge have a diagonal normal even when the
    // tread itself is horizontal. Verify the actual surface just inside that
    // edge, rather than mistaking the capsule's rounded toe for a steep slope.
    const Vector3 toe = support->get_position() + horizontal_motion.normalized() * 0.04;
    Ref<PhysicsRayQueryParameters3D> query;
    query.instantiate();
    query->set_from(toe + Vector3(0.0, max_step_height + clearance_margin, 0.0));
    query->set_to(toe - Vector3(0.0, max_step_height + get_floor_snap_length(), 0.0));
    query->set_collision_mask(get_collision_mask());
    TypedArray<RID> excluded;
    excluded.push_back(get_rid());
    query->set_exclude(excluded);
    const Dictionary floor = get_world_3d()->get_direct_space_state()->intersect_ray(query);
    if (floor.is_empty()) {
        return false;
    }
    const Vector3 floor_normal = floor["normal"];
    const Vector3 floor_position = floor["position"];
    if (floor_normal.y < Math::cos(get_floor_max_angle()) ||
        floor_position.y - start.origin.y > max_step_height + clearance_margin) {
        return false;
    }
    const Vector3 target = raised.origin + support->get_travel();
    const double rise = target.y - start.origin.y;
    // While the rounded toe approaches a riser, a valid next tread can be
    // higher even when the capsule's supporting contact changes by only a
    // millimetre. Permit that bounded contact recovery, but require a genuinely
    // higher tread so this never becomes a general-purpose floor teleporter.
    if (floor_position.y - start.origin.y <= clearance_margin ||
        rise < -get_safe_margin() || rise > max_step_height + clearance_margin) {
        return false;
    }
    Transform3D landing = start;
    landing.origin = target;
    set_global_transform(landing);
    ++steps_taken;
    return true;
}

void SwgFirstPersonController::set_camera_pitch(double value) {
    pitch = Math::clamp(value, -1.48, 1.48);
    update_camera();
}

void SwgFirstPersonController::set_third_person(bool value) {
    third_person = value;
    update_camera();
}

void SwgFirstPersonController::set_avatar_height(double value) {
    avatar_height = Math::clamp(value, 1.0, 3.5);
    if (capsule.is_valid()) capsule->set_height(physical_height());
    if (body_shape) body_shape->set_position(Vector3(0.0, physical_height() * 0.5, 0.0));
    update_camera();
}

double SwgFirstPersonController::physical_height() const {
    const double ratio = posture == 1 ? 0.62 : posture == 2 ? 0.36 : posture == 3 ? 0.56 : 1.0;
    return MAX(0.64, avatar_height * ratio);
}

bool SwgFirstPersonController::request_posture(int value) {
    if (value < 0 || value > 3) return false;
    if (value == posture) return true;
    if (active && !is_on_floor() && !stepped_last_frame) return false;
    const int previous = posture;
    const double old_height = physical_height();
    posture = value;
    const double next_height = physical_height();
    posture = previous;
    // The full old capsule must fit the expansion toward the target top. This
    // prevents standing into ceilings while preserving the grounded foot point.
    if (is_inside_tree() && next_height > old_height && test_move(get_global_transform(), Vector3(0, next_height - old_height, 0), Ref<KinematicCollision3D>(), 0.005)) return false;
    posture = value;
    set_avatar_height(avatar_height);
    return true;
}

void SwgFirstPersonController::set_presentation_height(double value) {
    if (!std::isfinite(value)) return;
    presentation_height = CLAMP(value, -2.5, 2.0);
    update_camera();
}

void SwgFirstPersonController::update_camera() {
    if (!camera || !is_inside_tree()) return;
    const Vector3 pivot(0.0, physical_height() * (1.65 / 1.8) + presentation_height, 0.0);
    camera->set_cull_mask(third_person ? 3 : 1);
    if (!third_person) {
        // Original rigs place the torso around the capsule axis. A forward eye
        // offset keeps downward views outside the chest, within capsule bounds.
        camera->set_position(pivot + Vector3(0.0, 0.0, -MIN(0.25, avatar_height * 0.13)));
        camera->set_rotation(Vector3(pitch, 0.0, 0.0));
        return;
    }
    const Basis orbit = Basis(Vector3(0, 1, 0), camera_orbit_yaw) * Basis(Vector3(1, 0, 0), pitch);
    Vector3 desired = pivot + orbit.xform(Vector3(0, 0, avatar_height * 1.7));
    const Transform3D world = get_global_transform();
    Ref<PhysicsRayQueryParameters3D> query;
    query.instantiate();
    query->set_from(world.xform(pivot));
    query->set_to(world.xform(desired));
    query->set_collision_mask(get_collision_mask());
    TypedArray<RID> excluded;
    excluded.push_back(get_rid());
    query->set_exclude(excluded);
    const Dictionary hit = get_world_3d()->get_direct_space_state()->intersect_ray(query);
    if (!hit.is_empty()) {
        const Vector3 position = hit["position"];
        const Vector3 local_hit = world.affine_inverse().xform(position);
        desired = pivot + (desired - pivot).normalized() * MAX(0.1, pivot.distance_to(local_hit) - 0.18);
    }
    camera->set_position(desired);
    camera->set_rotation(Vector3(pitch, camera_orbit_yaw, 0.0));
}

}
