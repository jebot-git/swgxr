extends SceneTree
func _initialize():call_deferred('run')
func run():
 var evaluator=SwgTerrainEvaluator.new()
 assert(evaluator.configure(JSON.parse_string(FileAccess.get_file_as_string(ProjectSettings.globalize_path('res://../runtime/assets/terrain/tatooine.json')))))
 var data=evaluator.build_chunk(3520,-4864,128,64)
 var body=StaticBody3D.new()
 var shape=CollisionShape3D.new()
 shape.shape=SwgMeshBuilder.new().create_terrain_collision(data)
 body.add_child(shape);root.add_child(body)
 var player=SwgFirstPersonController.new();root.add_child(player)
 player.testing=true;player.active=true;player.spawn_point=Vector3(64,400,-64)
 player.reset_spawn();player.position=Vector3(64,6,-64)
 for i in range(3):await physics_frame
 var legacy_reset=player.position.y>350
 player.void_floor_y=-4096.0
 player.position=Vector3(64,6,-64);player.velocity=Vector3.ZERO
 for i in range(90):await physics_frame
 var valley_grounded=player.is_on_floor() and abs(player.position.y-5.0)<.04
 var valley_y=player.position.y
 var override_preserved=player.void_floor_y==-4096.0
 player.position=Vector3(64,-4097,-64);player.velocity=Vector3.ZERO
 for i in range(3):await physics_frame
 var absolute_void_resets=player.position.y>350 and player.void_floor_y==-4096.0
 player.clear_void_floor();player.position=Vector3(64,6,-64);player.velocity=Vector3.ZERO
 for i in range(3):await physics_frame
 var legacy_restored=player.position.y>350 and player.void_floor_y==320.0
 var result={'test':'actual_terrain_valley_void_guard','legacy_reset':legacy_reset,'valley_grounded':valley_grounded,'valley_y':valley_y,'spawn_y':400,'override_preserved':override_preserved,'absolute_void_resets':absolute_void_resets,'legacy_restored':legacy_restored}
 result.success=legacy_reset and valley_grounded and override_preserved and absolute_void_resets and legacy_restored
 FileAccess.open(ProjectSettings.globalize_path('res://../runtime/terrain/controller-void-floor.json'),FileAccess.WRITE).store_string(JSON.stringify(result,'  '));print(JSON.stringify(result));print('TERRAIN_VOID_FLOOR_PASS' if result.success else 'TERRAIN_VOID_FLOOR_FAIL');quit(0 if result.success else 1)
