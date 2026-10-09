extends SceneTree
var checks:=0
var failures:Array[String]=[]
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failures.append(message);push_error(message)
func _initialize()->void:call_deferred("run")
func run()->void:
	var ui:=preload("res://scripts/datapad_ui.gd").new();root.add_child(ui)
	root.add_child(ui.take_detail_panel())
	ui.select_category("skills")
	var trees:Control=ui.professions
	check(trees.catalog.get("professions",[]).size()>30,"Original profession catalog loaded")
	var marksman:Dictionary={}
	var rifleman:Dictionary={}
	for p:Dictionary in trees.catalog.get("professions",[]):
		for node:Dictionary in p.nodes:
			if node.id=="combat_marksman_rifle_04":marksman=node
			if node.id=="combat_rifleman_novice":rifleman=node
	check(not marksman.is_empty() and not rifleman.is_empty(),"Original linked profession skills available")
	ui.set_skills([marksman.id,rifleman.id],true)
	ui.set_forget_skills(JSON.parse_string(JSON.stringify([{"skill_id":marksman.id,"eligible":true,"refunded_points":2},{"skill_id":rifleman.id,"eligible":true,"reason":"Eligible","refunded_points":6}])),40)
	check(not trees.forget_status(marksman.id).eligible,"Learned advanced profession blocks prerequisite even with stale server eligibility")
	for i in trees.catalog.professions.size():
		if trees.catalog.professions[i].id=="combat_rifleman":trees.show_profession(i)
	trees.select_skill(rifleman)
	check(ui.forget_button.visible and not ui.forget_button.disabled and "6" in ui.forget_button.text,"Learned leaf presents native refund amount")
	var actions:Array=[];ui.forget_skill_requested.connect(func(id):actions.append(id))
	ui.forget_button.pressed.emit()
	check(actions==[rifleman.id] and rifleman.id in trees.learned,"Click sends request and never locally removes skill")
	ui.set_busy(true);ui.forget_button.pressed.emit()
	check(actions.size()==1 and ui.forget_button.disabled,"Pending request cannot repeat")
	ui.set_busy(false)
	ui.set_forget_skills([{"skill_id":rifleman.id,"eligible":false,"reason":"Leave combat before forgetting skills","refunded_points":6}],40)
	check(ui.forget_button.disabled and "combat" in ui.forget_button.tooltip_text,"Native refusal is visible and disables action")
	ui.set_skills([marksman.id],true)
	check(not trees.forget_status(marksman.id).eligible,"New learned snapshot invalidates previous eligibility")
	ui.set_forget_skills([{"skill_id":marksman.id,"eligible":true,"reason":"Eligible","refunded_points":3}],46)
	check(trees.forget_status(marksman.id).eligible,"Former dependency becomes leaf only after authoritative removal")
	ui.set_forget_skills([{"skill_id":marksman.id,"eligible":true,"reason":"Eligible","refunded_points":3.5}],46)
	check(not trees.forget_status(marksman.id).eligible,"Fractional native refund is rejected")
	ui.select_category("waypoints")
	check(not ui.forget_button.visible,"Forget does not leak into item details")
	ui.set_skills([],false)
	check(not trees.forget_status(marksman.id).eligible,"Character reset disables forgetting")
	print(JSON.stringify({"passed":failures.is_empty(),"checks":checks,"failures":failures,"native_mutation_tested":false}))
	quit(0 if failures.is_empty() else 1)
