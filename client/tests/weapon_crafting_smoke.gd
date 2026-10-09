extends SceneTree
const State = preload("res://combat/weapon_state.gd")
var checks := 0
var errors: Array[String] = []
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: errors.append(message); push_error(message)
func run() -> void:
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/assets/combat/catalog.json"))
	var data: Dictionary = catalog.weapons.pistol_cdef.duplicate(true)
	data.merge({"source_kind":"core3_weapon_instance","item_id":"1001","certified":true,"profile_version":1},true)
	var state := State.new()
	check(state.configure(data,data.core3.certificationsRequired),"Instance configuration")
	state.tick(0.1,0,true,false)
	check(not state.tick(0.1,1,true,false).is_empty(),"Initial shot")
	var remaining := state.rounds
	var cooldown := state.next_shot-state.clock
	var update: Dictionary = data.duplicate(true)
	update.rpm=262.5; update.capacity=14
	check(state.refresh_instance(update),"Refresh same item")
	check(state.rounds==remaining,"Increased capacity refilled ammunition")
	check(is_equal_approx(state.next_shot-state.clock,cooldown*240.0/262.5),"Cooldown fraction lost")
	check(state.tick(0,1,true,false).is_empty(),"Refresh rearmed held trigger")
	check(State.crafting_preview(update,data).contains("+22.5 RPM · +2 shots"),"Preview change")
	update.capacity=4
	check(state.refresh_instance(update) and state.rounds==4,"Capacity decrease clamp")
	state.rounds=0; state.reload()
	var reload_deadline := state.reload_until
	update.capacity=20
	check(state.refresh_instance(update) and state.rounds==0 and state.reload_until==reload_deadline,"Refresh reset reload or refilled")
	state.tick(2,0,true,false)
	check(state.rounds==20,"Completed reload did not use new capacity")
	update.item_id="other"
	check(not state.refresh_instance(update),"Cross-item refresh accepted")
	update.item_id="1001"; update.rpm=NAN
	check(not state.refresh_instance(update),"Non-finite RPM accepted")
	update.rpm=240; update.certified=false
	check(state.refresh_instance(update) and not state.certified(),"Lost certification ignored")
	var path := "res://../runtime/evidence/crafting-live-snapshot.json"
	if FileAccess.file_exists(path):
		var snapshot: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		for item in snapshot.get("weapons",[]):
			var live := State.new()
			check(live.configure(item,item.core3.certificationsRequired if item.certified else [],item.condition),"Real Core3 item rejected")
			if live.is_melee():
				check(live.profile.power==item.power and live.profile.stance_recovery==item.stance_recovery and live.rounds==0,"Server melee stats replaced by defaults")
			else:
				check(live.profile.rpm==item.rpm and live.rounds==item.capacity,"Server stats replaced by class defaults")
	var report := {"test":"weapon_crafting_client","checks":checks,"passed":errors.is_empty(),"errors":errors,"hardware_tested":false}
	FileAccess.open("res://../runtime/evidence/weapon-crafting-client.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print(JSON.stringify(report))
	quit(0 if errors.is_empty() else 1)
