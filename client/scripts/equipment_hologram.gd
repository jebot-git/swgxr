extends Node3D
## Local frozen presentation: no actor script, controller, collision or network ID.
signal loadout_proposed(value:Dictionary)
var ability_editor:Node3D
var ability_context:Dictionary={}
const HEIGHT := 0.54
const MAX_MARKERS := 32
const PAGE_ROWS := 4
const FONT = preload("res://resources/fonts/Jupiteroid-Regular.ttf")
var frozen: Node3D
var skeleton: Skeleton3D
var source_avatar: Node3D
var equipment: Array = []
var incoming: Dictionary = {}
var markers: Dictionary = {}
var highlighted: Dictionary = {}
var panels: Array[Node3D] = []
var labels: Array[Label3D] = []
var active := false
var page := 0
var comparison_rows: Array = []
var status := ""
var offhand := "left"
var report: Dictionary = {}
var browsing := false
var equipment_targets: Dictionary = {}

func configure(source: Node3D, current_equipment: Array) -> void:
	source_avatar=source; equipment=current_equipment.duplicate(true)
	for child in get_children():
		remove_child(child); child.queue_free()
	frozen=null; skeleton=null; markers.clear(); panels.clear(); labels.clear()
	report={"meshes":0,"bones":0,"markers":0,"physics_bodies":0,"actors":0,"error":"","unsupported_slots":[]}
	if not is_instance_valid(source) or source.get("visual_root")==null:
		report.error="Current character appearance is unavailable."; return
	frozen=source.visual_root.duplicate(0)
	add_child(frozen)
	var source_height:=maxf(0.5,float(source.get("height_meters")))
	frozen.scale*=HEIGHT/source_height
	frozen.position*=HEIGHT/source_height
	frozen.rotation.y=PI # Original characters face -Z; inspection faces the viewer.
	freeze_nodes(frozen)
	if skeleton==null: report.error="Current character skeleton is unavailable."
	create_panel(-0.38,0.22,"CURRENT EQUIPMENT")
	create_panel(0.38,-0.22,"HELD ITEM")
	ability_editor=preload("res://scripts/equipment_abilities.gd").new();add_child(ability_editor);ability_editor.setup(self);ability_editor.observe(ability_context)
	ability_editor.proposed.connect(func(value):loadout_proposed.emit(value))
	visible=false; active=false

func freeze_nodes(node: Node) -> void:
	node.process_mode=Node.PROCESS_MODE_DISABLED
	if node is Skeleton3D:
		skeleton=node; report.bones=node.get_bone_count()
	if node is MeshInstance3D:
		node.visible=true; node.layers=1; node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for surface in range(node.mesh.get_surface_count()):
			var original: Material=node.get_active_material(surface)
			var material:=ShaderMaterial.new()
			material.shader=preload("res://shaders/equipment_hologram.gdshader")
			if original is ShaderMaterial:
				var texture: Variant=original.get_shader_parameter("main_texture")
				if not texture is Texture2D: texture=original.get_shader_parameter("albedo_texture")
				if texture is Texture2D: material.set_shader_parameter("source_texture",texture); material.set_shader_parameter("has_texture",true)
				material.set_shader_parameter("alpha_cutout",bool(original.get_shader_parameter("alpha_cutout")))
			elif original is StandardMaterial3D and original.albedo_texture!=null:
				material.set_shader_parameter("source_texture",original.albedo_texture); material.set_shader_parameter("has_texture",true)
			node.set_surface_override_material(surface,material)
		report.meshes+=1
	for child in node.get_children():
		if child is AnimationPlayer or child is CollisionObject3D or child is SkeletonModifier3D:
			child.free(); continue
		if child.get_script()!=null: child.set_script(null)
		freeze_nodes(child)

