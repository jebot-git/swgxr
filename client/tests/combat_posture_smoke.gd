extends SceneTree
const State = preload("res://combat/weapon_state.gd")
const Posture = preload("res://combat/firing_posture.gd")
var checks := 0
var errors: Array[String] = []
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: errors.append(message); push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://../runtime/combat/catalog.json")))
	for id in ["pistol_cdef","rifle_e11"]:
		for support in [false,true]:
			var expected_scale: float = (1.1 if support else 1.0) if id=="pistol_cdef" else (1.0 if support else 0.3)
			var damages := []
			for stance in ["standing","crouched","prone"]:
				var state := State.new()
				var profile: Dictionary = catalog.weapons[id].duplicate(true)
				# Explicit curve covers both beneficial and harmful ranges independently
				# of balance changes to individual original templates.
				profile.core3.pointBlankAccuracy = -20
				profile.core3.idealAccuracy = 25
				profile.core3.maxRangeAccuracy = -60
				state.configure(profile,profile.core3.certificationsRequired)
				state.tick(0,0,true,support,stance)
				var shot := state.tick(0.01,1,true,support,stance)
				check(shot.firing_posture==stance and is_equal_approx(shot.range_scale,expected_scale),"Shot keeps posture and independent grip multiplier: %s/%s/%s" % [id,support,stance])
				var far := State.damage_at(shot,shot.range,{},0,0.5,1)
				var penalty: float = {"standing":-60.0,"crouched":-30.0,"prone":0.0}[stance]
				check(is_equal_approx(far.range_modifier,penalty),"Far penalty matches stance: "+stance)
				check(is_equal_approx(State.damage_at(shot,float(profile.core3.idealRange)*expected_scale,{},0,0.5,1).range_modifier,25),"Posture keeps positive range bonus: "+stance)
				check(State.damage_at(shot,shot.range+0.01,{},0,0.5,1).damage==0,"Prone/crouch never bypasses grip-scaled projectile range")
				state.tick(1,0,true,not support,"standing")
				check(is_equal_approx(State.damage_at(shot,shot.range,{},0,0.5,1).damage,far.damage),"Changing posture/grip after firing leaves shot unchanged")
				damages.append(far.damage)
			check(is_equal_approx(damages[1]/damages[0],1.75) and is_equal_approx(damages[2]/damages[0],2.5),"Posture affects final damage, after independent hand multiplier")
	var detector := Posture.new()
	check(detector.update_tracked({"tracked":true,"grounded":true,"eye_height":1.7})=="standing","Upright standing")
	for sample in [[1.2,"crouched"],[1.4,"crouched"],[1.6,"standing"],[0.5,"prone"],[0.75,"prone"],[0.9,"crouched"],[1.7,"standing"]]:
		check(detector.update_tracked({"tracked":true,"grounded":true,"eye_height":sample[0]})==sample[1],"Physical height and hysteresis: "+str(sample))
	for context in [{"tracked":false,"grounded":true,"eye_height":0.5},{"tracked":true,"grounded":false,"eye_height":0.5},{"tracked":true,"grounded":true,"eye_height":NAN},{"tracked":true,"grounded":true,"eye_height":-1}]:
		check(detector.update_tracked(context)=="standing","Invalid or airborne tracking has no posture advantage")
	check(not detector.set_standing_eye_height(NAN) and not detector.set_standing_eye_height(0.3) and detector.set_standing_eye_height(2.0),"Calibration validates height")
	check(detector.update_tracked({"tracked":true,"grounded":true,"eye_height":0.7})=="prone","Calibrated height controls physical posture thresholds")
	for i in range(4):
		check(detector.update_desktop(i,true)==["standing","crouched","prone","standing"][i],"Desktop posture enum "+str(i))
		check(detector.update_desktop(i,false)=="standing","Airborne desktop posture gives no benefit")
	var report := {"test":"combat_posture","passed":errors.is_empty(),"checks":checks,"errors":errors,"hardware_tested":false}
	FileAccess.open(ProjectSettings.globalize_path("res://../runtime/evidence/combat-posture-smoke.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print(JSON.stringify(report)); quit(0 if errors.is_empty() else 1)
