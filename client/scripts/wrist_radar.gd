extends Node3D
## Passive, bounded wrist display. No gameplay queries or tracking mutations.
const RANGE_METERS := 64.0
const MAX_CONTACTS := 128
const REFRESH_SECONDS := 0.2
const PIXELS := 256
const DIAMETER_METERS := 0.14
# Original SWG relationship colors; source mapping is documented by the provider.
const COLORS = preload("res://scripts/entity_relationship.gd").COLORS
class RadarCanvas extends Control:
	const LABEL_FONT = preload("res://resources/fonts/Jupiteroid-Regular.ttf")
	var points: Array = []
	var heading_degrees := 0.0
	func _draw() -> void:
		var center:=Vector2(128,128)
		var cyan:=preload("res://scripts/datapad_theme.gd").ACCENT
		draw_style_box(preload("res://scripts/datapad_theme.gd").frame(12),Rect2(4,4,248,248))
		draw_circle(center,119,Color(0.015,0.08,0.105,0.83))
		draw_arc(center,118,0,TAU,96,cyan,2,true)
		for radius in [39.0,78.0]: draw_arc(center,radius,0,TAU,64,Color(0.3,0.92,1.0,0.23),1,true)
		for direction in [Vector2.UP,Vector2.RIGHT,Vector2.DOWN,Vector2.LEFT]:
			draw_line(center+direction*104,center+direction*116,cyan,1.5,true)
		draw_line(center+Vector2(-94,0),center+Vector2(94,0),Color(0.3,0.92,1.0,0.10),1,true)
		draw_line(center+Vector2(0,-94),center+Vector2(0,94),Color(0.3,0.92,1.0,0.10),1,true)
		for contact: Dictionary in points:
			var p: Vector2=contact.pixel
			var color: Color=contact.color
			if contact.kind=="mob":
				draw_colored_polygon(PackedVector2Array([p+Vector2(0,-4),p+Vector2(4,0),p+Vector2(0,4),p+Vector2(-4,0)]),color)
			else: draw_circle(p,3.5,color)
			if contact.height_sign!=0:
				var y: float=-7 if contact.height_sign>0 else 7
				var sign_value: float=-1 if contact.height_sign>0 else 1
				draw_polyline(PackedVector2Array([p+Vector2(-2,y-sign_value*2),p+Vector2(0,y),p+Vector2(2,y-sign_value*2)]),color,1.2,true)
		draw_colored_polygon(PackedVector2Array([center+Vector2(0,-9),center+Vector2(6,6),center+Vector2(0,3),center+Vector2(-6,6)]),cyan)
		draw_string(LABEL_FONT,Vector2(108,230),"64m",HORIZONTAL_ALIGNMENT_LEFT,-1,16,cyan)
		draw_string(LABEL_FONT,Vector2(94,38),"%03d°"%(int(round(heading_degrees))%360),HORIZONTAL_ALIGNMENT_CENTER,68,15,cyan)
var sector_canvas: Control
var viewport: SubViewport
var canvas: RadarCanvas
var display: MeshInstance3D
var active := false
var elapsed := REFRESH_SECONDS
var query_count := 0
var refresh_count := 0
var last_contacts: Array = []
var last_forward := Vector3.FORWARD

