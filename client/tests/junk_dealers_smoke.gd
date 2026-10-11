extends SceneTree
func _initialize()->void:call_deferred("run")
func run()->void:
	var panel:=preload("res://scripts/service_panel.gd").new();root.add_child(panel)
	var row:={"name":"Sell damaged datapad · 100 credits","items":[{"item_id":"123","price":100}]}
	panel.configure({"id":"456","kind":"junk_dealer","dialogue":"Offer loot","options":[row]},{"cash":0,"bank":0})
	var calls:Array=[];panel.action_requested.connect(func(action,payload):calls.append([action,payload]))
	panel.selected=0;panel.confirm()
	var passed:bool=calls.size()==1 and calls[0][0]=="junk_sell" and calls[0][1].items==row.items and panel.delivery_dialogue.visible and preload("res://scripts/npc_wave_gesture.gd").is_npc({"kind":"junk_dealer"})
	print(JSON.stringify({"passed":passed,"checks":"Dealer quote submission, dialogue visibility and omnidirectional NPC interaction classification","live_xr":false}))
	panel.queue_free();await process_frame;quit(0 if passed else 1)