func create_panel(x: float, yaw: float, title: String) -> void:
	var panel:=Node3D.new(); add_child(panel); panel.position=Vector3(x,0.29,0); panel.rotation.y=yaw
	var mesh:=MeshInstance3D.new(); var quad:=QuadMesh.new(); quad.size=Vector2(0.27,0.36); mesh.mesh=quad
	var material:=StandardMaterial3D.new(); material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED; material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA; material.albedo_color=Color(0.015,0.08,0.12,0.91); mesh.material_override=material; mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	panel.add_child(mesh)
	var label:=Label3D.new(); panel.add_child(label); label.font=FONT; label.font_size=22; label.pixel_size=0.00075; label.width=320
	label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; label.horizontal_alignment=HORIZONTAL_ALIGNMENT_LEFT; label.vertical_alignment=VERTICAL_ALIGNMENT_TOP; label.position=Vector3(-0.12,0.165,0.002)
	label.outline_size=0; label.modulate=Color("c9fbff"); label.render_priority=10; label.text=title
	panels.append(panel); labels.append(label)

func show_item(item: Dictionary, head: Transform3D) -> bool:
	if not report.get("error","").is_empty(): return false
	browsing=false; equipment_targets.clear()
	incoming=item.duplicate(true); highlighted={}; page=0; status=""
	for marker in markers.values():
		remove_child(marker); marker.queue_free()
	markers.clear()
	var ids: Array=[]
	for arrangement: Dictionary in incoming.get("equip_arrangements",[]):
		for slot: Variant in arrangement.get("slots",[]):
			if not ids.has(str(slot)): ids.append(str(slot))
	if not str(incoming.get("tool_kind","")).is_empty(): ids.append("prototype_tool_hip")
	for id: String in ids:
		if markers.size()>=MAX_MARKERS: break
		var anchor: Variant=slot_anchor(id)
		if not anchor is Vector3: report.unsupported_slots.append(id); continue
		var ring:=MeshInstance3D.new(); var sphere:=SphereMesh.new(); sphere.radius=0.022; sphere.height=0.044; sphere.radial_segments=12; sphere.rings=6; ring.mesh=sphere
		var material:=StandardMaterial3D.new(); material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED; material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA; material.albedo_color=Color(0.1,0.8,1,0.35); ring.material_override=material; ring.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(ring); ring.position=anchor; markers[id]=ring
	var forward:=(-head.basis.z).slide(Vector3.UP).normalized()
	if forward.length_squared()<0.5: forward=Vector3.FORWARD
	global_transform=Transform3D(Basis.looking_at(forward,Vector3.UP),head.origin+forward*0.67-Vector3.UP*0.46)
	active=true; visible=true; report.markers=markers.size()
	update_comparison({}); return true

func show_equipment(head: Transform3D) -> bool:
	# Reuse original avatar anchors; each actual equipped object gets its own
	# reachable marker even when several layers occupy the same source slot.
	if not show_item({},head):return false
	browsing=true
	var offsets:Dictionary={}
	for item:Dictionary in equipment:
		var slots:Array=item.get("equipped_slots",[])
		if not item.get("equipped",true) or slots.is_empty():continue
		var anchor:Variant=slot_anchor(str(slots[0]))
		if not anchor is Vector3:continue
		var slot:=str(Vector3(anchor).snapped(Vector3.ONE*.025));var layer:=int(offsets.get(slot,0));offsets[slot]=layer+1
		anchor+=Vector3(0.065*layer,0,0.018*layer)
		var marker:=MeshInstance3D.new();var shape:=SphereMesh.new();shape.radius=.018;shape.height=.036;shape.radial_segments=12;shape.rings=6;marker.mesh=shape
		var material:=StandardMaterial3D.new();material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;material.albedo_color=Color("59d5f0");marker.material_override=material
		add_child(marker);marker.position=anchor
		var id:=str(item.get("id",""));markers[id]=marker;equipment_targets[id]=item.duplicate(true)
	labels[0].text="EQUIPPED ITEMS\n\nTouch a glowing item and squeeze grip.\n\nOpen your backpack with the other hand, then release the item inside it."
	labels[1].text="SELECT EQUIPMENT\n\nItems stay equipped until Core3 confirms their return to inventory.\n\nRight stick click: combat abilities."
	return true

