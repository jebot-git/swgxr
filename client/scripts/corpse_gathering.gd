extends Node3D
## Dominant empty-hand interaction with provider-verified native Core3 corpses.
signal corpse_inspect_requested(record: Dictionary)
signal corpse_harvest_requested(record: Dictionary, resource_kind: String)
signal corpse_loot_requested(record: Dictionary)
const HandInput=preload("res://scripts/tracked_hand_input.gd")
const FONT=preload("res://resources/fonts/Jupiteroid-Regular.ttf")
const MAX_CHOICES:=8
const BLOCK_MESSAGES := {
	"insufficient_inventory_capacity":"Make room in your inventory before collecting this.",
	"personal_loot_owner_required_group_loot_unsupported":"Only the personal loot owner can collect this. Group loot is not supported yet.",
	"native_harvest_rights_skill_or_already_harvested":"You cannot harvest this corpse: check harvesting rights, skill, or whether you already harvested it.",
	"source_command_state_restriction":"Your current state or movement prevents this action.",
	"not_dead":"This creature is not dead.",
	"not_dead_or_player_unavailable":"The creature must be dead and your character must be alive to loot it.",
	"dna_harvested":"This corpse has already been harvested for DNA.",
	"beyond_native_7m_harvest_range":"Move within 7 m of the corpse to harvest it.",
	"beyond_native_16m_loot_range":"Move within 16 m of the corpse to loot it.",
	"corpse_empty":"This corpse has no credits or items left to loot.",
	"missing_inventory":"The required inventory is unavailable.",
	"native_inventory_restriction":"Your inventory cannot accept one of these items.",
	"native_transfer_permission":"You do not have permission to transfer these items.",
	"no_current_resource_spawn":"This resource is currently unavailable on the planet.",
	"no_organic_resources":"This corpse has no harvestable organic resources.",
	"unsupported_source_yield":"This harvest amount is not supported yet."
}
var corpse_provider: Callable
var empty_hand_provider: Callable
var rig: XROrigin3D
var body: CharacterBody3D
var assets: RefCounted
var dominant:="right"
var allowed:=false
var pending:=false
var trigger_armed:=false
var grip_armed:=false
var corpse: Dictionary={}
var context: Dictionary={}
var choices: Array=[]
var title: Label3D
var message: Label3D
var choice_nodes: Array[Node3D]=[]
var hovered: Dictionary={}
var interaction_active:=false

func configure(origin: XROrigin3D,player: CharacterBody3D,source_assets: RefCounted,side:="right") -> void:
	rig=origin;body=player;assets=source_assets;dominant="left" if side=="left" else "right";process_priority=122
	title=make_label(28);add_child(title);title.position=Vector3(0,0.15,0)
	message=make_label(22);add_child(message);message.position=Vector3(0,-0.12,0);message.width=900
	visible=false

func make_label(font_size: int)->Label3D:
	var label:=Label3D.new();label.font=FONT;label.font_size=font_size;label.pixel_size=0.00085;label.outline_size=4;label.modulate=Color("c9fbff");label.billboard=BaseMaterial3D.BILLBOARD_ENABLED;label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;label.width=700;label.render_priority=5
	return label

func set_allowed(value: bool)->void:
	allowed=value
	if not value:close()

func above_body(record: Dictionary,position: Vector3)->bool:
	if not record.get("dead",false) or not record.get("bounds") is AABB or str(record.get("id","")).is_empty():return false
	var bounds:AABB=record.bounds
	return position.x>=bounds.position.x-0.10 and position.x<=bounds.end.x+0.10 and position.z>=bounds.position.z-0.10 and position.z<=bounds.end.z+0.10 and position.y>=bounds.end.y-0.04 and position.y<=bounds.end.y+0.38

func candidate(position: Vector3)->Dictionary:
	if not corpse_provider.is_valid():return {}
	var value:Variant=corpse_provider.call(position)
	return value if value is Dictionary and above_body(value,position) else {}

func sample(tracked:bool,empty:bool,hand:Transform3D,head:Transform3D,trigger:float,grip:float)->void:
	if not allowed or not tracked or not empty:
		close();return
	hovered=candidate(hand.origin)
	interaction_active=not hovered.is_empty() or (visible and choice_at(hand.origin)>=0)
	if trigger<0.35:trigger_armed=true
	if grip<0.35:grip_armed=true
	if pending:
		if trigger>=0.55:trigger_armed=false
		if grip>=0.65:grip_armed=false
		return
	var selected:=choice_at(hand.origin) if visible else -1
	if grip>=0.65 and grip_armed:
		grip_armed=false
		if selected>=0:
			var choice:Dictionary=choices[selected]
			if not bool(choice.get("available",false)):
				set_busy(false,str(choice.get("block_reason","This resource cannot be harvested.")));return
			set_busy(true,"Harvesting resource in CoreCU…")
			corpse_harvest_requested.emit(corpse.duplicate(true),str(choice.get("kind","")));return
	if trigger>=0.55 and trigger_armed:
		trigger_armed=false
		if hovered.is_empty():return
		if visible and str(corpse.get("id",""))==str(hovered.id) and not context.is_empty():
			if context.has("loot_available") and not bool(context.loot_available):set_busy(false,str(context.get("loot_block_reason","This corpse cannot be looted.")));return
			set_busy(true,"Looting credits and items in CoreCU…");corpse_loot_requested.emit(corpse.duplicate(true))
		else:
			corpse=hovered.duplicate(true);context={};clear_choices();visible=true
			place_above(corpse,head);title.text=str(corpse.get("name","Corpse"));set_busy(true,"Inspecting corpse…")
			corpse_inspect_requested.emit(corpse.duplicate(true))

