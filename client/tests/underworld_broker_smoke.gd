extends SceneTree
## Exact original deliver_npc variants through the ordinary live actor renderer.
var checks:=0
var errors:Array=[]
func check(value:bool,label:String)->void:
	checks+=1
	if not value:errors.append(label);push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	var source:=FileAccess.get_file_as_string("res://../vendor/Core3/MMOCoreORB/bin/scripts/mobile/mission/deliver_npc.lua")
	var pattern:=RegEx.new();pattern.compile('"(object/mobile/[^\"]+\\.iff)"')
	var variants:=pattern.search_all(source)
	check(not variants.is_empty(),"Pinned deliver_npc source supplies original broker variants")
	var assets:=preload("res://scripts/inventory_assets.gd").new();assets.configure()
	var dead_assets:=preload("res://scripts/inventory_assets.gd").new();dead_assets.configure(ProjectSettings.globalize_path("res://../runtime/assets/corpses/catalog.json"))
	for variant in variants:
		var template:String=variant.get_string(1)
		var actor:=preload("res://combat/live_actor.gd").new();root.add_child(actor)
		var record:Dictionary={"id":"broker-fixture","kind":"creature","template":template,"name":"Barak","position":[3500,5,-4800],"heading_radians":0.0,"scale":1.0,"health":8400,"max_health":8400,"ham":[8400,8400,8400],"max_ham":[8400,8400,8400],"dead":false,"passive":true,"posture":0,"equipment":[]}
		check(actor.configure(record,"mocked-native-session",assets,dead_assets,"res://../runtime/assets/combat_population/native_current/catalog.json"),"Exact native broker appearance configures: "+template)
		check(is_instance_valid(actor.visual) and actor.visual.get("skeleton")!=null and not actor.visual.meshes.is_empty(),"Broker displays original animated NPC geometry: "+template)
		actor.free()
	await process_frame
	print(JSON.stringify({"checks":checks,"variants":variants.size(),"errors":errors,"original_assets":true,"mocked_native_rows":true,"renderer":"dummy","headset_validated":false}));quit(0 if errors.is_empty() else 1)
