extends SceneTree
const State=preload("res://multiplayer/replication_state.gd")
var checks:=0
var errors:Array=[]
func check(value:bool,message:String)->void:
	checks+=1
	if not value:errors.append(message);push_error(message)
func response(sequence:=1,revision:=1)->Dictionary:
	return {"ok":true,"backend":"core3","source_kind":"core3_multiplayer_sync","character_id":"101","session_id":"owned","sequence":sequence,"world_revision":revision,
		"world":{"source_kind":"core3_world","full":true,"players":[{"id":"101","position":[0,0,0],"heading_radians":0,"appearance":{},"posture":0,"building_id":"0","cell_index":0},{"id":"102","position":[2,0,0],"heading_radians":0,"appearance":{"template":"original","equipment":[{"id":"77"}]},"posture":0,"building_id":"0","cell_index":0}],"actors":[{"id":"103","kind":"creature","template":"original_creature","position":[4,0,0],"heading_radians":0,"dead":false,"health":100,"max_health":100}]},
		"poses":[{"id":"102","sequence":1,"position":[2.5,0,0],"heading_radians":.5,"building_id":"0","cell_index":0,"age_ms":100,"tracking":{"head":{"tracked":true,"position":[2.5,1.8,0],"rotation":[0,0,0,1]},"left_hand":{"tracked":true,"position":[2,1,0],"rotation":[0,0,0,1]}}}]}
