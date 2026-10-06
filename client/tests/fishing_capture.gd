extends SceneTree
func _initialize()->void:run.call_deferred()
func run()->void:
	var world:=Node3D.new();root.add_child(world)
	var environment:=WorldEnvironment.new();var settings:=Environment.new();settings.background_mode=Environment.BG_COLOR;settings.background_color=Color('08151e');environment.environment=settings;world.add_child(environment)
	var camera:=Camera3D.new();world.add_child(camera);camera.position=Vector3(.06,.08,1.1);camera.current=true;camera.fov=55
	var assets=preload('res://scripts/inventory_assets.gd').new();assets.configure()
	var rod:=MeshInstance3D.new();rod.mesh=assets.model('object/tangible/fishing/fishing_pole.iff');world.add_child(rod);rod.transform=Transform3D(Basis(Vector3.RIGHT,-PI/2+.65),Vector3(-.3,-.24,0))
	var tray=preload('res://fishing/bait_slots.gd').new();world.add_child(tray);tray.setup(assets);tray.position=Vector3(-.16,.10,.02)
	var baits:Array=[]
	for name in ['worm','grub','insect','chum']:baits.append({'id':name,'template':'object/tangible/fishing/bait/bait_'+name+'.iff','name':name.capitalize(),'use_count':5})
	tray.configure(baits,'Fresh',true,'object/tangible/fishing/bait/bait_worm.iff')
	var title:=Label3D.new();world.add_child(title);title.text='FISHING · BAIT';title.font=preload('res://resources/fonts/Jupiteroid-Regular.ttf');title.font_size=38;title.pixel_size=.0006;title.position=Vector3(.08,.32,.02);title.modulate=Color('baffff')
	var help:=Label3D.new();world.add_child(help);help.text='Grip bait · drag into the rod slot\nHold trigger · swing back/forward · release to cast';help.font=title.font;help.font_size=24;help.pixel_size=.0005;help.position=Vector3(.09,-.19,.1);help.modulate=Color('baffff')
	var note:=Label3D.new();world.add_child(note);note.text='DESKTOP UI FIXTURE · ORIGINAL SWG ASSETS · NO NATIVE SESSION';note.font_size=18;note.pixel_size=.00035;note.position=Vector3(.04,-.32,.02);note.modulate=Color('6b93a7')
	for i in 12:await process_frame
	await RenderingServer.frame_post_draw
	var path:='res://../runtime/evidence/fishing-bait-vulkan.png';var result:=root.get_texture().get_image().save_png(path);print('FISHING_CAPTURE ',result,' ',RenderingServer.get_current_rendering_method())
	world.free();quit(result)
