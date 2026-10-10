extends SceneTree
var failures:Array=[]
var checks:=0
func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures.append(label);push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	var ui:=preload("res://scripts/datapad_ui.gd").new();root.add_child(ui);ui.build_ui()
	ui.set_entries([{"id":"12","name":"placeholder","category":"data"}])
	var mission:Dictionary={"id":"12","name":"Parcel delivery","description":"Deliver medicine.","type":"deliver","target":"Recipient","reward":250,"difficulty":5,"active":true,"status":"Collect parcel","waypoint":{"planet":"tatooine","position":[100,0,200],"active":true}}
	ui.set_owned_missions([mission]);ui.select_category("missions")
	check(ui.filtered_entries.size()==1 and ui.detail_description.text=="Deliver medicine.","Owned mission replaces generic replicated object and exposes description")
	check(ui.detail_attributes.text.contains("Collect parcel") and ui.detail_attributes.text.contains("250 credits"),"Mission phase and reward visible")
	check(ui.map.waypoints.size()==1 and ui.map.waypoints[0].position==[100,0,200],"Native mission waypoint reaches map")
	mission.status="Deliver parcel";mission.waypoint.position=[300,0,400];ui.set_owned_missions([mission])
	check(ui.selected_entry.id=="12" and ui.detail_attributes.text.contains("Deliver parcel") and ui.map.waypoints[0].position==[300,0,400],"Progress refresh retains selection and updates destination")
	var second:Dictionary=mission.duplicate(true);second.id="13";second.name="Second mission"
	ui.set_owned_missions([mission,second]);ui.select_entry(1)
	second.status="Updated objective";ui.set_owned_missions([mission,second])
	check(ui.selected_entry.id=="13" and ui.detail_attributes.text.contains("Updated objective"),"Refresh preserves a selected mission beyond the first row")
	ui.set_owned_missions([])
	check(ui.map.waypoints.is_empty() and ui.filtered_entries.is_empty(),"Completed or cancelled mission removes objective and marker")
	ui.free()
	var radar:=preload("res://scripts/wrist_radar.gd").new();root.add_child(radar);radar.configure();radar.set_active(true)
	radar.refresh(Vector3.ZERO,Vector3.FORWARD,[{"id":"far","kind":"waypoint","position":Vector3(1000,0,0)},{"id":"npc","kind":"npc","position":Vector3(1000,0,0)}])
	check(radar.last_contacts.size()==1 and radar.last_contacts[0].id=="far" and radar.last_contacts[0].pixel.distance_to(Vector2(128,128))<=110.01,"Far active waypoint has bounded bearing; distant NPC omitted")
	radar.free()
	var catalog:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/assets/combat/catalog.json"))
	var state:=preload("res://combat/weapon_state.gd").new();var profile:Dictionary=catalog.weapons.pistol_cdef.duplicate(true);profile.item_id="99"
	check(state.configure(profile,profile.core3.certificationsRequired),"Original CDEF profile loads")
	state.rounds=1;state.tick(0,0,true,false);var shot:Dictionary=state.tick(.01,1,true,false)
	check(not shot.is_empty() and state.rounds==0 and state.reload_until>=0,"Last CDEF shot reserves capacity and starts automatic recovery")
	var rig:=preload("res://combat/ranged_rig.gd").new();rig.weapons=[{"state":state}];rig.selected=0;rig.shot_authority=func(_shot,_pose,_grip):return {}
	check(not rig.dispatch_shot(shot,Transform3D.IDENTITY,Vector3.ZERO,profile,false),"Local authority can reject unlaunched CDEF shot")
	check(state.rounds==1 and state.reload_until<0 and state.condition_damage==0,"Rejected CDEF shot restores capacity and wear without empty recovery")
	state.reload();state.refund_rounds(1)
	check(state.reload_until>=0,"Late receipt refund does not cancel a manual partial-capacity recovery")
	var live:=preload("res://combat/live_world.gd").new()
	state.reload_until=-1;state.rounds=2;state.reserve_rounds(1)
	live.shots["declined"]={"ammo_state":state,"ammo_spent":1,"accepted":false,"shot":{}}
	live.rejected_fire("declined");live.rejected_fire("declined")
	check(state.rounds==2,"Confirmed native rejection refunds ordinary capacity exactly once")
	state.reserve_rounds(1);live.shots["committed"]={"ammo_state":state,"ammo_spent":1,"accepted":true,"shot":{}}
	live.rejected_fire("committed")
	check(state.rounds==1,"Accepted discharge stays spent after a failed impact")
	live.free();rig.free()
	var sector:=preload("res://space/sector_scene.gd").new()
	sector.data=JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/assets/jtl/space_tatooine.json"))
	var station:Dictionary=sector.data.instances[0];var p:Array=station.position
	var contact:Dictionary={"template":str(station.source_template).replace("/shared_","/"),"position":[p[0],p[1],-p[2]]}
	check(sector.represents_station(contact),"Native Tatooine station contact reuses authored hull")
	contact.position[0]+=100
	check(not sector.represents_station(contact),"Separate station is not culled by template alone")
	contact.template="object/ship/tiefighter.iff"
	check(not sector.represents_station(contact),"Moving combat traffic remains visible")
	sector.free()
	var result:Dictionary={"passed":failures.is_empty(),"checks":checks,"failures":failures,"renderer":"dummy","xr":false}
	print(JSON.stringify(result));FileAccess.open("res://../runtime/evidence/mission-combat-20261010/client-regressions.json",FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	quit(0 if failures.is_empty() else 1)
