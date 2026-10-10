extends RefCounted
## Original planet maps with destinations returned by Core3; clicks only select.
const RECT=Rect2(430,128,340,340)
var catalog:Dictionary={}
var textures:Dictionary={}
var directory:=""
func setup()->void:
	if not directory.is_empty():return
	directory=preload("res://scripts/avatar.gd").asset_path("res://../runtime/assets/datapad")
	catalog=preload("res://scripts/avatar.gd").read_json(directory.path_join("catalog.json"))
func planet(row:Dictionary)->String:return str(row.get("planet",row.get("destination_planet",row.get("zone",""))))
func pixel(row:Dictionary)->Vector2:
	setup()
	var point:Variant=row.get("position")
	if not point is Array or point.size()!=3:return Vector2.INF
	var bounds:Array=catalog.get("maps",{}).get(planet(row),{}).get("world_bounds",[-8192,-8192,8192,8192])
	return RECT.position+Vector2((float(point[0])-bounds[0])/(bounds[2]-bounds[0]),(bounds[3]-float(point[2]))/(bounds[3]-bounds[1]))*RECT.size
func select_at(at:Vector2,rows:Array,selected:int)->int:
	if not RECT.has_point(at) or rows.is_empty():return -1
	var zone:=planet(rows[selected if selected>=0 and selected<rows.size() else 0]);var best:=-1;var distance:=14.0
	for i in rows.size():
		if planet(rows[i])!=zone:continue
		var p:=pixel(rows[i]);var d:=at.distance_to(p)
		if p.is_finite() and d<distance:best=i;distance=d
	return best
func draw(panel:Control,rows:Array,selected:int,font:Font)->void:
	setup()
	if rows.is_empty():return
	var row:Dictionary=rows[selected if selected>=0 and selected<rows.size() else 0]
	var zone:=planet(row)
	if not textures.has(zone):
		var path:=directory.path_join(str(catalog.get("maps",{}).get(zone,{}).get("texture","")))
		var image:=Image.load_from_file(path) if FileAccess.file_exists(path) else null
		textures[zone]=ImageTexture.create_from_image(image) if image!=null else null
	panel.draw_rect(RECT,Color("10202c"))
	if textures[zone]!=null:panel.draw_texture_rect(textures[zone],RECT,false)
	else:panel.draw_string(font,RECT.position+Vector2(12,30),"Original planet map unavailable",HORIZONTAL_ALIGNMENT_LEFT,320,18)
	panel.draw_string(font,Vector2(430,115),zone.capitalize()+" · Spaceport destinations",HORIZONTAL_ALIGNMENT_LEFT,400,19,Color("c9fbff"))
	for i in rows.size():
		if planet(rows[i])!=zone:continue
		var p:=pixel(rows[i])
		if not p.is_finite() or not RECT.has_point(p):continue
		panel.draw_circle(p,8 if i==selected else 5,Color("071119"))
		panel.draw_circle(p,5 if i==selected else 3,Color("ffe399") if i==selected else Color("8df5fa"))
		if i==selected:panel.draw_arc(p,11,0,TAU,32,Color("ffe399"),2,true)
	if selected>=0:
		panel.draw_string(font,Vector2(430,480),str(row.get("name",row.get("id","Destination")))+" · %d cr"%int(row.get("price",0)),HORIZONTAL_ALIGNMENT_LEFT,400,17,Color("ffe399"))
	else:panel.draw_string(font,Vector2(430,480),"Select a destination to see its marker and fare",HORIZONTAL_ALIGNMENT_LEFT,400,16,Color("c9fbff"))
