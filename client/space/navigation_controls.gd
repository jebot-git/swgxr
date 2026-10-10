extends VBoxContainer
signal jump_requested(destination: String)
signal abort_requested
var destinations = preload("res://scripts/frontend_choice.gd").new()
var jump := Button.new()
var cancel := Button.new()
var info := Label.new()
var loaded := false
func _ready() -> void:
	var row:=HBoxContainer.new();add_child(row)
	destinations.size_flags_horizontal=Control.SIZE_EXPAND_FILL;destinations.custom_minimum_size.y=42;row.add_child(destinations)
	jump.text="Jump";row.add_child(jump);jump.pressed.connect(func():jump_requested.emit(str(destinations.get_selected_metadata())))
	cancel.text="Abort jump";row.add_child(cancel);cancel.pressed.connect(func():abort_requested.emit())
	info.add_theme_font_size_override("font_size",14);info.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;add_child(info)
func configure(catalog: Dictionary, ship: Dictionary) -> void:
	if not loaded:
		for sector:Dictionary in catalog.get("sectors",{}).values():
			for destination:Dictionary in sector.get("navigation",[]):
				destinations.add_item(str(sector.name)+" · "+str(destination.name))
				destinations.set_item_metadata(destinations.item_count-1,str(destination.id))
		loaded=true
	var pilot:bool=ship.get("station","")=="pilot"
	var active:bool=ship.get("hyperspacing",false)
	jump.disabled=not pilot or active or destinations.item_count==0 or int(ship.get("hyperspace_delay",0))>0
	cancel.visible=active;cancel.disabled=not pilot
	destinations.disabled=active
	info.text="Hyperspace sequence in progress…" if active else "Select an original jump point. The pilot confirms travel." if not pilot else "Select a destination and press Jump. Native hyperdrive requirements apply."
