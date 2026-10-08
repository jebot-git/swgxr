extends SceneTree
var checks: Array=[]
var errors: Array=[]
func check(value: bool, label: String) -> void:
	if not value:errors.append(label);push_error(label)
	checks.append(label)
func _initialize() -> void:call_deferred("run")
func run() -> void:
	for file in ["res://medic/controller.gd","res://medic/range_circle.gd","res://scripts/main.gd"]:
		var script=load(file);check(script!=null and script.can_instantiate(),"Script loads: "+file)
	var targeting=preload("res://medic/targeting.gd")
	var ability={"id":"tenddamage","range_m":7}
	var candidates=[{"id":"full","position":Vector3(0,0,-1),"eligible":false,"bounds":[AABB(Vector3(-0.3,-0.3,-1.2),Vector3(0.6,0.6,0.4))]},{"id":"near","position":Vector3(0,0,-3),"eligible":true,"bounds":[AABB(Vector3(-0.3,-0.3,-3.2),Vector3(0.6,0.6,0.4))]},{"id":"far","position":Vector3(0,0,-5),"eligible":true,"bounds":[AABB(Vector3(-0.3,-0.3,-5.2),Vector3(0.6,0.6,0.4))]}]
	check(targeting.first(Transform3D.IDENTITY,Vector3.ZERO,ability,candidates).id=="near","First eligible recipient ignores full-health actor")
	check(targeting.first(Transform3D.IDENTITY,Vector3.ZERO,ability,candidates,2).is_empty(),"World obstruction blocks healing reticle")
	check(targeting.first(Transform3D.IDENTITY,Vector3.ZERO,{"range_m":2},candidates).is_empty(),"Native healing range filters recipient")
	check(targeting.first(Transform3D(Basis(Vector3.UP,PI),Vector3.ZERO),Vector3.ZERO,ability,candidates).is_empty(),"No self-heal fallback when reticle misses")
	var items=preload("res://medic/item_targeting.gd")
	var patient={"healable":true,"dead":false,"needs":{"healdamage":true},"states":8388608,"wounds":[50,0,0,0,0,0,0,0,0]}
	check(items.eligible({"medical_command":"healdamage"},patient),"Held stim selects injured patient")
	check(items.eligible({"medical_command":"curepoison","medical_state":8388608},patient),"Antidote requires matching native state")
	check(not items.eligible({"medical_command":"curedisease","medical_state":33554432},patient),"Wrong antidote is not consumed")
	check(items.eligible({"medical_command":"healwound","wound_attribute":0},patient),"Health wound supply matches patient")
	check(not items.eligible({"medical_command":"reviveplayer"},patient),"Resuscitation rejects living patient")
	patient.dead=true
	check(items.eligible({"medical_command":"reviveplayer"},patient),"Resuscitation can select dead patient")
	check(not items.eligible({"medical_command":"healdamage"},patient),"Stim does not select dead patient")
	patient.healable=false
	check(not items.eligible({"medical_command":"reviveplayer"},patient),"Hostile recipient excluded")
	var pet={"healable":true,"companion":true,"droid":false,"dead":false,"needs":{"healdamage":true},"wounds":[50,0,0,0,0,0,0,0,0]}
	check(items.eligible({"medical_command":"healpet"},pet),"Pet stim selects an injured creature companion")
	check(not items.eligible({"medical_command":"healpet"},{"healable":true,"needs":{"healdamage":true}}),"Pet stim cannot target a player")
	check(not items.eligible({"medical_command":"healdroiddamage"},pet),"Repair kit cannot target an organic pet")
	pet.droid=true
	check(items.eligible({"medical_command":"healdroiddamage"},pet),"Repair kit selects an injured droid")
	check(items.eligible({"medical_command":"healdroidwound"},pet),"Reconstruction kit selects Health wounds")
	check(not items.eligible({"medical_command":"healdamage"},pet),"Organic stim cannot target a droid")
	pet.dead=true
	check(not items.eligible({"medical_command":"reviveplayer"},pet),"Player resuscitation cannot resurrect a companion")

	var effect=preload("res://combat/vital_feedback.gd").new()
	effect.observe({"damage":1,"heal":2,"age_seconds":0})
	check(effect.strength("damage")==0 and effect.strength("heal")==0,"Initial snapshot does not replay old feedback")
	effect.observe({"damage":3,"heal":2,"age_seconds":0});effect.advance(0.07)
	check(effect.strength("damage")>0 and effect.strength("heal")==0,"Only damaged recipient sees damage pulse")
	var previous: float=effect.elapsed.damage;effect.observe({"damage":3,"heal":2,"age_seconds":0})
	check(effect.elapsed.damage==previous,"Duplicate snapshots cannot replay effects")
	effect.observe({"damage":3,"heal":4,"age_seconds":0});effect.advance(0.07)
	check(effect.strength("heal")>0,"Native healing produces independent subtle pulse")
	for i in range(20):effect.advance(0.1)
	check(effect.strength("damage")==0 and effect.strength("heal")==0,"Both effects decay fully")
	var controller=preload("res://medic/controller.gd").new();root.add_child(controller)
	controller.selected="tenddamage";controller.stow()
	check(controller.selected=="tenddamage","Stowing preserves independent medical selection")
	controller.queue_free()
	check(SwgMedicDrag.crossed(Transform3D.IDENTITY,Vector3(.18,-.3,-.2),Vector3(-.18,-.3,-.2),true),"Crossed arms detected in head-local chest volume")
	check(not SwgMedicDrag.crossed(Transform3D.IDENTITY,Vector3(.18,-.3,-.2),Vector3(-.18,-.3,-.2),false),"Lost hand tracking cannot generate a gesture")
	var boxes=[AABB(Vector3(-.5,-.5,-.5),Vector3.ONE)]
	check(SwgMedicDrag.both_touch(boxes,Vector3(-.2,0,0),Vector3(.2,0,0)),"Two hands on different avatar points permit drag")
	check(not SwgMedicDrag.both_touch(boxes,Vector3(-.2,0,0),Vector3(2,0,0)),"One hand cannot start drag")
	var drag=SwgMedicDrag.new()
	check(drag.sample(Vector3.ZERO,true,true,.01).start,"Drag establishes a physical anchor")
	check(drag.sample(Vector3(.01,0,0),true,true,.01).delta==Vector3(.01,0,0),"Physical hand displacement becomes drag motion")
	check(not drag.sample(Vector3(2,0,0),true,true,.01).active,"Tracking teleport cancels drag")
	var report={"passed":errors.is_empty(),"checks":checks,"errors":errors,"renderer":"dummy","live_headset_validated":false}
	FileAccess.open("res://../runtime/evidence/medic-client.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print(JSON.stringify(report));quit(0 if errors.is_empty() else 1)
