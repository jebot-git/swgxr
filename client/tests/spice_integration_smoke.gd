extends SceneTree
class Harness extends "res://scripts/main.gd":
	var reply:Dictionary={}
	var profile_reads:=0
	func _ready()->void:pass
	func _process(_delta:float)->void:pass
	func _physics_process(_delta:float)->void:pass
	func api(_method:HTTPClient.Method,_path:String,_payload:Dictionary={})->Dictionary:
		profile_reads+=1;await get_tree().process_frame;return reply.duplicate(true)
class Body extends CharacterBody3D:
	var feedback=preload("res://combat/player_feedback.gd").new()
class Ambient extends Node3D:
	var records:Dictionary={}
	var manifest:Dictionary={"instances":[{"id":"neutral","position":[1,0,0]}]}
var checks:=0
var errors:Array=[]
func check(value:bool,label:String)->void:
	checks+=1
	if not value:errors.append(label);push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	var fixture:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/evidence/professions/fixture.json"))
	fixture.unarmed=JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/evidence/unarmed-live-snapshot.json")).unarmed
	var app:=Harness.new();root.add_child(app);app.world_ready=true;app.loading_stage=false;app.datapad_character_id=str(fixture.unarmed.character_id)
	app.player=Body.new();app.add_child(app.player)
	var head:=Camera3D.new();app.player.add_child(head)
	app.combat_rig=preload("res://combat/ranged_rig.gd").new();app.add_child(app.combat_rig)
	check(app.combat_rig.configure(head,app.player,[]) and app.combat_rig.configure_unarmed(fixture.unarmed),"Original rig initializes native unarmed profile")
	app.combat_rig.set_process(false);app.combat_rig.set_physics_process(false)
	app.inventory_snapshot={"equipment":[]};app.reply={"ok":true,"backend":"core3","weapons":[],"unarmed":fixture.unarmed.duplicate(true),"player_combat":fixture.player_combat}
	var world:=preload("res://spice/world_effects.gd").new();app.add_child(world);world.setup(app);world.set_process(false)
	app.reply.unarmed.power=123.0;app.reply.unarmed.stance_recovery=42.0
	app.player.feedback.spice.observe(preload("res://tests/spice_smoke.gd").envelope("droid_lube","active"))
	world._process(.1);await process_frame;await process_frame
	check(app.profile_reads==1 and app.combat_rig.unarmed.right.profile.power==123.0 and app.combat_rig.unarmed.right.profile.stance_recovery==42.0,"New native spice phase refreshes actual unarmed Power/recovery with no equipped weapon")
	world._process(.1);await process_frame
	check(app.profile_reads==1,"Same phase does not repeatedly request profiles")
	app.reply.unarmed.power=31.0;app.player.feedback.spice.observe(preload("res://tests/spice_smoke.gd").envelope("droid_lube","withdrawal"))
	world._process(.1);await process_frame;await process_frame
	check(app.profile_reads==2 and app.combat_rig.unarmed.right.profile.power==31.0,"Withdrawal replaces native unarmed stats without double multiplying")
	var source:=Ambient.new();app.add_child(source);app.radar_contacts.configure(source)
	app.player.feedback.spice.observe(preload("res://tests/spice_smoke.gd").envelope("pyrepenol","withdrawal"))
	check(app.get_radar_contacts(Vector3.ZERO,64)[0].relation=="hostile","Actual minimap provider shows neutral NPC as hostile only locally")
	check(app.radar_contacts.query(Vector3.ZERO,64)[0].relation=="neutral","Minimap illusion leaves underlying contact relation unchanged")
	app.player.feedback.spice.reset()
	check(app.get_radar_contacts(Vector3.ZERO,64)[0].relation=="neutral","Cleared native spice restores minimap relation")
	var snapshot_path:="res://../runtime/evidence/spice-giggledust-native-snapshot.json"
	if FileAccess.file_exists(snapshot_path):
		var native:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(snapshot_path))
		app.stage=Node3D.new();app.add_child(app.stage)
		app.services=preload("res://scripts/services_controller.gd").new();app.add_child(app.services);app.services.app=app;app.services.set_process(false)
		app.player.feedback.spice.observe(native.player.spice)
		var actors:Array=world.sync_outline_sources(native.world.spice_outlines,[])
		check(app.player.feedback.spice.policy().outlines and actors.size()==native.world.spice_outlines.size() and not actors.is_empty(),"Actual native cross-cell Giggledust rows build original client actor proxies")
		if not actors.is_empty():
			var actor:Node3D=actors[0]
			check(actor.record.cell_id==native.world.spice_outlines[0].cell_id and str(actor.record.cell_id)!="0" and actor.collision_layer==0 and actor.collision_mask==0 and actor.collider.disabled and not actor.is_in_group("swg_radar_contacts"),"Other-cell outline source preserves native cell, excludes collision and normal actor/target registry")
			world.refresh(actors,[],actor.global_position,app.player.feedback.spice.policy())
			check(world.outlines.size()==1 and not world.outlines.values()[0].parts.is_empty() and not actor.visible,"Native hidden source supplies original mesh outline only")
		world.sync_outline_sources([],[]);world.refresh([],[],Vector3.ZERO,app.player.feedback.spice.policy())
		check(world.outline_sources.is_empty() and world.outlines.is_empty(),"Native outline removal frees source and all rendered proxies")
	app.free();await process_frame
	print(JSON.stringify({"checks":checks,"errors":errors,"renderer":"dummy","native_profile":"recorded then mocked phase updates","headset_validated":false}));quit(0 if errors.is_empty() else 1)
