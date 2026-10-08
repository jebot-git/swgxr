extends PanelContainer
## Owner-only statistics and a frozen copy of the actual character appearance.
signal equipment_requested
const Hologram=preload("res://scripts/equipment_hologram.gd")
const Style=preload("res://scripts/datapad_theme.gd")
var scroll:ScrollContainer
var fields:RichTextLabel
var bust:TextureButton
var portrait:SubViewport
var clone:Node3D
var appearance_key:=""
var summary:Dictionary={}

func _ready()->void:
	theme=Style.build();add_theme_stylebox_override("panel",Style.frame(24,"tall"))
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var column:=VBoxContainer.new();add_child(column)
	var title:=Label.new();title.text="CHARACTER";title.add_theme_font_size_override("font_size",24);column.add_child(title)
	bust=TextureButton.new();bust.custom_minimum_size=Vector2(0,165);bust.ignore_texture_size=true;bust.stretch_mode=TextureButton.STRETCH_KEEP_ASPECT_CENTERED;bust.disabled=true;bust.tooltip_text="Open equipment hologram";column.add_child(bust)
	bust.pressed.connect(func():equipment_requested.emit())
	var hint:=Label.new();hint.text="Touch your hologram to manage equipment";hint.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;hint.add_theme_font_size_override("font_size",16);column.add_child(hint)
	scroll=ScrollContainer.new();scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;column.add_child(scroll)
	fields=RichTextLabel.new();fields.bbcode_enabled=true;fields.fit_content=true;fields.scroll_active=false;fields.size_flags_horizontal=Control.SIZE_EXPAND_FILL;fields.add_theme_font_size_override("normal_font_size",18);scroll.add_child(fields)
	portrait=SubViewport.new();portrait.size=Vector2i(440,260);portrait.transparent_bg=true;portrait.own_world_3d=true;portrait.gui_disable_input=true;portrait.render_target_update_mode=SubViewport.UPDATE_DISABLED;add_child(portrait)
	bust.texture_normal=portrait.get_texture()
	set_summary(summary)

func set_character(source:Node3D,key:String)->void:
	if key==appearance_key and is_instance_valid(clone):return
	appearance_key=key
	if is_instance_valid(clone):portrait.remove_child(clone);clone.queue_free()
	clone=null;bust.disabled=true;bust.tooltip_text="Character appearance unavailable"
	if not is_instance_valid(source):return
	clone=Hologram.new();portrait.add_child(clone);clone.configure(source,[])
	if not str(clone.report.get("error","")).is_empty():return
	for panel:Node3D in clone.panels:panel.hide()
	clone.show()
	var camera:=Camera3D.new();clone.add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=.28;camera.position=Vector3(0,.43,1);camera.current=true
	# The near/far crop is photographic only; the source tracked skeleton remains untouched.
	bust.disabled=false;bust.tooltip_text="Open equipment hologram";portrait.render_target_update_mode=SubViewport.UPDATE_ONCE

func set_summary(value:Dictionary)->void:
	summary=value.duplicate(true)
	if not is_instance_valid(fields):return
	fields.text="Awaiting character statistics" if summary.is_empty() else format_summary(summary)

static func location_text(value:Variant)->String:
	if not value is Dictionary or value.is_empty():return "Unavailable"
	if value.get("status","")=="unset":return "Not set"
	if value.get("status","")=="unavailable":return "Location unavailable"
	var point:Variant=value.get("position",[])
	var result:=str(value.get("name",value.get("zone","")))
	if value.has("zone") and str(value.zone)!=result:result+=" · "+str(value.zone).capitalize()
	if point is Array and point.size()==3:result+="\nX %.0f  Z %.0f"%[float(point[0]),float(point[2])]
	return result if not result.is_empty() else "Location unavailable"

static func format_summary(value:Dictionary)->String:
	var lines:=PackedStringArray([str(value.get("name","Character"))])
	var names:=["Health","Action","Mind"]
	for i in range(3):
		var pool:Array=value.get("ham",[]);var maxima:Array=value.get("max_ham",[]);var wounds:Array=value.get("wounds",[])
		lines.append("\n%s  %s / %s\nWounds  %s"%[names[i],str(pool[i]) if pool.size()>i else "—",str(maxima[i]) if maxima.size()>i else "—",str(wounds[i]) if wounds.size()>i else "—"])
	lines.append("Battle fatigue  %s"%str(value.get("shock_wounds","—")))
	var credits:Dictionary=value.get("wallet",{})
	lines.append("\nCREDITS\nCash  %s\nBank  %s"%[str(credits.get("cash","—")),str(credits.get("bank","—"))])
	lines.append("\nARMOUR · EQUIPPED PIECES")
	var armour:Dictionary=value.get("armour",{})
	var pieces:Array=armour.get("pieces",[])
	if pieces.is_empty():lines.append("No armour equipped" if value.has("armour") else "Armour data unavailable")
	for piece:Dictionary in pieces:
		lines.append("\n"+str(piece.get("name","Armour"))+" · rating "+str(piece.get("rating","—")))
		lines.append(", ".join(PackedStringArray(piece.get("slots",[]))).replace("_"," "))
		if piece.get("broken",false):lines.append("Broken")
		if piece.get("shield",false):lines.append("Personal shield")
		var protection:Dictionary=piece.get("protection_percent",{})
		for key:String in protection:lines.append(key.capitalize()+"  "+str(protection[key])+"%")
		for key:String in piece.get("protection_score",{}):lines.append(key.capitalize()+" protection score  "+str(piece.protection_score[key]))
	for key in ["movement_scale","output_scale","recovery_scale"]:
		if armour.has(key):lines.append(({"movement_scale":"Movement","output_scale":"Damage","recovery_scale":"Recovery"}[key])+"  × %.2f"%float(armour[key]))
	var faction:Dictionary=value.get("faction",{});var standings:Dictionary=faction.get("standings",{})
	lines.append("\nFACTION\n%s · %s\nRank  %s\nImperial  %s\nRebel  %s"%[str(faction.get("allegiance","—")).capitalize(),str(faction.get("status_name","—")).replace("_"," ").capitalize(),str(faction.get("rank","—")),str(standings.get("imperial","—")),str(standings.get("rebel","—"))])
	var homes:Dictionary=value.get("homepoints",{})
	lines.append("\nRESIDENCE\n"+location_text(homes.get("residence",{})))
	lines.append("\nBOUND CLONING LOCATION\n"+location_text(homes.get("cloning",{})))
	return "\n".join(lines).replace("[","[lb]")
