extends SceneTree
const Radar = preload("res://scripts/wrist_radar.gd")
const Datapad = preload("res://scripts/xr_datapad.gd")
class Player extends CharacterBody3D:
	var move_captured := false
	var turn_captured := false
	func set_interface_capture(move: bool, turn: bool) -> void: move_captured=move; turn_captured=turn
var checks := 0
var errors: Array[String] = []
var provider_calls := 0
var queried_center := Vector3.ZERO
var queried_radius := 0.0
func contacts(center: Vector3, radius: float) -> Array:
	provider_calls+=1; queried_center=center; queried_radius=radius
	return [{"id":"ahead","position":center+Vector3(0,0,-32),"kind":"npc","relation":"neutral"},
		{"id":"right","position":center+Vector3(32,0,0),"kind":"mob","relation":"hostile"},
		{"id":"friendly","position":center+Vector3(-16,5,-18),"kind":"npc","relation":"friendly"},
		{"id":"attackable","position":center+Vector3(10,-5,15),"kind":"mob","relation":"attackable"}]
func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok: errors.append(message); push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var world:=Node3D.new(); root.add_child(world)
	var radar:=Radar.new(); world.add_child(radar); radar.configure()
	var provider:=Callable(self,"contacts")
	for i in range(30): radar.tick(1.0/60,Vector3.ZERO,Vector3.FORWARD,provider)
	check(provider_calls==0 and radar.refresh_count==0 and radar.viewport.render_target_update_mode==SubViewport.UPDATE_DISABLED,"Hidden radar does no queries, redraws or viewport passes")
	radar.set_active(true)
	var center:=Vector3(10,5,-40)
	for i in range(60): radar.tick(1.0/60,center,Vector3.FORWARD,provider)
	check(provider_calls==5 and radar.refresh_count==5,"Active radar refreshes exactly5times per second without catch-up")
	check(queried_center==center and queried_radius==64,"Provider gets player world center and original64m range")
	var ahead: Dictionary=radar.last_contacts.filter(func(c): return c.id=="ahead")[0]
	var right: Dictionary=radar.last_contacts.filter(func(c): return c.id=="right")[0]
	check(ahead.pixel.is_equal_approx(Vector2(128,76)) and right.pixel.is_equal_approx(Vector2(180,128)),"Heading-up projection places forward above and right to the right")
	check(ahead.color==Color.WHITE and right.color==Color.RED,"Neutral townNPCwhite and hostile red preserve source palette")
	check(radar.last_contacts.filter(func(c): return c.id=="attackable")[0].color==Color("ffdd00"),"Attackable neutral uses sourceyellow")
	check(radar.last_contacts.filter(func(c): return c.id=="friendly")[0].height_sign==1,"Prototype elevation chevron records above-floor contacts")
	radar.refresh(center,Vector3.RIGHT,contacts(center,64))
	right=radar.last_contacts.filter(func(c): return c.id=="right")[0]
	check(right.pixel.is_equal_approx(Vector2(128,76)) and is_equal_approx(radar.canvas.heading_degrees,90),"Camera yaw rotates contacts independently of wrist orientation")
	var overload: Array=[]
	for i in range(300): overload.append({"id":str(i),"position":center+Vector3(i*0.2,50,0)})
	overload.append({"id":"outside","position":center+Vector3(65,0,0)})
	overload.append({"id":"invalid","position":Vector3(INF,0,0)})
	radar.refresh(center,Vector3.UP,overload)
	check(radar.last_contacts.size()==128 and radar.last_contacts.all(func(c): return c.id.to_int()<128),"Over-capacity provider output retains nearest128 horizontal contacts")
	check(radar.last_forward==Vector3.RIGHT,"Looking straight up preserves stable horizontal heading")
	radar.set_active(false)
	var prior:=radar.refresh_count
	radar.tick(10,center,Vector3.FORWARD,provider)
	check(radar.refresh_count==prior and radar.viewport.render_target_update_mode==SubViewport.UPDATE_DISABLED,"Hiding immediately disables refresh even after a long stall")
	# Datapad integration tests passive tracking independently of pointer tracking.
	var rig:=XROrigin3D.new(); world.add_child(rig)
	var head:=XRCamera3D.new(); head.name="XRCamera3D"; rig.add_child(head); head.position=Vector3(0,1.7,0)
	for side in ["LeftHand","RightHand"]:
		var controller:=XRController3D.new(); controller.name=side; rig.add_child(controller)
		controller.position=Vector3(-0.25 if side=="LeftHand" else 0.25,1.3,-0.3)
	var player:=Player.new(); rig.add_child(player)
	var pad:=Datapad.new(); world.add_child(pad); pad.configure(rig,player); pad.set_process(false); pad.radar_contacts_provider=provider
	var transforms: Array=[rig.transform,head.transform,player.transform,rig.get_node("LeftHand").transform,rig.get_node("RightHand").transform]
	pad.set_allowed(true); pad.update_tracking_state(true,true,false,0,0,0.016)
	check(not pad.visible and not pad.radar.active and not pad.is_open,"Minimap stays hidden without fist gesture")
	check(pad.surfaces.all(func(s): return not s.mesh.visible and s.viewport.render_target_update_mode==SubViewport.UPDATE_DISABLED),"Closed datapad panels remain hidden and do not render")
	check(not player.move_captured and not player.turn_captured,"Passive radar never captures sticks")
	pad.update_tracking_state(true,true,false,0.8,0.8,0.26)
	check(pad.radar.active and not pad.is_open,"Fist opens minimap without pointing-hand tracking")
	pad.touch_minimap({"tip":pad.radar.display.global_position,"direction":Vector3.FORWARD})
	check(pad.is_open and not pad.radar.active and pad.radar.viewport.render_target_update_mode==SubViewport.UPDATE_DISABLED,"Opening datapad replaces radar without a second UI pass")
	pad.update_tracking_state(true,true,true,0,0,0.016)
	check(pad.is_open and not pad.radar.active,"Releasing fist keeps full datapad open and minimap hidden")
	pad.update_tracking_state(false,true,true,0,0,0.016)
	check(not pad.visible and not pad.radar.active,"Head tracking loss hides radar")
	pad.update_tracking_state(true,false,true,0,0,0.016)
	check(not pad.radar.active,"Offhand tracking loss hides radar")
	pad.update_tracking_state(true,true,false,0,0,0.016); pad.set_allowed(false)
	check(not pad.visible and not pad.radar.active,"Menu/world/focus gate hides radar immediately")
	var after: Array=[rig.transform,head.transform,player.transform,rig.get_node("LeftHand").transform,rig.get_node("RightHand").transform]
	check(transforms==after,"UI leaves head/controllers/physics body transforms unchanged")
	check(radar.display.mesh.size==Vector2(0.14,0.14) and radar.viewport.size==Vector2i(256,256),"Compact14cm radar has bounded256px viewport")
	check(radar.display.material_override.shading_mode==BaseMaterial3D.SHADING_MODE_UNSHADED and radar.display.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,"Hologram adds no lighting or shadows")
	if "--capture" in OS.get_cmdline_user_args():
		check(RenderingServer.get_current_rendering_method()=="forward_plus" and DisplayServer.get_name()!="headless","Preview uses actual Forward+ GPU renderer")
		pad.visible=false; radar.set_active(true); radar.refresh(center,Vector3.FORWARD,contacts(center,64))
		var camera:=Camera3D.new(); world.add_child(camera); camera.position=Vector3(0,0.084,0.22); camera.fov=50; camera.make_current()
		var environment:=WorldEnvironment.new(); var settings:=Environment.new(); settings.background_mode=Environment.BG_COLOR; settings.background_color=Color("071119"); environment.environment=settings; world.add_child(environment)
		var overlay:=CanvasLayer.new(); world.add_child(overlay); var label:=Label.new(); overlay.add_child(label); label.position=Vector2(24,22); label.text="WRIST RADAR · 64 m\nSynthetic contact palette / desktop preview"; label.add_theme_font_size_override("font_size",22)
		root.size=Vector2i(1100,800)
		for i in range(5): await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../runtime/evidence/wrist-radar-preview.png"))
	var result: Dictionary={"test":"wrist_radar","checks":checks,"passed":errors.is_empty(),"errors":errors,"radar":radar.statistics(),"gpu_tested":"--capture" in OS.get_cmdline_user_args(),"headset_tested":false}
	var report_name := "wrist-radar-render.json" if result.gpu_tested else "wrist-radar-smoke.json"
	FileAccess.open("res://../runtime/evidence/"+report_name,FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	print(JSON.stringify(result))
	# Let the capture coroutine release its locals before destroying its scene.
	call_deferred("finish",world,0 if errors.is_empty() else 1)

func finish(world: Node3D, code: int) -> void:
	world.free()
	quit(code)
