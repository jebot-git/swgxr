extends SceneTree
var failures:Array=[]
var checks:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);push_error(label)
func chain(texture:Texture2D,label:String)->void:
	check(texture!=null,label+" loads")
	if texture==null:return
	var image:=texture.get_image()
	check(image.has_mipmaps() and image.get_mipmap_count()==int(floor(log(maxi(image.get_width(),image.get_height()))/log(2))),label+" has the complete mip chain")
func _initialize()->void:create_timer(30).timeout.connect(func():quit(2));call_deferred("run")
func run()->void:
	var combat=preload("res://combat/original_assets.gd").new();check(combat.load_catalog(),"Original combat catalogue available")
	chain(combat.texture(str(combat.catalog.reticle.path)),"Original reticle")
	var effects=preload("res://combat/original_assets.gd").new();effects.directory=ProjectSettings.globalize_path("res://../runtime/assets/space_effects");check(effects.load_catalog(),"Original effect catalogue available")
	chain(effects.texture(str(effects.catalog.nebula["0"].MAIN.path)),"Original nebula artwork")
	var entertainer=preload("res://entertainment/effects.gd").EffectResources.new();entertainer.directory=effects.directory
	chain(entertainer.texture(str(effects.catalog.nebula["0"].MAIN.path)),"Entertainer resource cache")
	var image:=Image.create(4,4,false,Image.FORMAT_RGBA8)
	for x in range(4):
		for y in range(4):image.set_pixel(x,y,Color(1,.5,.5,.25) if x%2==0 else Color(.5,1,.5,.75))
	var path:="user://mipmap-smoke.png";image.save_png(path)
	var normal=preload("res://scripts/avatar_materials.gd").texture(path,"",true)
	var packed=preload("res://scripts/avatar_materials.gd").texture(path,"")
	chain(normal,"Conventional RGB normal map");chain(packed,"Packed-channel map")
	var normalized:PackedByteArray=normal.get_image().get_data().slice(-4)
	var encoded:PackedByteArray=packed.get_image().get_data().slice(-4)
	var vector:=Vector3(normalized[0],normalized[1],normalized[2])/255*2-Vector3.ONE
	check(absf(vector.length()-1)<.02,"RGB normal mip renormalizes the averaged vector")
	check(absi(int(encoded[0])-191)<=1 and absi(int(encoded[1])-191)<=1 and absi(int(encoded[3])-127)<=1,"Packed normals preserve independently averaged channels")
	check(normal!=packed,"Normal and packed-channel cache entries stay distinct")
	var particles=preload("res://space/original_particles.gd").new()
	var definition:Dictionary={"alpha":{"points":[[0,1,0,0],[1,0,0,0]],"interpolation":0}}
	check(not particles.curve_image(definition,["alpha"]).get_image().has_mipmaps(),"Particle curve lookup stays unmipped")
	particles.free();DirAccess.remove_absolute(path)
	var stars=preload("res://space/starfield.gd").new().build(10,null)
	if DisplayServer.get_name()!="headless":
		for i in range(6):check(stars.get_layer_data(i).has_mipmaps(),"Star cubemap face retains mipmaps: "+str(i))
	print(JSON.stringify({"passed":failures.is_empty(),"checks":checks,"failures":failures,"renderer":"dummy" if DisplayServer.get_name()=="headless" else RenderingServer.get_current_rendering_method(),"xr":false}))
	quit(0 if failures.is_empty() else 1)
