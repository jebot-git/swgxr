#pragma once

#include <godot_cpp/classes/character_body3d.hpp>
#include <godot_cpp/classes/camera3d.hpp>
#include <godot_cpp/classes/input_event.hpp>
#include <godot_cpp/classes/capsule_shape3d.hpp>
#include <godot_cpp/classes/collision_shape3d.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include "xr_step_solver.h"

namespace godot {

// Engine-facing shell around reusable native locomotion state. No SWG protocol,
// asset paths, UI, or backend assumptions belong in this controller.
class SwgFirstPersonController : public CharacterBody3D {
    GDCLASS(SwgFirstPersonController, CharacterBody3D)

    Camera3D *camera = nullptr;
    uint64_t ground_provider_id = 0;
    CollisionShape3D *body_shape = nullptr;
    Ref<CapsuleShape3D> capsule;
    Ref<SwgXRStepSolver> terrain_solver;
    bool terrain_grounded = false;
    bool third_person = false;
    double avatar_height = 1.8;
    int posture = 0; // 0 standing, 1 kneeling/crouched, 2 prone, 3 sitting.
    double physical_height() const;
    double camera_orbit_yaw = 0.0;
    double presentation_height = 0.0;
    bool movement_locked = false;
    void update_camera();
    bool active = false;
    bool testing = false;
    double pitch = 0.0;
    double speed = 5.2;
    double max_step_height = 0.35;
    int64_t steps_taken = 0;
    bool stepped_last_frame = false;
    bool try_step_up(const Vector3 &horizontal_motion);
    double mouse_sensitivity = 0.0022;
    Vector3 spawn_point;
    double spawn_yaw = 0.0;
    bool custom_void_floor = false;
    double void_floor_y = -4096.0;
    Vector2 test_input;

protected:
    static void _bind_methods();

public:
    void _ready() override;
    void _physics_process(double delta) override;
    void _unhandled_input(const Ref<InputEvent> &event) override;
    void reset_spawn();
    Node3D *get_ground_provider() const;
    void set_ground_provider(Node3D *value);
    // By default retain the bounded-stage spawn-minus-80 guard. Planet clients
    // can explicitly choose an absolute local floor below all valid terrain.
    double get_void_floor_y() const { return custom_void_floor ? void_floor_y : spawn_point.y - 80.0; }
    void set_void_floor_y(double value);
    void clear_void_floor() { custom_void_floor = false; }
    Camera3D *get_camera() const { return camera; }
    double get_camera_pitch() const { return pitch; }
    void set_camera_pitch(double value);
    bool get_third_person() const { return third_person; }
    void set_third_person(bool value);
    double get_avatar_height() const { return avatar_height; }
    void set_avatar_height(double value);
    int get_posture() const { return posture; }
    void set_posture(int value) { request_posture(value); }
    bool request_posture(int value);
    double get_camera_orbit_yaw() const { return camera_orbit_yaw; }
    void set_camera_orbit_yaw(double value) { camera_orbit_yaw = value; update_camera(); }
    double get_presentation_height() const { return presentation_height; }
    void set_presentation_height(double value);
    bool get_movement_locked() const { return movement_locked; }
    void set_movement_locked(bool value) { movement_locked = value; }

    bool get_grounded() const { return terrain_grounded || is_on_floor(); }
    bool get_active() const { return active; }
    void set_active(bool value) { active = value; }
    bool get_testing() const { return testing; }
    void set_testing(bool value) { testing = value; }
    int64_t get_steps_taken() const { return steps_taken; }
    double get_max_step_height() const { return max_step_height; }
    void set_max_step_height(double value);
    double get_speed() const { return speed; }
    void set_speed(double value) { speed = value; }
    double get_mouse_sensitivity() const { return mouse_sensitivity; }
    void set_mouse_sensitivity(double value) { mouse_sensitivity = value; }
    Vector3 get_spawn_point() const { return spawn_point; }
    void set_spawn_point(Vector3 value) { spawn_point = value; }
    double get_spawn_yaw() const { return spawn_yaw; }
    void set_spawn_yaw(double value) { spawn_yaw = value; }
    Vector2 get_test_input() const { return test_input; }
    void set_test_input(Vector2 value) { test_input = value; }
};
}
