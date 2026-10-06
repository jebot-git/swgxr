extends RefCounted
## Replace only world presentation after Core3 selects a destination. The owned
## session and pending transport survive; native ACK follows supported placement.
const Catalog=preload("res://scripts/planet_catalog.gd")
var generation:=0
var busy:=false
var installed_zone:=""
func cancel()->void:generation+=1;busy=false;installed_zone=""
func prepare(app:Node,destination:Dictionary)->Dictionary:
	var zone:=str(destination.get("zone",""))
	var check:Dictionary=app.planet_catalog.readiness(zone)
	if not check.get("ok",false):return check
	if zone==app.active_planet and is_instance_valid(app.stage) and (installed_zone.is_empty() or installed_zone==zone):return {"ok":true,"changed":false}
	if busy:return {"ok":false,"error":"Another planet transition is still loading."}
	busy=true;generation+=1;installed_zone="loading"
	var epoch:=generation
	app.loading_stage=true;app.world_ready=false;app.player.active=false;app.player.set_physics_process(false)
	app.ensure_loading_screen();app.loading_screen.set_status("Loading "+str(check.descriptor.get("label",zone.capitalize()))+"…")
	app.datapad_epoch+=1
	app.native_poll_budget.reset()
	for key in ["inventory","datapad"]:
		var node:Variant=app.get(key)
		if is_instance_valid(node):node.set_allowed(false)
	var inventory:Variant=app.get("inventory")
	if is_instance_valid(inventory):inventory.cancel_interaction()
	var drops:Variant=app.get("inventory_drops")
	if is_instance_valid(drops):drops.clear()
	for key in ["mission_parcels","gameplay_combat","multiplayer_sync","services","gathering","crafting","medic","vehicles","pets","scout","corpse_gathering"]:
		var node:Variant=app.get(key)
		if is_instance_valid(node) and node.has_method("reset"):node.reset()
	var entertainer:Variant=app.get("entertainer")
	if is_instance_valid(entertainer):
		if is_instance_valid(entertainer.get("native")):entertainer.native.reset()
		entertainer.generation+=1;entertainer.actions.clear();entertainer.pending=false
		entertainer.active_performance={};entertainer.clear_presentation()
	var rig:Variant=app.get("combat_rig")
	if is_instance_valid(rig):rig.rounds_sim.clear()
	var live:Variant=app.get("live_combat")
	if is_instance_valid(live):
		live.generation+=1;live.busy=false;live.queue.clear();live.shots.clear()
		for actor:Node in live.actors.values():
			actor.collision_layer=0;actor.hide();actor.queue_free()
		live.actors.clear();live.ambient_bindings.clear()
	app.player.ground_provider=null
	app.radar_contacts.clear()
	for key in ["ambient_npcs","portal_visibility","world_stream","terrain","stage","environment_presentation"]:
		var node:Variant=app.get(key)
		if is_instance_valid(node):
			if node.has_method("set_active"):node.set_active(false)
			app.retire_world_node(node)
		app.set(key,null)
	await app.get_tree().process_frame
	await app.get_tree().physics_frame
	if generation!=epoch or not is_instance_valid(app):busy=false;return {"ok":false,"cancelled":true}
	app.loader=preload("res://scripts/stage_loader.gd").new()
	app.active_planet=zone;app.planet_assets=check.descriptor
	var installed:Dictionary=await app.install_planet_world(destination)
	if generation!=epoch:busy=false;return {"ok":false,"cancelled":true}
	busy=false
	if not installed.get("ok",false):return installed
	installed_zone=zone
	for key in ["live_combat","gameplay_combat"]:
		var bridge:Variant=app.get(key)
		if is_instance_valid(bridge):
			bridge.stage=app.stage;bridge.actor_catalog=str(app.planet_assets.get("entities",""))
			bridge.ambient_source=app.ambient_npcs
			bridge.ambient_bindings.clear()
	if is_instance_valid(app.get("datapad")):app.datapad.ui.set_planet(zone)
	if is_instance_valid(app.get("services")):app.services.reset()
	if is_instance_valid(app.get("multiplayer_sync")):
		app.multiplayer_sync.entities.setup(app)
		app.multiplayer_sync.players.configure_world(app)
	return {"ok":true,"changed":true}

func install(app:Node,destination:Dictionary)->Dictionary:
	var descriptor:Dictionary=app.planet_assets
	var source:Vector3=app.loader.vec(destination.position)
	var origin:Vector3=app.loader.vec(descriptor.get("origin",[0,0,0]))
	var relative:=source-origin
	var target:=Vector3(relative.x,relative.y,-relative.z)
	var stage_path:=str(descriptor.get("stage",""))
	app.stage=app.loader.load_stage(stage_path) if not stage_path.is_empty() else app.loader.empty_stream_stage(descriptor,target)
	if app.stage==null:return {"ok":false,"error":str(app.loader.report.get("error","Original destination stage is unavailable."))}
	app.stage.set_meta("planet",app.active_planet);app.add_child(app.stage);app.player.ground_provider=app.stage
	app.world_stream=preload("res://scripts/world_stream.gd").new();app.add_child(app.world_stream)
	if not app.world_stream.configure(str(descriptor.world),app.stage):return {"ok":false,"error":str(app.world_stream.report.get("error","Destination world failed."))}
	app.terrain=preload("res://scripts/terrain_stream.gd").new();app.add_child(app.terrain)
	if not app.terrain.configure(str(descriptor.terrain),origin):return {"ok":false,"error":"Destination terrain failed: "+app.active_planet}
	app.terrain.set_cell_source(app.stage);app.player.void_floor_y=-4096.0
	app.world_stream.update_observer(target);app.terrain.update_observer(target)
	app.stage.set_observer(app.player)
	app.portal_visibility=preload("res://scripts/portal_visibility.gd").new();app.add_child(app.portal_visibility)
	app.portal_visibility.culling_enabled=not app.args.has("no-portal-culling")
	app.portal_visibility.configure(app.stage,app.player.get_camera(),app.xr_spectator.camera if is_instance_valid(app.xr_spectator) and app.xr_spectator.enabled else null)
	app.make_environment()
	if not app.environment_presentation.report.get("ready",false):return {"ok":false,"error":str(app.environment_presentation.report.get("error","Destination environment failed."))}
	app.environment_presentation.bind_world(app.terrain,app.stage);app.environment_presentation.update_observer(target);app.environment_presentation.set_active(true)
	var placements:=str(descriptor.get("ambient_placements",""))
	if not placements.is_empty():
		app.ambient_npcs=preload("res://scripts/ambient_npcs.gd").new();app.add_child(app.ambient_npcs)
		app.ambient_npcs.set_visibility_provider(app.portal_visibility)
		if not app.ambient_npcs.configure(placements,app.stage,app.terrain):return {"ok":false,"error":str(app.ambient_npcs.report.get("error","Destination inhabitants failed."))}
		app.radar_contacts.configure(app.ambient_npcs);app.ambient_npcs.update_observer(target)
	return {"ok":true}