func _initialize()->void:call_deferred("run")
func run()->void:
	var state:=State.new()
	check(state.accept(response(),"101","owned",1),"Accept authenticated owned full observer snapshot")
	check(state.players.size()==1 and state.players[0].id=="102","Self omitted from remote player projection")
	check(state.players[0].position==[2.5,0,0] and state.players[0].tracking.size()==2,"Fresh same-cell visual poses decorate native identity")
	check(state.players[0].appearance.equipment[0].id=="77" and state.actors[0].health==100,"Equipment and actor health stay Core3 authoritative")
	var delta:=response(2);delta.world=null;delta.poses[0].position=[3,0,0]
	check(state.accept(delta,"101","owned",2) and state.players[0].position==[3,0,0],"Unchanged native revision accepts cheap pose update without retransmitting world")
	check(state.native_world.players[1].position==[2,0,0],"Pose overlay never rewrites cached authoritative world anchor")
	check(not state.accept(delta,"101","owned",2),"Duplicate/out-of-order transport response rejected")
	var other:=response(3);other.character_id="999"
	check(not state.accept(other,"101","owned",3) and state.sequence==2,"Foreign character cannot alter replicated state")
	other=response(3);other.session_id="replaced"
	check(not state.accept(other,"101","owned",3),"Replaced session rejects in-flight old ownership")
	other=response(3,0)
	check(not state.accept(other,"101","owned",3),"Older native revision cannot roll back health or equipment")
	other=response(3);other.world=null;other.poses[0].age_ms=1001
	check(state.accept(other,"101","owned",3) and state.players[0].position==[2,0,0] and state.players[0].tracking.is_empty(),"Stale tracking falls back to native location and source animation")
	other=response(4);other.poses[0].building_id="44"
	check(state.accept(other,"101","owned",4) and state.players[0].position==[2,0,0],"Cross-cell visual pose cannot drag native identity through walls")
	other=response(5);other.poses[0].id="999"
	check(state.accept(other,"101","owned",5) and state.players.size()==1 and state.players[0].position==[2,0,0],"Presentation-only ID cannot create a fabricated player")
	other=response(6);other.poses[0].position=[100,0,0]
	check(state.accept(other,"101","owned",6) and state.players[0].position==[2,0,0],"Tracking cannot move body outside authenticated anchor radius")
	other=response(7);other.poses[0].tracking.head.position=[1000,0,0];other.poses[0].tracking.left_hand.rotation=[1,1,1,1]
	check(state.accept(other,"101","owned",7) and state.players[0].tracking.is_empty(),"Malformed rotation and out-of-reach tracking discarded")
	other=response(8);other.world.players.append(other.world.players[1].duplicate())
	check(not state.accept(other,"101","owned",8),"Duplicate IDs fail entire native snapshot atomically")
	other=response(8);other.world.players[1].position=[NAN,0,0]
	check(not state.accept(other,"101","owned",8),"Nonfinite native transform rejected")
	other=response(8);other.world.actors[0].max_health=0
	check(not state.accept(other,"101","owned",8),"Incomplete actor state cannot create broken collision/render entities")
	other=response(8,2);other.world.players=[];other.world.actors=[];other.poses=[]
	check(state.accept(other,"101","owned",8) and state.players.is_empty() and state.actors.is_empty(),"Complete native removal clears departed players and entities")
	var stage_basis:=Basis(Vector3.UP,.4)
	var original:=Basis.from_euler(Vector3(.2,-.5,.9))
	var encoded:=State.source_rotation(original,stage_basis)
	check(State.world_rotation(encoded,stage_basis).is_equal_approx(original),"Source-world quaternion reflection round trips head and both hands")
	state.reset();other=response(1);other.world=null
	check(not state.accept(other,"101","owned",1),"Reconnection requires complete snapshot rather than inherited old character state")
	other=response(1);other.world.truncated=true
	check(state.accept(other,"101","owned",1),"Bounded complete AOI subset remains usable when distant entities were truncated")
	other=response(2,2);other.event_sequence=20;other.events=[{"id":20,"actor_id":"102","kind":"survey","position":[2,0,0]}]
	check(state.accept(other,"101","owned",2) and state.events.size()==1 and state.event_sequence==20,"Native action event advances the presentation cursor once")
	other=response(3,2);other.event_sequence=20;other.events=[]
	check(state.accept(other,"101","owned",3) and state.events.is_empty(),"Unchanged event cursor cannot replay survey pulse")
	other=response(4,2);other.event_sequence=21;other.events=[{"id":20,"actor_id":"102","kind":"survey","position":[2,0,0]}]
	check(not state.accept(other,"101","owned",4) and state.event_sequence==20,"Replayed event rejected without advancing authoritative world or action cursor")
	other=response(4,2);other.event_sequence=21;other.events=[{"id":21,"actor_id":"102","kind":"fire","position":[INF,0,0]}]
	check(not state.accept(other,"101","owned",4),"Nonfinite native event position rejected")
	other=response(4,2);other.world.deployments=[{"id":"42:1","owner_id":"102","template":"original_tool","position":[2,0,0]}]
	check(state.accept(other,"101","owned",4) and state.native_world.deployments.size()==1,"Native ledger deployment is retained separately from actor identity and private inventory")
	other=response(5,2);other.world.deployments=[{"id":"42:1","owner_id":"102","template":"original_tool","position":[NAN,0,0]}]
	check(not state.accept(other,"101","owned",5),"Malformed tool deployment cannot enter world projection")
	other=response(5,2);other.poses[0].physical_posture=1
	check(state.accept(other,"101","owned",5) and state.players[0].physical_posture==1,"Tracked upright native player can present actual physical crouching")
	other=response(6,2);other.poses[0].physical_posture=2;other.world.players[1].posture=13
	check(state.accept(other,"101","owned",6) and not state.players[0].has("physical_posture"),"Native incapacitation always defeats transient physical posture")
	other=response(7,2);other.poses[0].physical_posture=2;other.poses[0].tracking.head.tracked=false
	check(state.accept(other,"101","owned",7) and not state.players[0].has("physical_posture"),"Physical posture requires fresh actual head tracking")
	state.reset();other=response(1);other.world.players=[];other.poses=[]
	for n in range(32):other.world.players.append({"id":str(1000+n),"position":[n,0,0],"heading_radians":0,"appearance":{},"posture":0,"building_id":"0","cell_index":0})
	check(state.accept(other,"101","owned",1) and state.players.size()==32,"32 nearby players fit the rendering budget independently of total connected population")
	other=response(2,2);other.world.players=[];other.poses=[]
	for n in range(33):other.world.players.append({"id":str(1000+n),"position":[n,0,0],"heading_radians":0,"appearance":{},"posture":0,"building_id":"0","cell_index":0})
	check(not state.accept(other,"101","owned",2),"Oversized single-response peer list remains bounded during stress testing")
	print(JSON.stringify({"checks":checks,"errors":errors,"mocked":true,"live_xr":false}));quit(0 if errors.is_empty() else 1)
