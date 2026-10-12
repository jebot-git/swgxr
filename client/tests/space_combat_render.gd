extends SceneTree
func _initialize()->void:call_deferred("run")
func run()->void:
	root.size=Vector2i(1280,720)
	var eye:=Camera3D.new();root.add_child(eye);eye.current=true;eye.position=Vector3(0,2,12)
	var env:=Environment.new();env.background_mode=Environment.BG_COLOR;env.background_color=Color(.005,.008,.02);eye.environment=env
	var fx:=preload("res://space/combat_effects.gd").new();root.add_child(fx)
	for index in range(4):
		fx.receive([{"id":str(index),"kind":"hit","hit_type":index,"position":[(index-1.5)*6,0,0],"age_seconds":0}])
		var label:=Label3D.new();label.text=["SHIELD","ARMOR","COMPONENT","CHASSIS"][index];label.position=Vector3((index-1.5)*6,-2,0);root.add_child(label)
	for i in range(3):fx.receive([{"id":"bolt"+str(i),"kind":"projectile","projectile_type":i+1,"position":[(i-1)*6,4,0],"direction":[1,0,0],"speed":1,"range":10,"age_seconds":0}])
	await create_timer(.3).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://../runtime/evidence/jtl2-20261012/original-effects.png")
	print(JSON.stringify({"renderer":RenderingServer.get_current_rendering_method(),"effects":fx.effects.size(),"missing":fx.missing,"live_xr":false}));quit()
