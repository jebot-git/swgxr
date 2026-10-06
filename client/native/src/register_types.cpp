#include "first_person_controller.h"
#include "swg_mesh_builder.h"
#include "cell_classifier.h"
#include "combat_collision.h"
#include "swg_terrain.h"
#include "xr_step_solver.h"
#include "tracked_ik.h"
#include "finger_retargeter.h"
#include "body_motion.h"
#include "virtual_skin_binding.h"
#include "interior_mask.h"
#include "ground_support.h"
#include "collision_builder.h"
#include "wrist_datapad.h"
#include "action_simulation.h"
#include "particle_batch.h"
#include "melee_swing.h"
#include "view_posture.h"
#include "performance_gesture.h"
#include "creature_gesture.h"
#include "ranger_gesture.h"
#include "salute_gesture.h"
#include "scout_locomotion.h"
#include "medic_drag.h"
#include "vehicle_controls.h"
#include "portal_visibility.h"
#include <gdextension_interface.h>
#include <godot_cpp/godot.hpp>

using namespace godot;

void initialize_swg_native(ModuleInitializationLevel level) {
    if (level != MODULE_INITIALIZATION_LEVEL_SCENE) return;
    ClassDB::register_class<SwgFirstPersonController>();
    ClassDB::register_class<SwgMeshBuilder>();
    ClassDB::register_class<SwgCellClassifier>();
    ClassDB::register_class<SwgCombatCollision>();
    ClassDB::register_class<SwgTerrainEvaluator>();
    ClassDB::register_class<SwgXRStepSolver>();
    ClassDB::register_class<SwgTrackedIK>();
    ClassDB::register_class<SwgFingerRetargeter>();
    ClassDB::register_class<SwgBodyMotion>();
    ClassDB::register_class<SwgVirtualSkinBinding>();
    ClassDB::register_class<SwgInteriorMask>();
    ClassDB::register_class<SwgGroundSupport>();
    ClassDB::register_class<SwgCollisionBuilder>();
    ClassDB::register_class<SwgWristDatapad>();
    ClassDB::register_class<SwgActionSimulation>();
    ClassDB::register_class<SwgParticleBatch>();
    ClassDB::register_class<SwgMeleeSwing>();
    ClassDB::register_class<SwgViewPosture>();
    ClassDB::register_class<SwgPerformanceGesture>();
    ClassDB::register_class<SwgCreatureGesture>();
    ClassDB::register_class<SwgRangerGesture>();
    ClassDB::register_class<SwgSaluteGesture>();
    ClassDB::register_class<SwgScoutLocomotion>();
    ClassDB::register_class<SwgMedicDrag>();
    ClassDB::register_class<SwgVehicleControls>();
    ClassDB::register_class<SwgPortalVisibility>();
}
void uninitialize_swg_native(ModuleInitializationLevel level) {
    (void)level;
}
extern "C" {
GDExtensionBool GDE_EXPORT swg_native_library_init(GDExtensionInterfaceGetProcAddress get_proc_address,
    GDExtensionClassLibraryPtr library, GDExtensionInitialization *initialization) {
    GDExtensionBinding::InitObject init(get_proc_address, library, initialization);
    init.register_initializer(initialize_swg_native);
    init.register_terminator(uninitialize_swg_native);
    init.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
    return init.init();
}
}
