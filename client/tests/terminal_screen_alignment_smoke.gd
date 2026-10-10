extends SceneTree
var checks:=0
var failures:Array=[]
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures.append(label);push_error(label)
func _initialize():call_deferred("run")
func run():
 root.size=Vector2i(1400,1000)
 var world:=Node3D.new();root.add_child(world)
 var scenery=preload("res://scripts/service_world.gd").new();world.add_child(scenery);scenery.configure(Vector3.ZERO)
 var rig:=XROrigin3D.new();world.add_child(rig)
 var camera:=XRCamera3D.new();camera.name="XRCamera3D";rig.add_child(camera);camera.position=Vector3(.2,1.55,-1.7);camera.look_at(Vector3(0,1.45,0));camera.current=true
 var environment:=Environment.new();environment.background_mode=Environment.BG_COLOR;environment.background_color=Color(.12,.14,.16);environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.ambient_light_color=Color.WHITE;environment.ambient_light_energy=1;camera.environment=environment
 var body:=CharacterBody3D.new();world.add_child(body)
 var ui=preload("res://scripts/xr_services.gd").new();world.add_child(ui);ui.configure(rig,body);ui.set_process(false);ui.set_allowed(true)
 for kind in ["bank","bazaar"]:
  var template="object/tangible/terminal/terminal_"+kind+".iff"
  var record={"id":"fixture","kind":kind,"name":kind.capitalize()+" Terminal","template":template,"position":Vector3.ZERO}
  var displays=scenery.screen_surfaces(record)
  check(not displays.is_empty(),kind+" original glass measured")
  record.ui_displays=displays;record.ui_anchors=scenery.screen_offsets(record);record.pick_geometry=scenery.terminal_pick_geometry(record);record.pick_pose=Transform3D.IDENTITY
  var shared=record.duplicate();shared.template=template.replace("/terminal_","/shared_terminal_")
  check(scenery.terminal_pick_geometry(shared).has("bounds"),kind+" shared template resolves original casing")
  check(scenery.screen_surfaces(shared)==displays,kind+" shared template resolves same glass")
  for yaw in [0.0,1.1,PI]:
   var transformed=record.duplicate(true);var object_pose=Transform3D(Basis(Vector3.UP,yaw),Vector3(3,2,-4));transformed.ui_displays=[]
   for display:Dictionary in displays:transformed.ui_displays.append({"pose":object_pose*display.pose,"size":display.size,"area":display.area})
   for size in [ui.PANEL_METERS,Vector2(.59,.66)]:
    var pose=ui.terminal_pose(transformed,Vector3.ZERO,object_pose*Vector3(0,1.1,-1),size)
    var glass:Transform3D=transformed.ui_displays[0].pose
    for x in [-1,1]:
     for y in [-1,1]:
      var local=glass.affine_inverse()*(pose*Vector3(size.x*x*.5,size.y*y*.5,0))
      check(absf(local.x)<=displays[0].size.x*.5 and absf(local.y)<=displays[0].size.y*.5 and absf(local.z)<.0001,kind+" complete panel stays inside authored glass")
    var normal=pose.basis.z.normalized()
    var hit=SwgWristDatapad.new().point(pose,size,Vector2(860,620),pose.origin+normal*.4,-normal)
    check(hit.get("valid",false) and Vector2(hit.pixel).distance_to(Vector2(430,310))<.01,kind+" scaled panel retains controller ray mapping")
  var source_path="res://../"+str(scenery.screens[template][0].source_path)
  var data=JSON.parse_string(FileAccess.get_file_as_string(source_path))
  var mesh=SwgMeshBuilder.new().create_mesh(data.surfaces)
  var loader=preload("res://scripts/stage_loader.gd").new()
  for index in mesh.get_surface_count():mesh.surface_set_material(index,loader.make_material(data.surfaces[index],ProjectSettings.globalize_path(source_path).get_base_dir().get_base_dir()))
  var terminal:=MeshInstance3D.new();terminal.mesh=mesh;world.add_child(terminal)
  ui.open_terminal(record);ui.set_pending(false);ui.set_wallet({"cash":100,"bank":1000})
  if kind=="bazaar":ui.panel.configure(dict_bazaar(record),ui.wallet)
  await capture(kind)
  if kind=="bazaar":
   ui.close_interface()
   var sale=preload("res://scripts/vendor_commerce.gd").new();world.add_child(sale);sale.set_process(false);sale.root_ui=Node3D.new();sale.add_child(sale.root_ui);sale.mode="sale";sale.target=record;sale.item={"name":"Maroj Melon"};sale.build()
   sale.root_ui.transform=ui.terminal_pose(record,Vector3.ZERO,camera.global_position,Vector2(.59,.66))
   await capture("bazaar-sale");sale.free()
  ui.close_interface();terminal.free()
 world.queue_free();await process_frame
 print(JSON.stringify({"passed":failures.is_empty(),"checks":checks,"failures":failures,"original_terminal_meshes":true,"xr":false,"renderer":"dummy" if DisplayServer.get_name()=="headless" else RenderingServer.get_current_rendering_method()}));quit(0 if failures.is_empty() else 1)
func dict_bazaar(record:Dictionary)->Dictionary:
 var result=record.duplicate();result.listings=[{"id":"1","name":"CDEF Pistol","price":100,"buy_eligible":true},{"id":"2","name":"Survival Knife","price":100,"buy_eligible":true}];return result
func capture(label:String):
 for frame in 5:await process_frame
 if DisplayServer.get_name()!="headless":
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png("res://../runtime/evidence/terminal-shuttle-20261010/"+label+".png")
