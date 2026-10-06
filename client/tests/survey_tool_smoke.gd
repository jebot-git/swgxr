extends SceneTree
const Inventory=preload("res://scripts/xr_inventory.gd")
const Avatar=preload("res://scripts/avatar.gd")
class Player extends CharacterBody3D:
	var move_captured:=false
	var turn_captured:=false
	func set_interface_capture(move:bool,turn:bool)->void: move_captured=move; turn_captured=turn
var checks:=0
var errors:Array[String]=[]
var surveys:Array=[]
var deploys:Array=[]
var pickups:Array=[]
var returns:Array=[]
var holsters:Array=[]
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok: errors.append(message); push_error(message)
func _initialize()->void: call_deferred("run")
func run()->void:
	var world:=Node3D.new(); root.add_child(world)
	var rig:=XROrigin3D.new(); world.add_child(rig)
	var head:=XRCamera3D.new(); head.name="XRCamera3D"; rig.add_child(head); head.position=Vector3(0,1.7,0)
	for side in ["LeftHand","RightHand"]:
		var hand:=XRController3D.new(); hand.name=side; rig.add_child(hand)
	var player:=Player.new(); rig.add_child(player)
	var bag:=Inventory.new(); world.add_child(bag); bag.configure(rig,player); bag.set_process(false); bag.set_allowed(true)
	bag.survey_requested.connect(func(tool,id):surveys.append({"tool":tool,"id":id}))
	bag.deploy_requested.connect(func(tool,pose):deploys.append({"tool":tool,"pose":pose}))
	bag.tool_pickup_requested.connect(func(candidate):pickups.append(candidate))
	bag.return_tool_requested.connect(func(tool):returns.append(tool))
	bag.tool_holster_requested.connect(func(tool):holsters.append(tool))
	var tool:Dictionary={"id":"tool1","name":"Survey tool","template":"object/tangible/survey_tool/survey_tool_mineral.iff","tool_kind":"survey","container_id":"inventory"}
	bag.set_snapshot({"inventory":{"id":"inventory","capacity":80,"occupied":1},"items":[tool]}); bag.set_open(true); bag.take_item(tool)
	check(bag.surfaces[0].mesh.visible and not bag.surfaces[bag.survey_surface].mesh.visible,"Open inventory remains readable while holding survey tool")
	bag.set_open(false)
	check(bag.survey_ui.active and bag.surfaces[bag.survey_surface].mesh.visible and not bag.surfaces[0].mesh.visible,"Closing bag exposes held survey minimap")
	check(bag.blocks_combat(),"Held survey tool reserves holding trigger from combat")
	var context:Dictionary={"planet":"tatooine","max_range_m":128,"range_m":128,"surveying_skill":35,"center":[3528,5,4800],"resources":[]}
	for i in range(35):context.resources.append({"id":"resource%d"%i,"name":"Server resource %d"%i,"type":"Mineral","container_template":"object/resource_container/inorganic_minerals.iff","attributes":[{"name":"res_quality","label":"Overall Quality","value":352},{"name":"res_conductivity","label":"Conductivity","value":670}]})
	bag.set_tool_context("tool1",context)
	bag.set_survey_transform(Transform3D.IDENTITY)
	check(bag.surfaces[bag.resource_surface].mesh.visible and bag.surfaces[bag.resource_surface].mesh.position.x< -0.4 and bag.surfaces[bag.resource_surface].mesh.rotation.y>0.4,"Held survey opens spaced left-side resource pane tilted toward viewer")
	check(bag.resource_preview_viewport.get_node("Models").get_child_count()==1 and not bag.resource_panel.unavailable.visible,"Selected resource renders its original container template")
	check(bag.resource_panel.statistics.text.contains("Overall Quality: 352") and bag.resource_panel.statistics.text.contains("Conductivity: 670"),"Resource statistics preserve authoritative values and source labels")
	context.resources[1].container_template="object/resource_container/unavailable_original.iff"
	bag.set_tool_context("tool1",context);bag.survey_ui.select_index(1)
	check(bag.resource_panel.unavailable.visible and bag.resource_preview_viewport.get_node("Models").get_child_count()==0,"Unavailable original resource model is explicitly reported without keeping stale preview")
	bag.survey_ui.select_index(0)
	check(bag.survey_ui.map.service_points.is_empty() and bag.survey_ui.map.landmarks.is_empty() and bag.survey_ui.map.waypoints.is_empty(),"Survey map excludes inherited terminals, POIs and saved waypoint overlays")
	check(bag.survey_ui.selected_ids.size()==35 and bag.survey_ui.map.texture!=null,"Current planet source map and server resource list load")
	check(is_equal_approx(bag.survey_ui.map.pixels_per_meter(),515.0/128.0),"Minimap spans authoritative maximum full-width skill/tool range")
	await process_frame
	var target_pixel:Vector2=bag.survey_ui.resources.position+bag.survey_ui.resources.get_item_rect(5).get_center()
	var click:Dictionary={"surface":bag.survey_surface,"pixel":target_pixel,"world":Vector3.ZERO}
	bag.update_pointer(click,0);bag.update_pointer(click,0.9);bag.update_pointer(click,0)
	check(bag.resource_panel.resource.get("id","")=="resource5","Finger selection updates resource side pane atomically")
	check(bag.survey_ui.selected_resource_id=="resource5","Other-hand pointed trigger selects a real SubViewport resource row")
	bag.update_held_trigger(0,head.global_transform); bag.update_held_trigger(0.9,head.global_transform)
	check(surveys.size()==1 and surveys[0].id=="resource5" and bag.action_pending,"Holding-hand fresh trigger surveys selected resource once")
	bag.update_held_trigger(0.9,head.global_transform);check(surveys.size()==1,"Held trigger never repeats survey")
	bag.set_snapshot(bag.snapshot);bag.set_tool_context("tool1",context)
	check(bag.action_pending and bag.survey_ui.pending and bag.mutation_pending,"Unrelated inventory/context refresh cannot unlock pending survey mutation")
	bag.set_survey_result("stale-tool",{"spots":[]})
	check(bag.action_pending,"Response for another held tool cannot unlock current survey")
	var result:Dictionary={"spots":[{"position":[3528,5,4800],"density":0.31},{"position":[3560,5,4820],"density":0.81}],"highest":{"position":[3560,5,4820],"density":0.81},"waypoint":{"id":"real-waypoint"}}
	bag.set_survey_result("tool1",result)
	check(bag.survey_ui.map.spots.size()==2 and bag.survey_ui.map.highest.density==0.81 and "waypoint" in bag.survey_ui.status.text,"Returned densities/highest waypoint display without local synthesis")
	var hit:Dictionary={"surface":bag.survey_surface,"pixel":Vector2(100,100)}
	var selected_before:int=bag.survey_ui.selected_ids.find(bag.survey_ui.selected_resource_id)
	bag.update_stick_capture(Vector2(0,-1),hit,0.5)
	check(bag.stick_captured and player.turn_captured and bag.survey_ui.selected_resource_id==bag.survey_ui.selected_ids[selected_before+1],"Pointed stick advances highlighted resource and captures its locomotion channel")
	check(surveys.size()==1,"Stick selection does not start a survey")
	for i in range(20):bag.update_stick_capture(Vector2(0,-1),hit,.2)
	await process_frame
	check(bag.survey_ui.resources.get_v_scroll_bar().value>0,"Highlighted resource remains visible as selection crosses viewport")
	bag.update_stick_capture(Vector2.ZERO,{},0.01)
	check(not bag.stick_captured,"Neutral main stick releases survey capture")
	bag.set_open(false);bag.main_grip_armed=false
	var drop_pose:=Transform3D(Basis.IDENTITY,Vector3(0,0.08,-0.4))
	bag.update_gestures(true,head.global_transform,Transform3D.IDENTITY,0,0,{},drop_pose)
	check(deploys.size()==1 and deploys[0].pose==drop_pose and not bag.held_item.is_empty(),"Survey ground-release requests deployment and waits for authority")
	bag.set_snapshot(bag.snapshot);bag.set_tool_context("tool1",context)
	check(bag.action_pending and bag.survey_ui.pending,"Read-only refresh cannot unlock deployment awaiting confirmation")
	bag.finish_item_action(true)
	check(not bag.survey_ui.active and bag.surfaces[bag.survey_surface].viewport.render_target_update_mode==SubViewport.UPDATE_DISABLED,"Clearing tool disables minimap viewport")
	check(not bag.surfaces[bag.resource_surface].mesh.visible and bag.resource_preview_viewport.render_target_update_mode==SubViewport.UPDATE_DISABLED,"Stowing tool disables resource side pane and preview rendering")
	bag.set_hip_tool(tool)
	check(is_instance_valid(bag.hip_model) and bag.hip_model.visible,"Canonical hip escrow presents one original tool model")
	bag.update_gestures(true,head.global_transform,Transform3D.IDENTITY,0,0,{},bag.hip_transform())
	bag.update_gestures(true,head.global_transform,Transform3D.IDENTITY,0,0.9,{},bag.hip_transform())
	check(pickups.size()==1 and pickups[0].gathering_hip and bag.held_item.is_empty(),"Cross-body hip grab requests recovery without prematurely taking/removing tool")
	bag.set_busy(false);bag.take_item(tool)
	check(bag.held_item.gathering_hip and not bag.hip_model.visible,"Confirmed hip draw reserves escrow and hides duplicate hip visual")
	bag.set_open(true);bag.main_grip_armed=false
	bag.update_gestures(true,head.global_transform,Transform3D.IDENTITY,0.9,0,{},Transform3D.IDENTITY)
	check(returns.size()==1 and not bag.held_item.is_empty() and bag.action_pending,"Returning escrow tool into open bag waits for capacity-checked server request")
	bag.finish_item_action(false);check(not bag.held_item.is_empty(),"Rejected return retains hip-held tool")
	var source:=Avatar.new();world.add_child(source);source.configure("human_male");source.visible=false
	bag.set_equipment_context(source,[]);bag.show_equipment_hologram(head.global_transform)
	check(bag.hologram.markers.has("prototype_tool_hip"),"Every tool has explicit prototype offhand-hip hologram point")
	var marker:Node3D=bag.hologram.markers.prototype_tool_hip;bag.main_grip_armed=false
	bag.update_gestures(true,head.global_transform,Transform3D.IDENTITY,0.9,0,{},Transform3D(Basis.IDENTITY,marker.global_position))
	check(holsters.size()==1,"Release over tool hip requests holster rather than fabricated equipment arrangement")
	bag.cancel_interaction();check(not bag.survey_ui.active and bag.held_item.is_empty() and not bag.mutation_pending,"Tracking/menu cancellation closes survey UI safely")
	bag.set_hip_tool({});bag.world_pickup_provider=func(_pose):return {"gathering_deployment":{"id":"deployment1","tool_id":"tool1"}}
	bag.update_gestures(true,head.global_transform,Transform3D.IDENTITY,0,0,{},drop_pose)
	bag.update_gestures(true,head.global_transform,Transform3D.IDENTITY,0,0.9,{},drop_pose)
	check(pickups.size()==2 and pickups[1].has("gathering_deployment") and bag.held_item.is_empty() and bag.mutation_pending,"Deployed tool pickup waits for capacity-checked confirmation without optimistic ownership")
	bag.set_snapshot(bag.snapshot);check(bag.action_pending,"Inventory refresh preserves deployed pickup lock")
	bag.set_busy(false,"Capacity unavailable");check(not bag.action_pending and bag.held_item.is_empty(),"Rejected pickup leaves no held duplicate")
	bag.take_item(tool);bag.set_tool_context("tool1",context);bag.set_survey_result("tool1",result);bag.clear_held()
	var next_tool:Dictionary=tool.duplicate(true);next_tool.id="tool2";bag.take_item(next_tool)
	check(bag.survey_ui.selected_ids.is_empty() and bag.survey_ui.map.spots.is_empty(),"New held tool clears prior resource list and density samples before async context")
	bag.set_tool_context("tool1",context);check(bag.survey_ui.selected_ids.is_empty(),"Late old-tool context cannot populate newly held survey tool")
	bag.cancel_interaction()
	if "--capture" in OS.get_cmdline_user_args():
		check(RenderingServer.get_current_rendering_method()=="forward_plus","Survey preview uses desktop Vulkan Forward+")
		bag.set_hip_tool({});bag.take_item(tool);bag.set_tool_context("tool1",context);bag.set_survey_result("tool1",result)
		bag.set_survey_transform(Transform3D.IDENTITY);bag.held_model.visible=false
		var camera:=Camera3D.new();world.add_child(camera);camera.position=Vector3(-0.14,0,0.82);camera.fov=42;camera.make_current()
		var overlay:=CanvasLayer.new();world.add_child(overlay);var caption:=Label.new();overlay.add_child(caption);caption.position=Vector2(20,20);caption.text="Desktop survey UI · synthetic server-response fixture / original Tatooine map"
		root.size=Vector2i(1440,1000)
		for i in range(5):await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../runtime/evidence/survey-tool-preview.png"))
	var output:Dictionary={"checks":checks,"passed":errors.is_empty(),"errors":errors,"gpu_tested":"--capture" in OS.get_cmdline_user_args(),"headset_tested":false}
	print(JSON.stringify(output));FileAccess.open("res://../runtime/evidence/survey-tool-"+("render" if output.gpu_tested else "smoke")+".json",FileAccess.WRITE).store_string(JSON.stringify(output,"  "))
	call_deferred("finish",world,0 if errors.is_empty() else 1)
func finish(world:Node,code:int)->void:
	world.free()
	await process_frame
	quit(code)
