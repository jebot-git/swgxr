extends SceneTree
func _initialize()->void:call_deferred("run")
func run()->void:
	var view:=SubViewport.new();root.add_child(view);view.size=Vector2i(1440,1240);view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	var bg:=ColorRect.new();view.add_child(bg);bg.color=Color("07151f");bg.size=Vector2(1440,1240)
	var panel=preload("res://mail/panel.gd").new();view.add_child(panel);panel.position=Vector2(20,20);panel.size=Vector2(1400,790)
	panel.compose();panel.recipient.text="Aria";panel.subject.text="Meet at Mos Eisley";panel.body.text="The survey report has arrived.\n\nMeet at the starport after checking the new resource deposits.";panel.status.text="UI preview · local fixture"
	var keyboard=preload("res://ui/virtual_keyboard.gd").new();view.add_child(keyboard);keyboard.position=Vector2(120,830);keyboard.target_viewport=view
	await process_frame;await process_frame;await process_frame
	view.get_texture().get_image().save_png("res://../runtime/evidence/mail-keyboard-preview.png")
	quit()
