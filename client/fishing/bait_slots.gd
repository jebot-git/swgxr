extends Node3D
## Same physical resource-cube pattern as crafting, backed by owned bait IDs.
signal dropped(bait:Dictionary)
const PAGE_SIZE:=8
var assets:RefCounted
var rows:Array=[]
var cubes:Array[Node3D]=[]
var slot:MeshInstance3D
var label:Label3D
var loaded:Node3D
var loaded_template:=""
var drag:Node3D
var selected:Dictionary={}
var grip_down:=true
var page:=0
var page_down:=false
var key:=""
static func material(alpha:float)->StandardMaterial3D:
	var m:=StandardMaterial3D.new();m.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;m.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;m.albedo_color=Color(.12,.8,.95,alpha);return m
func setup(source:RefCounted)->void:
	assets=source;slot=cube(Vector3(.085,.085,.085));add_child(slot)
	label=Label3D.new();label.font=preload("res://resources/fonts/Jupiteroid-Regular.ttf");label.font_size=24;label.pixel_size=.0005;label.modulate=Color("baffff");label.outline_size=3;label.position=Vector3(0,.08,0);add_child(label)
func cube(size:Vector3)->MeshInstance3D:
	var node:=MeshInstance3D.new();var box:=BoxMesh.new();box.size=size;node.mesh=box;node.material_override=material(.12);return node
func configure(baits:Array,bait_status:String,enabled:bool,bait_template:String="")->void:
	if bait_template!=loaded_template:
		loaded_template=bait_template
		if is_instance_valid(loaded):loaded.free()
		loaded=assets.instance(bait_template,.055) if not bait_template.is_empty() else null
		if loaded!=null:slot.add_child(loaded)
	label.text="BAIT · "+bait_status
	var next:=JSON.stringify([baits,page,enabled])
	if next==key:return
	key=next;rows=baits.duplicate(true);page=clampi(page,0,maxi(0,(rows.size()-1)/PAGE_SIZE));cancel_drag()
	for cell in cubes:cell.free()
	cubes.clear()
	if not enabled:return
	for index in range(page*PAGE_SIZE,mini(rows.size(),(page+1)*PAGE_SIZE)):
		var cell:=cube(Vector3(.067,.067,.067));add_child(cell);cell.position=Vector3(.16+float(index%4)*.085,-.06-float((index%PAGE_SIZE)/4)*.09,0);cell.set_meta("bait",rows[index]);cubes.append(cell)
		var model:Node3D=assets.instance(str(rows[index].template),.05)
		if model!=null:cell.add_child(model)
		var title:=Label3D.new();title.text=str(rows[index].get("name","Bait")).get_slice(" ",0)+" ×"+str(maxi(1,int(rows[index].get("use_count",1))));title.font_size=14;title.pixel_size=.00035;title.position=Vector3(0,-.042,.012);title.modulate=Color("baffff");cell.add_child(title)
func cancel_drag()->void:
	selected={};grip_down=true
	if is_instance_valid(drag):drag.free()
	drag=null
func sample(point:Vector3,grip:float,stick:Vector2,permitted:bool)->void:
	if not permitted:cancel_drag();return
	if absf(stick.y)<.25:page_down=false
	elif absf(stick.y)>.65 and not page_down and selected.is_empty():
		page_down=true;page=clampi(page+(-1 if stick.y>0 else 1),0,maxi(0,(rows.size()-1)/PAGE_SIZE));key=""
	var pressed:=grip_down
	if grip<.25:pressed=false
	elif grip>.65:pressed=true
	if pressed and not grip_down and selected.is_empty():
		for cell in cubes:
			if cell.global_position.distance_to(point)<.055:
				selected=cell.get_meta("bait").duplicate(true);drag=assets.instance(str(selected.template),.055);if drag!=null:add_child(drag)
				break
	if is_instance_valid(drag):drag.global_position=point
	if not pressed and grip_down and not selected.is_empty():
		var item:=selected.duplicate(true);var inside:=slot.global_position.distance_to(point)<.075;cancel_drag()
		if inside:dropped.emit(item)
	grip_down=pressed
