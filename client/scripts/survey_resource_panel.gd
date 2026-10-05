extends Control
## Selected Core3 resource metadata; original container appearance is supplied by inventory.
const ThemeSource=preload("res://scripts/datapad_theme.gd")
const PIXELS:=Vector2i(480,680)
var resource: Dictionary={}
var heading: Label
var family: Label
var statistics: RichTextLabel
var unavailable: Label
func configure() -> void:
	theme=ThemeSource.build();size=Vector2(PIXELS);custom_minimum_size=size
	var panel:=Panel.new();panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(panel)
	panel.add_theme_stylebox_override("panel",ThemeSource.box("071c29","3ea8b9",2,14))
	heading=Label.new();add_child(heading);heading.position=Vector2(20,14);heading.size=Vector2(440,54);heading.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;heading.add_theme_font_size_override("font_size",25)
	family=Label.new();add_child(family);family.position=Vector2(20,74);family.size=Vector2(440,50);family.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;family.add_theme_font_size_override("font_size",18)
	unavailable=Label.new();add_child(unavailable);unavailable.position=Vector2(20,175);unavailable.size=Vector2(440,50);unavailable.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;unavailable.text="Original resource preview unavailable";unavailable.add_theme_font_size_override("font_size",17)
	statistics=RichTextLabel.new();add_child(statistics);statistics.position=Vector2(20,324);statistics.size=Vector2(440,335);statistics.add_theme_font_size_override("normal_font_size",20);statistics.bbcode_enabled=false
	set_resource({})
func set_resource(value: Dictionary) -> void:
	resource=value.duplicate(true)
	heading.text=str(resource.get("name","RESOURCE INFORMATION"))
	family.text=str(resource.get("type_label",resource.get("type",resource.get("family_label",resource.get("family","Select a resource to inspect.")))))
	var lines:=PackedStringArray()
	for attribute: Variant in resource.get("attributes",[]).slice(0,32):
		if not attribute is Dictionary: continue
		var label:=str(attribute.get("label",attribute.get("name","")))
		if not attribute.has("label"):label=label.get_slice(":",label.get_slice_count(":")-1).replace("_"," ").capitalize()
		lines.append(label+": "+str(attribute.get("value","")))
	statistics.text="\n".join(lines) if not lines.is_empty() else "No resource attributes returned by Core3."
func scroll(stick: Vector2, delta: float) -> void:
	statistics.get_v_scroll_bar().value-=stick.y*delta*500
