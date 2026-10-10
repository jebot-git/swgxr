extends VBoxContainer
signal changed
var preferences:RefCounted
var choice=preload("res://scripts/frontend_choice.gd").new()
var notice:=Label.new()
func setup(value:RefCounted)->void:
	preferences=value
	var label:=Label.new();label.text="Multisample anti-aliasing (MSAA)";add_child(label)
	choice.name="MSAA";choice.custom_minimum_size.y=44
	for option:String in ["Off","2×","4×","8×"]:choice.add_item(option)
	choice.select(preferences.msaa);add_child(choice)
	choice.item_selected.connect(func(index:int):
		preferences.set_msaa(index)
		notice.text="Applied and saved." if preferences.save_preferences()==OK else "Applied for this session; could not save the preference."
		changed.emit())
	var help:=Label.new();help.text="Smooths object edges in headset and desktop views. Higher levels use more GPU power. Changes apply immediately.";help.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;add_child(help)
	notice.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;add_child(notice)