func configure() -> void:
	viewport=SubViewport.new(); viewport.name="WristRadarViewport"
	viewport.size=Vector2i(PIXELS,PIXELS); viewport.transparent_bg=true; viewport.disable_3d=true
	viewport.gui_disable_input=true; viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
	add_child(viewport)
	canvas=RadarCanvas.new(); canvas.mouse_filter=Control.MOUSE_FILTER_IGNORE
	canvas.custom_minimum_size=Vector2(PIXELS,PIXELS); canvas.size=Vector2(PIXELS,PIXELS)
	viewport.add_child(canvas)
	sector_canvas=preload("res://space/sector_map.gd").new();sector_canvas.compact=true
	sector_canvas.custom_minimum_size=Vector2.ZERO;sector_canvas.size=Vector2(PIXELS,PIXELS)
	sector_canvas.mouse_filter=Control.MOUSE_FILTER_IGNORE;viewport.add_child(sector_canvas);sector_canvas.custom_minimum_size=Vector2.ZERO;sector_canvas.size=Vector2(PIXELS,PIXELS);sector_canvas.hide()
	display=MeshInstance3D.new(); display.name="WristRadarHologram"
	var quad:=QuadMesh.new(); quad.size=Vector2.ONE*DIAMETER_METERS
	display.mesh=quad; display.position=Vector3(0,DIAMETER_METERS*0.5+0.012,0.002)
	display.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material:=StandardMaterial3D.new(); material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA; material.albedo_texture=viewport.get_texture()
	material.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR; material.cull_mode=BaseMaterial3D.CULL_BACK
	display.material_override=material; add_child(display)
	visible=false

func set_sector(data:Dictionary,ship:Dictionary,contacts:Array)->void:
	sector_canvas.set_sector(data,ship,contacts)
	sector_canvas.visible=not data.is_empty();canvas.visible=data.is_empty()

func set_active(value: bool) -> void:
	if active==value: return
	active=value; visible=value
	if active: elapsed=REFRESH_SECONDS
	elif is_instance_valid(viewport): viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED

func tick(delta: float, center: Vector3, forward: Vector3, provider: Callable) -> void:
	if not active: return
	elapsed+=maxf(0.0,delta)
	if elapsed+0.000001<REFRESH_SECONDS: return
	elapsed=0.0 # No backlog or catch-up queries after a stall.
	if sector_canvas.visible:
		sector_canvas.queue_redraw();viewport.render_target_update_mode=SubViewport.UPDATE_ONCE;refresh_count+=1;return
	var contacts: Array=[]
	if provider.is_valid():
		query_count+=1
		var result: Variant=provider.call(center,RANGE_METERS)
		if result is Array: contacts=result
	refresh(center,forward,contacts)

func refresh(center: Vector3, forward: Vector3, contacts: Array) -> void:
	if not active: return
	var flat:=forward.slide(Vector3.UP)
	if flat.length_squared()>0.0001: last_forward=flat.normalized()
	var right:=last_forward.cross(Vector3.UP).normalized()
	var selected: Array=[]
	for value: Variant in contacts:
		if not value is Dictionary or not value.get("position") is Vector3: continue
		var delta: Vector3=value.position-center
		var distance_squared:=Vector2(delta.x,delta.z).length_squared()
		if not delta.is_finite() or distance_squared>RANGE_METERS*RANGE_METERS: continue
		var contact: Dictionary={"id":str(value.get("id","")),"distance_squared":distance_squared,
			"pixel":Vector2(128,128)+Vector2(delta.dot(right),-delta.dot(last_forward))*(104.0/RANGE_METERS),
			"height_sign":signf(delta.y) if absf(delta.y)>3.0 else 0.0,
			"color":COLORS.get(str(value.get("relation","neutral")),COLORS.neutral),"kind":str(value.get("kind","npc"))}
		# Bound retained state even if a provider incorrectly returns too many.
		if selected.size()<MAX_CONTACTS: selected.append(contact)
		else:
			var farthest:=0
			for i in range(1,selected.size()):
				if float(selected[i].distance_squared)>float(selected[farthest].distance_squared): farthest=i
			if distance_squared<float(selected[farthest].distance_squared): selected[farthest]=contact
	last_contacts=selected
	canvas.points=selected
	canvas.heading_degrees=fposmod(rad_to_deg(atan2(last_forward.x,-last_forward.z)),360.0)
	canvas.queue_redraw()
	viewport.render_target_update_mode=SubViewport.UPDATE_ONCE
	refresh_count+=1

func statistics() -> Dictionary:
	return {"active":active,"contacts":last_contacts.size(),"queries":query_count,"refreshes":refresh_count,
		"max_contacts":MAX_CONTACTS,"range_m":RANGE_METERS,"refresh_hz":1.0/REFRESH_SECONDS,"viewport_pixels":PIXELS}
