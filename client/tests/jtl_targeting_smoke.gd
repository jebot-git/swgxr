extends SceneTree
const Targeting=preload("res://space/targeting.gd")
var failures:Array[String]=[]
func check(ok:bool,label:String)->void:
	if not ok:failures.append(label);push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	var rows:Array=[{"id":"1","hostile":true},{"id":"2","hostile":false},{"id":"3","hostile":true}]
	check(Targeting.cycle(rows,"1")=="3" and Targeting.cycle(rows,"1",true)=="3","Hostile cycling filters friendly contacts and wraps")
	check(Targeting.pick(rows,Vector3.ZERO,Vector3.FORWARD,{"1":Vector3(0,0,-100),"3":Vector3(0,0,100)})=="1","Look selection chooses forward contact, excludes rear contact")
	check(Targeting.pick(rows,Vector3.ZERO,Vector3.FORWARD,{"1":Vector3(100,0,-100)})=="","Look selection respects acquisition angular boundary")
	check(Targeting.next_component({"component_slot":-1,"components":[{"slot":0,"available":false},{"slot":1,"available":true}]})==1,"Subsystem cycling skips destroyed/protected parts")
	check(Targeting.next_component({"component_slot":1,"components":[{"slot":1,"available":true}]})==-1,"Whole-ship targeting remains explicitly selectable")
	var lead:=Targeting.intercept(Vector3(0,0,-500),Vector3(100,0,0),1000,1)
	check(not lead.is_empty() and lead.offset.x>50 and lead.offset.x<51,"Lateral target produces projectile-speed-based lead")
	check(Targeting.intercept(Vector3(0,0,-500),Vector3(0,0,-2000),1000,1).is_empty(),"Unreachable receding target has no false lead")
	check(Targeting.intercept(Vector3(0,0,-1500),Vector3.ZERO,1000,1).is_empty(),"Beyond projectile lifetime has no firing solution")
	var stationary:=Targeting.intercept(Vector3(0,0,-500),Vector3.ZERO,1000,1)
	check(not stationary.is_empty() and stationary.offset==Vector3.ZERO,"Stationary target requires no lead")
	var hud=preload("res://space/targeting_hud.gd").new();root.add_child(hud)
	hud.project(hud.reticle,Vector3(0,0,-100),Transform3D.IDENTITY)
	check(hud.reticle.visible and hud.reticle.position.is_equal_approx(Vector3(0,0,-2)),"Reticle projects along firing axis")
	hud.project(hud.reticle,Vector3(0,0,-100),Transform3D(Basis(Vector3.UP,PI),Vector3.ZERO))
	check(not hud.reticle.visible,"Looking behind does not redirect firing reticle")
	var fx=preload("res://space/combat_effects.gd").new();root.add_child(fx)
	fx.receive([{"id":"3","kind":"missile","ship_id":"1","missile_id":"9","position":[10,20,30]},{"id":"2","kind":"missile","ship_id":"1","missile_id":"9","position":[1,2,3]}])
	check(fx.missiles["1:9"].destination==Vector3(10,20,-30),"Newest authoritative missile position wins overlapping receipts")
	fx.receive([{"id":"4","kind":"missile","ship_id":"1","missile_id":"9","done":true},{"id":"1","kind":"missile","ship_id":"1","missile_id":"9","position":[1,2,3]}])
	check(fx.missiles.is_empty(),"Completed missile cannot be resurrected by late receipt")
	fx.queue_free()
	var prefs=preload("res://space/preferences.gd").new();prefs.path="user://targeting_test.cfg";prefs.buttons.next=17;prefs.buttons.fire=-1
	check(prefs.save_preferences()==OK,"Targeting hardware bindings save")
	var restored=preload("res://space/preferences.gd").new();restored.path=prefs.path;restored.load_preferences()
	check(restored.buttons.next==17 and restored.buttons.fire==-1,"Targeting hardware bindings restore")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(prefs.path));hud.queue_free();await process_frame
	print(JSON.stringify({"passed":failures.is_empty(),"failures":failures,"renderer":"dummy","xr":false}));quit(0 if failures.is_empty() else 1)
