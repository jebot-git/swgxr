extends SubViewport
## Reuses original inventory meshes; renders once per selection, never continuously.
var assets:=preload("res://scripts/inventory_assets.gd").new()
var models:Node3D
var key:=""
var model_ready:=false
func _ready()->void:
	size=Vector2i(244,170);transparent_bg=true;own_world_3d=true;gui_disable_input=true;render_target_update_mode=SubViewport.UPDATE_DISABLED
	models=Node3D.new();add_child(models)
	var camera:=Camera3D.new();add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=1.8;camera.position=Vector3(0,0,3);camera.current=true
func show_item(item:Dictionary)->bool:
	var current:=str(item.get("id",""))+":"+str(item.get("template",""))
	if current==key:return model_ready
	key=current;model_ready=false
	for child in models.get_children():child.free()
	if not str(item.get("template","")).is_empty():
		if assets.catalog.is_empty():assets.configure()
		var model:=assets.instance(str(item.template),1.35,item.get("customization",{}))
		if model!=null:
			var pivot:=Node3D.new();models.add_child(pivot);pivot.rotation=Vector3(-.12,.65,0);pivot.add_child(model);model_ready=true
	render_target_update_mode=SubViewport.UPDATE_ONCE
	return model_ready
func suspend()->void:render_target_update_mode=SubViewport.UPDATE_DISABLED
