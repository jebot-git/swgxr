extends SceneTree
## Replay actual matched native mission-contact and world-actor identities.
const Actor=preload("res://combat/live_actor.gd")
const OriginalAvatar=preload("res://scripts/avatar.gd")
const SourceFont=preload("res://resources/fonts/Jupiteroid-Regular.ttf")
var contacts:Dictionary={}
var actors:Dictionary={}
var failures:Array=[]
func _initialize()->void:call_deferred("run")
func scan(value:Variant)->void:
	if value is Dictionary:
		if str(value.get("kind",""))=="delivery":contacts[str(value.id)]=value
		if str(value.get("kind",""))=="creature" and str(value.get("template","")).contains("dressed_commoner_"):actors[str(value.id)]=value
		for child:Variant in value.values():scan(child)
	elif value is Array:
		for child:Variant in value:scan(child)
func run()->void:
	var desktop:=DisplayServer.get_name()!="headless"
	if desktop and (RenderingServer.get_current_rendering_method()!="forward_plus" or RenderingServer.get_current_rendering_driver_name()!="vulkan"):
		push_error("Desktop capture requires Forward+ Vulkan");quit(1);return
	var source:=ProjectSettings.globalize_path("res://../runtime/evidence/delivery-mission-native.json")
	scan(JSON.parse_string(FileAccess.get_file_as_string(source)))
	var selected:Array=[]
	for id:String in contacts:
		var contact:Dictionary=contacts[id]
		if contact.role!="giver" or not actors.has(id):continue
		for other:String in contacts:
			if contacts[other].mission_id==contact.mission_id and contacts[other].role=="receiver" and actors.has(other):selected=[id,other];break
		if not selected.is_empty():break
	if selected.size()!=2:push_error("Recorded matching native giver and receiver required");quit(1);return
	root.size=Vector2i(1440,900)
	var world:=Node3D.new();root.add_child(world)
	var environment:=WorldEnvironment.new();environment.environment=Environment.new();environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color("071421");environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color.WHITE;environment.environment.ambient_light_energy=0.95;world.add_child(environment)
	var floor:=MeshInstance3D.new();var plane:=PlaneMesh.new();plane.size=Vector2(20,20);floor.mesh=plane;var mat:=StandardMaterial3D.new();mat.albedo_color=Color("685a47");mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;floor.material_override=mat;world.add_child(floor)
	var camera:=Camera3D.new();world.add_child(camera);camera.fov=40;camera.position=Vector3(0,1.6,-4.4);camera.look_at(Vector3(0,1.0,0));camera.current=true
	var results:Array=[]
	for index:int in range(selected.size()):
		var id:String=selected[index];var row:Dictionary=actors[id].duplicate(true)
		var actor:=Actor.new();world.add_child(actor)
		actor.configure(row,"recorded-native-mission",RefCounted.new(),RefCounted.new(),ProjectSettings.globalize_path("res://../runtime/assets/ambient_npcs/catalog.json"))
		var pose:=Transform3D(Basis.IDENTITY,Vector3(0.8 if index==0 else -0.8,0,0));actor.apply_record(row,pose,0.1,true);actor.label.visible=false
		var result:Dictionary={"id":id,"role":contacts[id].role,"mission_id":contacts[id].mission_id,"name":row.name,"template":row.template,"source_position":row.position,"render_position":pose.origin,"report":actor.report.duplicate(true),"source":"actual Core3 world actor matched to owned mission contact"}
		if actor.report.appearance_status!="complete":failures.append("Incomplete original appearance: "+row.template)
		if actor.visual==null or not actor.visual is OriginalAvatar:
			failures.append("Original skeletal avatar missing: "+id)
		else:
			var avatar=actor.visual
			result["bones"]=avatar.skeleton.get_bone_count();result["meshes"]=avatar.meshes.size();result["skinned_meshes"]=0;result["wearable_parts"]=0
			for mesh:MeshInstance3D in avatar.meshes:
				if mesh.skin!=null and mesh.skin.get_bind_count()>0 and mesh.get_node_or_null(mesh.skeleton)==avatar.skeleton:result.skinned_meshes+=1
			for part:Dictionary in avatar.loaded_parts:
				if part.scope=="equipment":result.wearable_parts+=1
			if result.skinned_meshes<=0 or result.bones<=0 or result.wearable_parts<=0:failures.append("Missing original skin or clothing: "+id)
		results.append(result)
		var nameplate:=Label.new();root.add_child(nameplate);nameplate.add_theme_font_override("font",SourceFont);nameplate.add_theme_font_size_override("font_size",24);nameplate.position=Vector2(270 if index==0 else 830,775);nameplate.text=str(contacts[id].role).to_upper()+" · "+str(row.name)
	var title:=Label.new();root.add_child(title);title.add_theme_font_override("font",SourceFont);title.add_theme_font_size_override("font_size",27);title.position=Vector2(30,25);title.text="ORIGINAL MISSION CONTACTS · ACTUAL CORE3 IDENTITIES"
	var note:=Label.new();root.add_child(note);note.add_theme_font_override("font",SourceFont);note.add_theme_font_size_override("font_size",20);note.position=Vector2(30,835);note.text="Source bodies, skeletons and clothing · isolated native snapshot replay · desktop Vulkan · XR disabled"
	for frame:int in range(12):await process_frame
	var capture:=""
	if desktop:
		await RenderingServer.frame_post_draw
		capture=ProjectSettings.globalize_path("res://../runtime/evidence/mission-native-npcs-vulkan.png");root.get_texture().get_image().save_png(capture)
	var report:Dictionary={"passed":failures.is_empty(),"failures":failures,"actors":results,"source":source,"capture":capture,"renderer":RenderingServer.get_current_rendering_method(),"driver":RenderingServer.get_current_rendering_driver_name(),"gpu":RenderingServer.get_video_adapter_name() if desktop else "dummy","headset_validated":false,"font":"Jupiteroid Regular"}
	FileAccess.open(ProjectSettings.globalize_path("res://../runtime/evidence/mission-native-npcs.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  "));print(JSON.stringify(report));world.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
