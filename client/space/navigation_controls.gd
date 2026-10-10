extends VBoxContainer
signal jump_requested(destination: String)
signal abort_requested
var destinations = preload("res://scripts/frontend_choice.gd").new()
var jump := Button.new()
var cancel := Button.new()
var info := Label.new()
var loaded := false
var destination_rows:Dictionary={}
var current_ship:Dictionary={}
func _ready() -> void:
	var row:=HBoxContainer.new();add_child(row)
	destinations.size_flags_horizontal=Control.SIZE_EXPAND_FILL;destinations.custom_minimum_size.y=42;row.add_child(destinations)
	jump.text="Jump";row.add_child(jump);jump.pressed.connect(func():jump_requested.emit(str(destinations.get_selected_metadata())))
	cancel.text="Abort jump";row.add_child(cancel);cancel.pressed.connect(func():abort_requested.emit())
	destinations.item_selected.connect(func(_index):update_description())
	info.add_theme_font_size_override("font_size",14);info.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;add_child(info)
func configure(catalog: Dictionary, ship: Dictionary) -> void:
	current_ship=ship
	if not loaded:
		for sector:Dictionary in catalog.get("sectors",{}).values():
			for destination:Dictionary in sector.get("navigation",[]):
				destinations.add_item(str(destination.name))
				destination_rows[str(destination.id)]=destination
				destinations.set_item_metadata(destinations.item_count-1,str(destination.id))
		loaded=true
	var pilot:bool=ship.get("station","")=="pilot"
	var active:bool=ship.get("hyperspacing",false)
	jump.disabled=not pilot or active or destinations.item_count==0 or int(ship.get("hyperspace_delay",0))>0
	cancel.visible=active;cancel.disabled=not pilot
	destinations.disabled=active
	update_description()
func update_description()->void:
	var destination:Dictionary=destination_rows.get(str(destinations.get_selected_metadata()),{})
	var description:=str(destination.get("description",""))
	var summary:PackedStringArray=[]
	for line in description.split("\n"):
		if line.begins_with("Distance to"):summary.append(line)
	info.text="Hyperspace sequence in progress…" if current_ship.get("hyperspacing",false) else str(destination.get("name","Select an original jump point"))+"\n"+("Shared Corellia/Talus sector; choose the intended station to land.\n" if destination.get("zone","")=="space_corellia" else "")+"\n".join(summary)
	info.tooltip_text=description
