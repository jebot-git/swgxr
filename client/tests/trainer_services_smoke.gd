extends SceneTree
## Original basic and artisan-specialist catalog labels and costs; mocked authoritative training envelopes.
const ServicePanel=preload("res://scripts/service_panel.gd")
const Coordinator=preload("res://scripts/services_controller.gd")
const Fixtures=preload("res://tests/services_controller_smoke.gd")
class TrainerHost extends Fixtures.Host:
	var weapon_refreshes:=0
	var live_combat_reserved:=false
	func refresh_weapon_statistics() -> void:
		weapon_refreshes+=1;await get_tree().process_frame
class SkillPresentation extends Control:
	var skill_calls: Array=[]
	var experience_calls: Array=[]
	func set_skills(values: Array,complete: bool) -> void: skill_calls.append({"values":values.duplicate(),"complete":complete})
	func set_experience(values: Dictionary,complete: bool) -> void:
		# Match the real profession UI's equality guard; services and live updates share it.
		if not experience_calls.is_empty() and experience_calls.back().values==values and experience_calls.back().complete==complete: return
		experience_calls.append({"values":values.duplicate(true),"complete":complete})
class Datapad extends Node3D:
	var ui: Control
	func _init() -> void: ui=SkillPresentation.new();add_child(ui)
	func set_open(_value: bool) -> void: pass
const PROFESSIONS=["crafting_artisan","combat_brawler","social_entertainer","combat_marksman","science_medic","outdoors_scout","crafting_armorsmith","crafting_weaponsmith","crafting_chef","crafting_tailor","crafting_architect","crafting_droidengineer","crafting_merchant","crafting_shipwright"]
var failures: Array[String]=[]
var checks:=0
var requests: Array=[]
func check(value: bool,message: String) -> void:
	checks+=1
	if not value: failures.append(message);push_error(message)
func _initialize() -> void: call_deferred("run")
static func source_trainer(profession_id: String) -> Dictionary:
	var catalog: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/assets/professions/catalog.json"))
	for profession: Dictionary in catalog.professions:
		if str(profession.id)!=profession_id: continue
		var rows: Array=[]
		for node: Dictionary in profession.nodes:
			rows.append({"id":node.id,"name":node.label,"description":node.description,"learned":false,"eligible":str(node.id).ends_with("_novice"),
				"blocked_reason":"Required previous skill has not been learned.","credit_cost":node.credits,"skill_point_cost":node.points,
				"xp_type":node.xp_type,"xp_cost":node.xp_cost,"xp_available":0,"prerequisites":node.requires})
		return {"id":"fixture-native-trainer","kind":"trainer","name":str(profession.label)+" Trainer","profession":profession_id,"trainer_text":"Select a skill to inspect its native training requirements.","skills":rows}
	return {}