func place_above(record:Dictionary,head:Transform3D)->void:
	var bounds:AABB=record.bounds
	var origin:=Vector3(bounds.get_center().x,bounds.end.y+0.22,bounds.get_center().z)
	var forward:Vector3=(origin-head.origin).slide(Vector3.UP).normalized()
	if forward.length_squared()<0.5:forward=Vector3.FORWARD
	global_transform=Transform3D(Basis.looking_at(forward,Vector3.UP),origin)

func clear_choices()->void:
	for node in choice_nodes:
		if is_instance_valid(node):remove_child(node);node.queue_free()
	choice_nodes.clear();choices=[]

func set_corpse_context(record:Dictionary,value:Dictionary)->void:
	if str(record.get("id",""))!=str(corpse.get("id","")):return
	context=value.duplicate(true);clear_choices()
	var source:Variant=context.get("choices",context.get("resources",[]))
	if source is Array:choices=source.slice(0,MAX_CHOICES).duplicate(true)
	for index in range(choices.size()):
		var choice:Dictionary=choices[index]
		var node:=Node3D.new();add_child(node);choice_nodes.append(node)
		node.position=Vector3((index-(choices.size()-1)*0.5)*0.16,0,0)
		var template:=str(choice.get("container_template",""))
		var mesh:MeshInstance3D=assets.instance(template,0.095) if not template.is_empty() else null
		if mesh!=null:
			node.add_child(mesh)
			for surface in range(mesh.mesh.get_surface_count()):
				var original:Material=mesh.get_active_material(surface)
				var material:=ShaderMaterial.new();material.shader=preload("res://shaders/equipment_hologram.gdshader")
				var texture:Texture2D=original.albedo_texture if original is StandardMaterial3D else null
				if original is ShaderMaterial:
					texture=original.get_shader_parameter("main_texture")
					if texture==null:texture=original.get_shader_parameter("albedo_texture")
				if texture!=null:material.set_shader_parameter("source_texture",texture);material.set_shader_parameter("has_texture",true)
				mesh.set_surface_override_material(surface,material)
		var label:=make_label(20);node.add_child(label);label.position.y=-0.07;label.width=175
		var kind:=str(choice.get("kind","Resource")).capitalize()
		var resource_name:=str(choice.get("name",kind))
		label.text=kind
		if not resource_name.is_empty() and resource_name.to_lower()!=kind.to_lower():label.text+="\n"+resource_name
		if choice.has("quantity"):label.text+=" ×%d"%int(choice.quantity)
		if mesh==null:label.text+="\nOriginal icon unavailable"
		if not bool(choice.get("available",false)):label.modulate=Color("d6a789")
	var loot:Dictionary=context.get("loot",{})
	title.text=str(corpse.get("name","Corpse"))+" · %d credits / %d items"%[int(loot.get("credits",0)),int(loot.get("item_count",0))]
	set_busy(false,"Grip a resource to harvest · fresh trigger over corpse loots credits/items" if not choices.is_empty() else "No harvestable resources · fresh trigger over corpse loots credits/items")

func choice_at(position:Vector3)->int:
	var nearest:=0.085;var selected:=-1
	for index in range(choice_nodes.size()):
		var distance:=choice_nodes[index].global_position.distance_to(position)
		if distance<nearest:nearest=distance;selected=index
	return selected

func set_busy(value:bool,text:="")->void:
	if pending and not value:
		trigger_armed=false;grip_armed=false
	pending=value
	if is_instance_valid(message) and not text.is_empty():message.text=str(BLOCK_MESSAGES.get(text,text))

func close()->void:
	visible=false;pending=false;trigger_armed=false;grip_armed=false;hovered={};corpse={};context={};interaction_active=false
	clear_choices()

func blocks_combat()->bool:
	if not allowed or not is_instance_valid(rig) or not empty_hand_provider.is_valid() or not bool(empty_hand_provider.call()):return false
	var hand:XRController3D=rig.get_node("LeftHand" if dominant=="left" else "RightHand")
	if not HandInput.controller_tracked(hand):return false
	return not candidate(hand.global_position).is_empty() or (visible and choice_at(hand.global_position)>=0)

func _process(_delta:float)->void:
	if not is_instance_valid(rig):return
	var hand:XRController3D=rig.get_node("LeftHand" if dominant=="left" else "RightHand")
	var tracker=XRServer.get_tracker("head");var pose:XRPose=tracker.get_pose("default") if tracker!=null else null
	var tracked:bool=pose!=null and pose.has_tracking_data and HandInput.controller_tracked(hand)
	var empty:bool=empty_hand_provider.is_valid() and bool(empty_hand_provider.call())
	var camera:Camera3D=rig.get_node("XRCamera3D")
	sample(tracked,empty,hand.global_transform,camera.global_transform,hand.get_float("trigger") if tracked else 0,hand.get_float("grip") if tracked else 0)
	if visible and camera.global_position.distance_to(global_position)>2.8:close()
