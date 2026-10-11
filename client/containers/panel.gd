extends "res://gcw/panel.gd"
## The same inventory grid and original item models used by the held backpack.
const Grid=preload("res://scripts/inventory_ui.gd")
const GRID_POSITION=Vector2(30,62)
const GRID_SCALE=.78
var grid:Control
var models:SubViewport
var scene:Node3D
var assets=preload("res://scripts/inventory_assets.gd").new()
func _ready()->void:
	super()
	assets.configure()
	grid=Grid.new();add_child(grid);grid.position=GRID_POSITION;grid.scale=Vector2.ONE*GRID_SCALE
	var details:Control=grid.configure_details();add_child(details);details.hide();grid.hide()
	models=SubViewport.new();models.size=Vector2i(1024,640);models.transparent_bg=true;models.own_world_3d=true;models.gui_disable_input=true;models.render_target_update_mode=SubViewport.UPDATE_DISABLED;add_child(models)
	scene=Node3D.new();models.add_child(scene)
	var camera:=Camera3D.new();models.add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=640;camera.position.z=500;camera.far=1000;camera.current=true
	var image:=TextureRect.new();grid.add_child(image);image.size=Vector2(1024,640);image.texture=models.get_texture();image.mouse_filter=Control.MOUSE_FILTER_IGNORE
	grid.page_changed.connect(rebuild_models)
func storage_mode()->bool:return terminal.get("kind","")=="container"
func configure(record:Dictionary,balances:Dictionary,held_tickets:Array=[])->void:
	super(record,balances,held_tickets)
	if not is_instance_valid(grid):return
	grid.visible=storage_mode()
	if storage_mode():
		grid.set_snapshot(record.get("storage",{}));grid.container_switch.hide();grid.status="Grip an item to take it · Release a held item here to store";grid.queue_redraw()
	else:models.render_target_update_mode=SubViewport.UPDATE_DISABLED
func rebuild_models()->void:
	for child in scene.get_children():child.free()
	grid.unavailable.clear()
	var items:Array=grid.visible_items()
	for i in range(items.size()):
		var item:Dictionary=items[i]
		var model:Node3D=assets.instance(str(item.get("template","")),72,item.get("customization",{}))
		if model==null:grid.unavailable[str(item.get("id",""))]=true;continue
		var cell:=Node3D.new();scene.add_child(cell)
		var pixel:Vector2=Grid.GRID_ORIGIN+Vector2(i%8,i/8)*Grid.CELL+Vector2(59,48)
		cell.position=Vector3(pixel.x-512,320-pixel.y,0);cell.rotation=Vector3(-.12,.65,0);cell.add_child(model)
	grid.queue_redraw();models.render_target_update_mode=SubViewport.UPDATE_ONCE
func storage_item_at(pixel:Vector2)->Dictionary:
	return grid.item_at((pixel-GRID_POSITION)/GRID_SCALE) if storage_mode() and not pending else {}
func pointer_begin(pixel:Vector2)->void:
	if not storage_mode():super(pixel);return
	if pending:return
	pointer_down=true;down_pixel=pixel
func pointer_move(pixel:Vector2)->void:
	if not storage_mode():super(pixel)
func pointer_end(pixel:Vector2)->void:
	if not storage_mode():super(pixel);return
	if not pointer_down:return
	pointer_down=false
	if pending or down_pixel.distance_to(pixel)>16:return
	if CLOSE_RECT.has_point(pixel):close_requested.emit();return
	var item:=storage_item_at(pixel)
	if not item.is_empty():grid.select_item(item);return
	if pixel.y<565:return
	var storage:Dictionary=terminal.get("storage",{})
	var target:=str(storage.get("inventory",{}).get("id",""))
	if pixel.x<270:
		if not grid.detail_item.get("is_container",false):return
		target=str(grid.detail_item.get("id",""))
	elif pixel.x<535:target=str(storage.get("inventory",{}).get("parent_id",target))
	if not target.is_empty():action_requested.emit("open",{"terminal_id":str(terminal.id),"container_id":target})
func scroll_at(pixel:Vector2,steps:int)->void:
	if not storage_mode():super(pixel,steps);return
	if not pending:grid.navigate(steps,(pixel-GRID_POSITION)/GRID_SCALE)
func _draw()->void:
	if not storage_mode():super();return
	draw_style_box(Holo.frame(12,"wide"),Rect2(Vector2.ZERO,Vector2(860,620)))
	draw_string(FONT,Vector2(24,38),str(terminal.get("name","Container")),HORIZONTAL_ALIGNMENT_LEFT,765,25,Color("d2f6ff"))
	draw_string(FONT,Vector2(815,39),"×",HORIZONTAL_ALIGNMENT_LEFT,-1,27,Color("d2f6ff"))
	for entry in [["Open selected container",20],["Parent container",280],["Refresh",545]]:
		draw_string(FONT,Vector2(entry[1],584),entry[0],HORIZONTAL_ALIGNMENT_LEFT,255,18,Color("9ac7da"))
	draw_string(FONT,Vector2(24,610),message,HORIZONTAL_ALIGNMENT_LEFT,812,17,Color("9ac7da"))
