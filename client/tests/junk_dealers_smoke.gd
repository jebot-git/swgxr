extends SceneTree
func _initialize()->void:call_deferred("run")
func run()->void:
	var panel:=preload("res://scripts/service_panel.gd").new();root.add_child(panel)
	var row:Dictionary=JSON.parse_string('{"name":"Sell damaged datapad · 100 credits","items":[{"item_id":"18446744073709551614","price":100}]}')
	panel.configure({"id":"456","kind":"junk_dealer","dialogue":"Offer loot","options":[row]},{"cash":0,"bank":0})
	var calls:Array=[];panel.action_requested.connect(func(action,payload):calls.append([action,payload]))
	panel.selected=0;panel.confirm()
	if not calls.is_empty():FileAccess.open("res://../runtime/evidence/junk-sale-wire.json",FileAccess.WRITE).store_string(JSON.stringify(calls[0][1]))
	var passed:bool=calls.size()==1 and calls[0][0]=="junk_sell" and calls[0][1].items.size()==1 and calls[0][1].items[0].item_id==row.items[0].item_id and calls[0][1].items[0].price==100 and typeof(calls[0][1].items[0].price)==TYPE_INT and panel.delivery_dialogue.visible and preload("res://scripts/npc_wave_gesture.gd").is_npc({"kind":"junk_dealer"})
	print(JSON.stringify({"passed":passed,"checks":"Dealer quote submission, dialogue visibility and omnidirectional NPC interaction classification","live_xr":false}))
	panel.queue_free();await process_frame;quit(0 if passed else 1)
