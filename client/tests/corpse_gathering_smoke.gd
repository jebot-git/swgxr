extends SceneTree
const CorpseUI=preload("res://scripts/corpse_gathering.gd")
const Assets=preload("res://scripts/inventory_assets.gd")
var checks:=0
var errors:Array[String]=[]
var inspections:Array=[]
var harvests:Array=[]
var loots:Array=[]
var record:Dictionary={"id":"corpse-native","dead":true,"name":"Original corpse record","position":Vector3(0,0,0),"bounds":AABB(Vector3(-0.4,0,-0.5),Vector3(0.8,0.35,1))}
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:errors.append(message);push_error(message)
func _initialize()->void:call_deferred("run")
func run()->void:
	var world:=Node3D.new();root.add_child(world)
	var rig:=XROrigin3D.new();world.add_child(rig)
	var head:=XRCamera3D.new();head.name="XRCamera3D";rig.add_child(head);head.position=Vector3(0,1.7,1)
	var hand:=XRController3D.new();hand.name="RightHand";rig.add_child(hand)
	var body:=CharacterBody3D.new();rig.add_child(body)
	var assets:=Assets.new();assets.configure()
	var popup:=CorpseUI.new();world.add_child(popup);popup.configure(rig,body,assets);popup.set_process(false);popup.set_allowed(true)
	popup.corpse_provider=func(_position):return record
	popup.corpse_inspect_requested.connect(func(value):inspections.append(value))
	popup.corpse_harvest_requested.connect(func(value,kind):harvests.append({"corpse":value,"kind":kind}))
	popup.corpse_loot_requested.connect(func(value):loots.append(value))
	var pose:=Transform3D(Basis.IDENTITY,Vector3(0,0.5,0))
	check(popup.above_body(record,pose.origin) and not popup.above_body(record,Vector3(0,0.1,0)),"Hover requires hand above actual corpse bounds")
	var alive:=record.duplicate();alive.dead=false;check(not popup.above_body(alive,pose.origin),"Living/training entities cannot become corpse interactions")
	popup.sample(true,true,pose,head.global_transform,0.9,0)
	check(inspections.is_empty(),"Held trigger at initial hover does not inspect")
	popup.sample(true,true,pose,head.global_transform,0,0);popup.sample(true,true,pose,head.global_transform,0.9,0)
	check(inspections.size()==1 and popup.visible and popup.pending,"Fresh empty-hand trigger inspects native corpse")
	popup.sample(true,true,pose,head.global_transform,0.9,0);check(inspections.size()==1 and loots.is_empty(),"Pending inspect blocks repeat and loot")
	var template:="object/resource_container/organic_food.iff"
	var context:Dictionary={"resources":[{"kind":"meat","name":"Gaho","container_template":template,"quantity":12,"available":true},{"kind":"hide","name":"Hide","container_template":"missing-original-icon","quantity":0,"available":false,"block_reason":"Harvest skill required"}],"loot_available":true,"loot":{"credits":25,"item_count":2}}
	popup.sample(true,true,pose,head.global_transform,0,0);popup.sample(true,true,pose,head.global_transform,0.9,0.9)
	popup.set_corpse_context(record,context)
	popup.sample(true,true,pose,head.global_transform,0.9,0.9)
	check(loots.is_empty() and harvests.is_empty(),"Buttons pressed during inspect cannot auto-fire when the reply arrives")
	check(popup.choices.size()==2 and "25 credits / 2 items" in popup.title.text,"Authoritative resource options and loot summary presented")
	var meat_label:Label3D=popup.choice_nodes[0].get_child(1) as Label3D
	var hide_label:Label3D=popup.choice_nodes[1].get_child(0) as Label3D
	check(meat_label.text=="Meat\nGaho ×12","Resource choice identifies kind before generated name and quantity")
	check(hide_label.text.begins_with("Hide ×0\nOriginal icon unavailable"),"Kind-only resource names are not duplicated")
	var icon:MeshInstance3D=popup.choice_nodes[0].get_child(0) as MeshInstance3D
	check(icon!=null and icon.get_active_material(0) is ShaderMaterial and icon.get_active_material(0).shader.resource_path.ends_with("equipment_hologram.gdshader"),"Original resource container uses independent cyan hologram material")
	var selected:=Transform3D(Basis.IDENTITY,popup.choice_nodes[0].global_position)
	popup.sample(true,true,selected,head.global_transform,0,0);popup.sample(true,true,selected,head.global_transform,0,0.9)
	check(harvests.size()==1 and harvests[0].kind=="meat" and popup.pending,"Fresh grip on resource requests one native harvest")
	popup.sample(true,true,selected,head.global_transform,0,0.9);check(harvests.size()==1,"Held grip does not duplicate harvest requests")
	popup.sample(true,true,selected,head.global_transform,0,0);popup.sample(true,true,selected,head.global_transform,0.9,0.9)
	popup.set_busy(false,"Server rejected capacity")
	popup.sample(true,true,selected,head.global_transform,0.9,0.9)
	check(harvests.size()==1 and loots.is_empty(),"Buttons pressed during harvest cannot auto-repeat after rejection")
	check(popup.visible and popup.message.text=="Server rejected capacity","Rejected harvest remains visible without local yield")
	selected.origin=popup.choice_nodes[1].global_position
	popup.sample(true,true,selected,head.global_transform,0,0);popup.sample(true,true,selected,head.global_transform,0,0.9)
	check(harvests.size()==1 and popup.message.text=="Harvest skill required","Unavailable resource choice displays native reason")
	popup.sample(true,true,pose,head.global_transform,0,0);popup.sample(true,true,pose,head.global_transform,0.9,0)
	check(loots.size()==1 and popup.pending,"Next fresh trigger over same corpse requests loot-all")
	popup.set_busy(false);popup.sample(true,false,pose,head.global_transform,0,0)
	check(not popup.visible and not popup.interaction_active,"Occupied hand cancels corpse interface")
	popup.sample(true,true,pose,head.global_transform,0,0);popup.sample(true,true,pose,head.global_transform,0.9,0);popup.set_corpse_context(record,context)
	popup.sample(false,true,pose,head.global_transform,0.9,0.9)
	check(not popup.visible and harvests.size()==1 and loots.size()==1,"Tracking loss closes without harvesting/looting")
	popup.set_busy(false,"insufficient_inventory_capacity")
	check(popup.message.text=="Make room in your inventory before collecting this.","Native capacity code is presented as a readable instruction")
	popup.set_busy(false,"personal_loot_owner_required_group_loot_unsupported")
	check("personal loot owner" in popup.message.text and "Group loot" in popup.message.text,"Ownership message preserves group-loot limitation")
	popup.set_busy(false,"Descriptive server rejection remains intact.")
	check(popup.message.text=="Descriptive server rejection remains intact.","Unknown descriptive server errors remain unchanged")
	if "--capture" in OS.get_cmdline_user_args():
		check(RenderingServer.get_current_rendering_method()=="forward_plus","Corpse preview uses desktop Vulkan Forward+")
		var corpses:Node3D=load("res://scripts/corpse_visuals.gd").new();world.add_child(corpses);corpses.configure();corpses.set_context(world,body);corpses.set_physics_process(false)
		corpses.set_states([{"id":"source-pose-fixture","template":"object/mobile/worrt_hue.iff","name":"Worrt","dead":true,"world_position":Vector3.ZERO,"heading_radians":0.6}]);corpses.sync_visuals()
		var visual:Dictionary=corpses.visuals["source-pose-fixture"]
		var bounds:AABB=visual.node.global_transform*visual.bounds
		var hover:=Transform3D(Basis.IDENTITY,Vector3(bounds.get_center().x,bounds.end.y+0.1,bounds.get_center().z))
		record=corpses.nearest(hover.origin)
		var camera:=Camera3D.new();world.add_child(camera);camera.position=Vector3(0,1.1,1.15);camera.look_at(Vector3(0,0.45,0));camera.fov=58;camera.make_current()
		popup.sample(true,true,hover,camera.global_transform,0,0);popup.sample(true,true,hover,camera.global_transform,0.9,0)
		var actual_icons:Array=[]
		for kind in ["meat","hide","bone"]:
			var source_template:String={"meat":"object/resource_container/organic_food.iff","hide":"object/resource_container/organic_hide.iff","bone":"object/resource_container/organic_structure.iff"}[kind]
			actual_icons.append({"kind":kind,"name":kind.capitalize(),"container_template":source_template,"quantity":12,"available":true})
		popup.set_corpse_context(record,{"resources":actual_icons,"loot_available":true,"loot":{"credits":25,"item_count":2}})
		var environment:=WorldEnvironment.new();world.add_child(environment);environment.environment=Environment.new();environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color("06121b");environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color.WHITE;environment.environment.ambient_light_energy=1
		var caption:=Label.new();root.add_child(caption);caption.position=Vector2(20,20);caption.text="Desktop corpse interaction · synthetic reward fixture / original worrt incapacitated pose and resource models"
		root.size=Vector2i(1440,1000)
		for i in range(5):await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../runtime/evidence/corpse-gathering-preview.png"))
		caption.queue_free()
	var output:Dictionary={"checks":checks,"passed":errors.is_empty(),"errors":errors,"gpu_tested":"--capture" in OS.get_cmdline_user_args(),"headset_tested":false}
	print(JSON.stringify(output));FileAccess.open("res://../runtime/evidence/corpse-gathering-"+("render" if output.gpu_tested else "smoke")+".json",FileAccess.WRITE).store_string(JSON.stringify(output,"  "))
	call_deferred("finish",world,0 if errors.is_empty() else 1)
func finish(world:Node,code:int)->void:world.free();quit(code)
