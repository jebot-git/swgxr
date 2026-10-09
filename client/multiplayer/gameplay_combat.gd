extends "res://combat/live_world.gd"
## Reuses the proven native shot/impact queue in the ordinary RPG session.
## This bridge never starts/stops another native login or owns scene actors.
var session:Node
var sync:Node
var blocked_revision:=-1
func attach(host:Node,combat_rig:Node3D,gameplay:Node,replication:Node)->void:
	app=host;rig=combat_rig;session=gameplay;sync=replication;stage=app.stage;player=app.player
	owner_account=app.datapad_account;owner_character=app.datapad_character_id
	rig.authority_gate=is_ready;rig.shot_authority=register_shot
	rig.rounds_sim.authoritative_contact.connect(contact)
	rig.close_ability_menu();rig.abilities.primed=false
	refresh_authority()
func refresh_authority()->void:
	if not is_instance_valid(session) or not session.live or session.character_id!=owner_character or not is_instance_valid(sync):
		live=false;native_ready=false;return
	if session_id!=session.session_id:
		cancel_showdown()
		generation+=1;queue.clear();shots.clear();next_launch_usec=0;blocked_revision=-1;abilities_revision=-1
	session_id=session.session_id;sequence=session.sequence;player_state=session.player_state;pending_transport=session.pending_transport;life_action_pending=session.life_action_pending
	weapon=session.weapon_state.duplicate(true);elapsed_since_snapshot=maxf(0,(Time.get_ticks_msec()-session.last_confirmed_ms)/1000.0)
	actors=sync.entities.actors
	live=true;native_ready=valid_weapon(weapon) and sequence>blocked_revision and elapsed_since_snapshot<SESSION_TIMEOUT
	# Equipping a different source item creates new local WeaponState objects.
	# Disable local HAM/wear prediction every time, without mutating native stats.
	for entry:Dictionary in rig.weapons:
		entry.state.ability_state=null;entry.state.wear_per_shot=0.0
		if native_ready and str(entry.state.profile.get("item_id",""))==str(weapon.item_id):
			entry.state.profile.rpm=60.0/float(weapon.fire_interval_seconds)
			# Native cadence already includes the current armour output penalty.
			var captured: Dictionary = entry.state.profile.get("armour_scales", {}).duplicate(true)
			captured["output_scale"] = float(player_state.get("armour", {}).get("output_scale", 1))
			entry.state.profile["armour_scales"] = captured
			entry.state.profile["profession"]={"rpm_scale":1.0}
			entry.state.profile.projectile_speed=float(weapon.get("projectile_speed",100))
			entry.state.core.maxRange=float(weapon.max_range_m)
			sync_commando_profile(entry.state)
			sync_bountyhunter_profile(entry.state)
	if rig.get("unarmed") is Dictionary:
		for state in rig.unarmed.values():state.ability_state=null;state.wear_per_shot=0.0
	sync_native_abilities()
func valid_weapon(value:Dictionary)->bool:
	if str(value.get("item_id","")).is_empty() or not value.get("certified",false):return false
	for key in ["fire_interval_seconds","max_range_m","projectile_speed"]:
		if not is_finite(float(value.get(key,NAN))) or float(value.get(key,0))<=0:return false
	if bool(value.get("unarmed",false)) and rig.get("unarmed") is Dictionary:return not rig.unarmed.is_empty()
	return rig.weapons.any(func(entry):return str(entry.state.profile.get("item_id",""))==str(value.item_id) )
func has_pending_commands()->bool:return busy or not queue.is_empty()
func is_ready()->bool:
	return is_instance_valid(session) and not app.session_leaving and app.world_ready and super.is_ready()
func pump()->void:
	if busy or not live or queue.is_empty() or session.busy:return
	if session.authority_expired():fail("Core3 authority expired; queued combat gestures discarded.");return
	if app.has_method("native_requests_in_flight") and app.native_requests_in_flight()>0:return
	var request:Dictionary=queue.pop_front()
	var id:=str(request.get("shot_id",""))
	if not shots.has(id) or Time.get_ticks_usec()>int(shots[id].expires_usec):shots.erase(id);return
	if request.kind=="impact" and not shots[id].accepted:return
	busy=true
	var epoch:=generation
	var response:Dictionary=await app.api(HTTPClient.METHOD_POST,"/combat/session/"+str(request.kind),request.payload)
	if epoch!=generation:return
	busy=false
	if settle_movement_rejection(response,request):
		session.next_update=0
		session.last_position=Vector3.INF
		return
	if not session.accept_native_response(response):fail(session.last_error);return
	refresh_authority()
	combat_receipt(request,response)
func fail(reason:String)->void:
	cancel_showdown()
	# An uncertain fire receipt disarms until a later authoritative heartbeat;
	# dropping the whole persistent RPG session would also lose unrelated work.
	last_error=reason;blocked_revision=session.sequence if is_instance_valid(session) else sequence
	queue.clear();shots.clear();native_ready=false
func discard_movement_commands()->void:
	super.discard_movement_commands()
	blocked_revision=session.sequence if is_instance_valid(session) else sequence
func reset(reason:="Gameplay combat stopped.")->void:
	cancel_showdown()
	generation+=1;live=false;native_ready=false;busy=false;session_id="";sequence=-1;queue.clear();shots.clear();actors={};last_error=reason
func _process(_delta:float)->void:
	refresh_authority()
	if not live:return
	for id in shots.keys():
		if Time.get_ticks_usec()>int(shots[id].expires_usec):shots.erase(id)
	if elapsed_since_snapshot>=SESSION_TIMEOUT:
		fail("Core3 authority expired; queued combat gestures discarded.");return
	pump()
func _exit_tree()->void:
	if is_instance_valid(rig):
		if rig.rounds_sim.authoritative_contact.is_connected(contact):rig.rounds_sim.authoritative_contact.disconnect(contact)
		# Fail closed while a still-visible rig is being torn down.
		rig.authority_gate=func():return false
		rig.shot_authority=Callable()

func apply_loadout_response(response:Dictionary)->bool:
	if not is_instance_valid(session) or not session.accept_native_response(response):return false
	refresh_authority();return true