func equipped_at(position:Vector3)->Dictionary:
	if is_instance_valid(ability_editor) and ability_editor.active:return {}
	if not active or not browsing:return {}
	var nearest:=.055;var selected:Dictionary={}
	for id:String in equipment_targets:
		var distance:float=markers[id].global_position.distance_to(position)
		if distance<nearest:nearest=distance;selected=equipment_targets[id]
	if not selected.is_empty():
		labels[1].text=str(selected.get("name","Equipment"))+"\n\n"+("Grip to drag to inventory" if selected.get("unequip_available",false) else str(selected.get("unequip_block_reason","Cannot remove this item.")))
	return selected.duplicate(true)

func bone_anchor(names: Array) -> Variant:
	if skeleton==null: return null
	for name: String in names:
		var index:=skeleton.find_bone(name)
		if index>=0: return global_transform.affine_inverse()*(skeleton.global_transform*skeleton.get_bone_global_pose(index)).origin
	return null

func slot_anchor(slot: String) -> Variant:
	if slot=="prototype_tool_hip":
		var hip: Variant=bone_anchor(["root","spine1"])
		return hip+Vector3(0.085 if offhand=="left" else -0.085,-0.02,0) if hip is Vector3 else null
	var direct: Variant=bone_anchor([slot])
	if direct is Vector3: return direct
	var aliases: Dictionary={"hold_r":["rwrist","rhand"],"hold_l":["lwrist","lhand"],"head":["head"],"hat":["head"],"neck":["neck"],"chest1":["spine3","spine2"],"chest2":["spine3","spine2"],"chest3":["spine3","spine2"],"back":["spine3","spine2"],"belt":["root","spine1"],"pants1":["root","spine1"],"pants2":["root","spine1"],"shoes":["lankle","lfoot"],"bicep_l":["larm","lclav"],"bicep_r":["rarm","rclav"],"bracer_upper_l":["lforearm","lelbow"],"bracer_upper_r":["rforearm","relbow"],"bracer_lower_l":["lwrist"],"bracer_lower_r":["rwrist"],"gloves":["rwrist"],"wrist_l":["lwrist"],"wrist_r":["rwrist"],"utility_belt":["root","spine1"],"chest3_l":["lclav","spine3"],"chest3_r":["rclav","spine3"],"earring_l":["leye","head"],"earring_r":["reye","head"],"ring_l":["lindex01","lwrist"],"ring_r":["rindex01","rwrist"],"eyes":["head"],"mouth":["jaw","head"],"hair":["head"],"cloak":["spine3","spine2"]}
	var result: Variant=bone_anchor(aliases.get(slot,[]))
	if result is Vector3:
		# Move a back slot slightly sideways so it remains reachable from the front.
		if slot in ["back","cloak"]: result+=Vector3(0.09,0,0)
		elif slot in ["earring_l","earring_r"]: result.x+=0.018*signf(result.x)
		elif slot in ["hat","hair"]: result.y+=0.025
		elif slot=="eyes": result.z+=0.025
		return result
	return null

func update_hand(position: Vector3) -> Dictionary:
	if not active or (is_instance_valid(ability_editor) and ability_editor.active): return {}
	if browsing:return equipped_at(position)
	var nearest:=0.075; var target: Dictionary={}
	for slot: String in markers:
		var distance: float=markers[slot].global_position.distance_to(position)
		if distance>nearest: continue
		if slot=="prototype_tool_hip":
			nearest=distance; target={"prototype_tool_slot":true,"available":true,"slots":[slot],"highlight_slot":slot,"displaced_item_ids":incoming.get("tool_hip_displaced_ids",[])}; continue
		var matching: Array=[]
		for arrangement: Dictionary in incoming.get("equip_arrangements",[]):
			if slot in arrangement.get("slots",[]): matching.append(arrangement)
		if matching.is_empty(): continue
		matching.sort_custom(func(a,b): return bool(a.get("available",false)) and not bool(b.get("available",false)))
		nearest=distance; target=matching[0].duplicate(true); target["highlight_slot"]=slot
	if target!=highlighted:
		highlighted=target; page=0; update_comparison(target)
	for slot: String in markers:
		var selected: bool=not target.is_empty() and slot in target.get("slots",[])
		markers[slot].material_override.albedo_color=Color(0.2,1,0.55,0.85) if selected and bool(target.get("available",false)) else Color(1,0.25,0.15,0.85) if selected else Color(0.1,0.8,1,0.35)
	return highlighted.duplicate(true)