func run() -> void:
	var panel:=ServicePanel.new();root.add_child(panel)
	panel.action_requested.connect(func(action,payload): requests.append({"action":action,"payload":payload}))
	for profession_id in PROFESSIONS:
		var trainer:=source_trainer(profession_id)
		check(not trainer.is_empty(),"Original trainer skill graph exists: "+profession_id)
		panel.selected=-1;panel.configure(trainer,{"cash":10000,"bank":5000})
		check(panel.rows.size()==trainer.skills.size() and panel.terminal.trainer_text==trainer.trainer_text,"Original skill rows and trainer greeting preserved: "+profession_id)
		var novice:=-1
		var locked:=-1
		for index in range(panel.rows.size()):
			if bool(panel.rows[index].eligible): novice=index
			else: locked=index
		panel.selected=locked
		var before:=requests.size();panel.confirm()
		check(requests.size()==before and not panel.pending and panel.message==trainer.skills[locked].blocked_reason,"Native ineligible skill is inspectable but cannot train: "+profession_id)
		panel.selected=novice;panel.confirm()
		check(requests.back().action=="trainer_train" and requests.back().payload.skill_id==trainer.skills[novice].id and requests.back().payload.terminal_id==trainer.id,"Training request retains actual selected source skill and trainer IDs: "+profession_id)
		check(not panel.rows[novice].learned and panel.wallet.cash==10000,"Selecting training never grants a local skill or deducts credits: "+profession_id)
		before=requests.size();panel.confirm()
		check(requests.size()==before,"Pending training cannot repeat: "+profession_id)
		trainer.skills[novice].learned=true;trainer.skills[novice].eligible=false
		panel.configure(trainer,{"cash":9900,"bank":5000});panel.confirm()
		check(requests.size()==before and panel.trainer_blocked_reason(panel.rows[novice])=="Already learned.","Native learned state prevents repeated training: "+profession_id)
		var detail: String=panel.detail_for(panel.rows[novice])
		check(detail.contains("%d credits"%int(trainer.skills[novice].credit_cost)) and detail.contains("%d skill points"%int(trainer.skills[novice].skill_point_cost)),"Native credit and skill-point costs shown: "+profession_id)
	var marksman:=source_trainer("combat_marksman")
	panel.configure(marksman,{"cash":5000,"bank":0})
	var pistol: Dictionary={}
	for row: Dictionary in panel.rows:
		if row.id=="combat_marksman_pistol_01": pistol=row
	check(not pistol.is_empty(),"Original pistol skill available for detail verification")
	pistol.xp_available=75;pistol.xp_name="Pistol"
	var detail: String=panel.detail_for(pistol)
	check(detail.contains("Pistol XP") and detail.contains("75 / %d"%int(pistol.xp_cost)),"Training detail uses native XP category and current/required amounts")
	check(detail.contains("Novice Marksman"),"Prerequisite source skill IDs resolve to original skill names")
	check(not panel.trainer_blocked_reason({"learned":false}).is_empty(),"Missing native eligibility never enables training")
	check(panel.trainer_blocked_reason({"learned":true,"eligible":true})=="Already learned.","Learned state takes precedence over malformed eligibility")
	panel.free()
	var host:=TrainerHost.new();root.add_child(host)
	host.player=CharacterBody3D.new();host.add_child(host.player)
	host.stage=Fixtures.Stage.new();host.add_child(host.stage)
	host.inventory=Fixtures.Inventory.new();host.add_child(host.inventory)
	host.live_combat=Fixtures.Live.new();host.add_child(host.live_combat);host.live_combat.live=true
	host.datapad=Datapad.new();host.add_child(host.datapad)
	var coordinator:=Coordinator.new();host.add_child(coordinator);coordinator.set_process(false);coordinator.app=host;coordinator.epoch=host.datapad_epoch;coordinator.set_allowed(true)
	var response: Dictionary=host.response()
	response.state.skills=["combat_marksman_novice"];response.state.skills_complete=true
	response.state.experience={"pistol":75};response.state.experience_complete=true
	check(coordinator.accept_response(response),"Validated CoreCU trainer state accepted")
	check(host.datapad.ui.skill_calls.size()==1 and host.datapad.ui.skill_calls[0].values==["combat_marksman_novice"],"Complete native skill snapshot reaches datapad without legacy request")
	check(host.datapad.ui.experience_calls.size()==1 and host.datapad.ui.experience_calls[0].values.pistol==75,"Complete native XP snapshot reaches datapad progress display")
	coordinator.accept_response(response)
	check(host.datapad.ui.skill_calls.size()==1 and host.datapad.ui.experience_calls.size()==1,"Unchanged status snapshots do not rebuild profession presentation")
	var incomplete:=response.duplicate(true);incomplete.state.skills=[];incomplete.state.skills_complete=false;incomplete.state.experience={};incomplete.state.experience_complete=false
	coordinator.accept_response(incomplete)
	check(host.datapad.ui.skill_calls.size()==1 and host.datapad.ui.experience_calls.size()==1,"Partial snapshots cannot clear known complete skills or XP")
	var invalid:=response.duplicate(true);invalid.state.character_id="other"
	check(not coordinator.accept_response(invalid) and host.datapad.ui.skill_calls.size()==1,"Wrong-character skills cannot reach current datapad")
	invalid=response.duplicate(true);invalid.source_kind="local_store"
	check(not coordinator.accept_response(invalid) and host.datapad.ui.experience_calls.size()==1,"Non-CoreCU progress cannot reach datapad")
	invalid=response.duplicate(true);invalid.state.skills=[12];invalid.state.experience={"pistol":-10}
	coordinator.accept_response(invalid)
	check(host.datapad.ui.skill_calls.size()==1 and host.datapad.ui.experience_calls.size()==1,"Malformed skills and negative XP rejected before presentation")
	var trained:=response.duplicate(true);trained.state.skills.append("combat_marksman_pistol_01");trained.state.experience.pistol=10;trained.state.wallet.cash=700
	trained.live_response={"session_id":"session-1","sequence":2}
	host.next_response=trained
	await coordinator.request("trainer_train",{"terminal_id":"actual-native-trainer-id","skill_id":"combat_marksman_pistol_01"})
	check(host.calls.size()==1 and host.calls[0].path=="/services/trainer_train" and host.calls[0].payload.skill_id=="combat_marksman_pistol_01","Trainer mutation uses native service API with exact skill identity")
	check(host.datapad.ui.skill_calls.size()==2 and host.datapad.ui.skill_calls.back().values.has("combat_marksman_pistol_01"),"Only confirmed training response updates learned skill presentation")
	check(host.datapad.ui.experience_calls.back().values.pistol==10 and host.live_combat.accepted==1,"Native XP deduction and authoritative live certification refresh propagated")
	var stale:=response.duplicate(true);stale.live_response={"session_id":"session-1","sequence":1}
	coordinator.accept_response(stale)
	check(host.datapad.ui.skill_calls.size()==2 and host.datapad.ui.experience_calls.back().values.pistol==10,"Older same-session service envelope cannot roll back learned skills or XP")
	stale.live_response={"session_id":"different-session","sequence":100};coordinator.accept_response(stale)
	check(host.datapad.ui.skill_calls.size()==2 and host.datapad.ui.experience_calls.back().values.pistol==10,"Different live session cannot overwrite progress even with higher sequence")
	host.live_combat.sequence=3;host.datapad.ui.set_experience({"pistol":60},true)
	trained.live_response={"session_id":"session-1","sequence":4};coordinator.accept_response(trained)
	check(host.datapad.ui.experience_calls.back().values.pistol==10,"Newer source service XP applies after intervening live write even when equal to older service value")
	var same_revision:=trained.duplicate(true);same_revision.state.experience.pistol=11;coordinator.accept_response(same_revision)
	check(host.datapad.ui.experience_calls.back().values.pistol==11,"Equal current live revision remains eligible for complete native progress display")
	check(host.weapon_refreshes==0,"Persistent live training updates combat through live envelope, never legacy weapon refresh")
	check(host.calls.all(func(call): return str(call.path).begins_with("/services/")),"Live training never calls legacy datapad endpoint")
	var before:int=host.datapad.ui.skill_calls.size()
	host.next_response={"ok":false,"error":"Native prerequisite changed"}
	await coordinator.request("trainer_train",{"terminal_id":"actual-native-trainer-id","skill_id":"combat_marksman_pistol_02"})
	check(host.datapad.ui.skill_calls.size()==before,"Rejected native training cannot optimistically add a skill")
	check(host.weapon_refreshes==0,"Rejected training does not refresh combat statistics")
	host.live_combat.live=false;host.next_response=trained
	await coordinator.request("trainer_train",{"terminal_id":"actual-native-trainer-id","skill_id":"combat_marksman_pistol_02"})
	check(host.weapon_refreshes==1,"Successful non-live training refreshes native weapon modifiers and certification")
	var rejected:=trained.duplicate(true);rejected.mutation={"success":false,"error_code":"not_eligible"};host.next_response=rejected
	await coordinator.request("trainer_train",{"terminal_id":"actual-native-trainer-id","skill_id":"combat_marksman_pistol_03"})
	check(host.weapon_refreshes==1,"Native refused mutation with valid envelope does not refresh weapons")
	host.live_combat_reserved=true;host.next_response=trained
	await coordinator.request("trainer_train",{"terminal_id":"actual-native-trainer-id","skill_id":"combat_marksman_pistol_03"})
	check(host.weapon_refreshes==1,"Disconnected but reserved persistent session cannot fall back to legacy weapon endpoint")
	host.queue_free();await process_frame
	var result: Dictionary={"checks":checks,"failures":failures,"passed":failures.is_empty(),"skills":"fourteen original user-media profession graphs","authority":"mocked CoreCU envelopes only; native server tested separately","renderer":"headless dummy; XR disabled"}
	var file:=FileAccess.open(ProjectSettings.globalize_path("res://../runtime/evidence/trainer-services-smoke.json"),FileAccess.WRITE)
	if file!=null: file.store_string(JSON.stringify(result,"\t"))
	print(JSON.stringify(result));quit(0 if failures.is_empty() else 1)