func update_comparison(arrangement: Dictionary) -> void:
	if labels.size()!=2: return
	var current: Array=[]
	var displaced: Array=arrangement.get("displaced_item_ids",[])
	for item: Dictionary in equipment:
		if str(item.get("id","")) in displaced: current.append(item)
	comparison_rows=[]
	var keys: Array=[]
	var incoming_values:=attribute_values([incoming])
	var current_values:=attribute_values(current)
	for key: String in incoming_values: keys.append(key)
	for key: String in current_values:
		if not keys.has(key): keys.append(key)
	for key: String in keys:
		comparison_rows.append({"name":key.get_slice(":",key.get_slice_count(":")-1).trim_prefix("cat_").replace("_"," ").capitalize(),"current":current_values.get(key,"—"),"incoming":incoming_values.get(key,"—")})
	var pages:=maxi(1,int(ceil(float(comparison_rows.size())/PAGE_ROWS)))
	page=clampi(page,0,pages-1)
	labels[0].text="CURRENT EQUIPMENT  %d/%d\n\n"%[page+1,pages]
	if arrangement.is_empty(): labels[0].text+="Move the held item near a glowing slot.\n"
	elif current.is_empty(): labels[0].text+="Empty slot\n"
	else:
		for item: Dictionary in current: labels[0].text+=str(item.get("name","Item"))+"\n"
	labels[1].text="HELD ITEM  %d/%d\n\n%s\n"%[page+1,pages,str(incoming.get("name","Item"))]
	for row: Dictionary in comparison_rows.slice(page*PAGE_ROWS,(page+1)*PAGE_ROWS):
		labels[0].text+="\n"+str(row.name)+": "+str(row.current)+"\n"
		labels[1].text+="\n"+str(row.name)+": "+str(row.incoming)+"\n"
	var hint: String=""
	if not arrangement.is_empty(): hint="Release grip to request tool holster" if arrangement.get("prototype_tool_slot",false) else "Release grip to equip" if bool(arrangement.get("available",false)) else str(arrangement.get("block_reason","Cannot equip here"))
	elif markers.is_empty(): hint="No supported hologram anchor for this item."
	labels[1].text+="\n"+(status if not status.is_empty() else hint)
	if pages>1:
		labels[0].text+="\nStick up/down: compare more"
		labels[1].text+="\nStick up/down: compare more"
	# Matched original examine fields only. No fabricated sums or stat deltas.

func attribute_values(items: Array) -> Dictionary:
	var result: Dictionary={}
	for item: Dictionary in items:
		for attribute: Variant in item.get("attributes",[]):
			if not attribute is Dictionary: continue
			var key:=str(attribute.get("name",""))
			var value:=str(attribute.get("value",""))
			if items.size()>1: value=str(item.get("name","Item"))+": "+value
			result[key]=str(result[key])+"; "+value if result.has(key) else value
	return result

func scroll_page(direction: int) -> void:
	if is_instance_valid(ability_editor) and ability_editor.active:ability_editor.scroll(direction);return
	var next:=clampi(page+direction,0,maxi(0,int(ceil(float(comparison_rows.size())/PAGE_ROWS))-1))
	if next==page: return
	page=next; update_comparison(highlighted)

func set_status(message: String) -> void:
	status=message
	if active and is_instance_valid(ability_editor) and ability_editor.active:
		if not message.is_empty():labels[1].text=message
		return
	if active:
		if browsing and labels.size()>1:labels[1].text=message
		else:update_comparison(highlighted)

func set_ability_context(value:Dictionary)->void:
	ability_context=value.duplicate(true)
	if is_instance_valid(ability_editor):ability_editor.observe(value)

func close() -> void:
	if is_instance_valid(ability_editor):ability_editor.close()
	active=false; visible=false; highlighted={}
