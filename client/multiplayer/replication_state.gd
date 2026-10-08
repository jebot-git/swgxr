extends RefCounted
## Validates the authenticated snapshot before any render state changes. Poses
## only decorate IDs in Core3's observer set; they never create gameplay objects.
const MAX_PLAYERS:=32
const MAX_ACTORS:=96
const POSE_TTL_MS:=1000.0
const SOURCE_REFLECTION:=Basis(Vector3.RIGHT,Vector3.UP,Vector3(0,0,-1))
var sequence:=-1
var world_revision:=-1
var event_sequence:=-1
var events:Array=[]
var players:Array=[]
var actors:Array=[]
var native_world:Dictionary={}
var error:=""
func reset()->void:
	sequence=-1;world_revision=-1;event_sequence=-1;events=[];players=[];actors=[];native_world={};error=""
static func finite_point(value:Variant)->bool:
	if not value is Array or value.size()!=3:return false
	for component in value:
		if not (component is int or component is float) or not is_finite(float(component)) or absf(float(component))>20000:return false
	return true
static func finite_rotation(value:Variant)->bool:
	if not value is Array or value.size()!=4:return false
	var length_squared:=0.0
	for component in value:
		if not (component is int or component is float) or not is_finite(float(component)):return false
		length_squared+=float(component)*float(component)
	return absf(length_squared-1.0)<.05
static func valid_id(value:Variant)->bool:
	return value is String and value.is_valid_int() and int(value)>0
static func point(value:Array)->Vector3:return Vector3(float(value[0]),float(value[1]),float(value[2]))
static func source_rotation(world_basis:Basis,stage_basis:=Basis.IDENTITY)->Array:
	var reflected:=SOURCE_REFLECTION*stage_basis.inverse()*world_basis.orthonormalized()*SOURCE_REFLECTION
	var q:=reflected.orthonormalized().get_rotation_quaternion()
	return [q.x,q.y,q.z,q.w]
static func world_rotation(value:Array,stage_basis:=Basis.IDENTITY)->Basis:
	var q:=Quaternion(float(value[0]),float(value[1]),float(value[2]),float(value[3])).normalized()
	return stage_basis*SOURCE_REFLECTION*Basis(q)*SOURCE_REFLECTION
func accept(response:Dictionary,character_id:String,session_id:String,minimum_sequence:int)->bool:
	error=""
	if not response.get("ok",false) or response.get("backend")!="core3" or response.get("source_kind")!="core3_multiplayer_sync" or str(response.get("character_id",""))!=character_id or str(response.get("session_id",""))!=session_id:
		error=str(response.get("error","Mismatched multiplayer snapshot ownership."));return false
	var incoming:=int(response.get("sequence",-1))
	if incoming<minimum_sequence or incoming<=sequence:error="Stale multiplayer snapshot.";return false
	var revision:=int(response.get("world_revision",-1))
	if revision<0 or revision<world_revision:error="Stale Core3 world revision.";return false
	var world:Variant=response.get("world")
	if world==null and revision==world_revision and not native_world.is_empty():world=native_world
	if not world is Dictionary or world.get("source_kind")!="core3_world" or not world.get("full",false) or not world.get("players") is Array or not world.get("actors") is Array or world.players.size()>MAX_PLAYERS or world.actors.size()>MAX_ACTORS:
		error="Incomplete or oversized Core3 world snapshot.";return false
	var seen:Dictionary={}
	for records in [world.players,world.actors]:
		for row in records:
			if not row is Dictionary or not valid_id(row.get("id")) or seen.has(row.id) or not finite_point(row.get("position")) or not is_finite(float(row.get("heading_radians",NAN))):
				error="Malformed Core3 world identity or transform.";return false
			seen[row.id]=true
	for row:Dictionary in world.players:
		if not row.get("appearance") is Dictionary or int(row.get("posture",-1)) not in range(15):error="Missing original remote player appearance/posture.";return false
	for row:Dictionary in world.actors:
		if row.get("kind","") not in ["creature","lair"] or not row.get("dead") is bool or str(row.get("template","")).is_empty() or not is_finite(float(row.get("health",NAN))) or not is_finite(float(row.get("max_health",NAN))) or float(row.max_health)<=0:
			error="Incomplete native entity state.";return false
	var deployments:Variant=world.get("deployments",[])
	if not deployments is Array or deployments.size()>64:error="Oversized deployed tool snapshot.";return false
	var tool_ids:Dictionary={}
	for tool in deployments:
		if not tool is Dictionary or str(tool.get("id","")).is_empty() or tool_ids.has(str(tool.id)) or not valid_id(tool.get("owner_id")) or not finite_point(tool.get("position")) or str(tool.get("template",tool.get("shared_template",""))).is_empty():
			error="Malformed native deployed tool.";return false
		tool_ids[str(tool.id)]=true
	var poses:Variant=response.get("poses",[])
	if not poses is Array or poses.size()>MAX_PLAYERS:error="Oversized tracked presentation snapshot.";return false
	var by_id:Dictionary={}
	for pose in poses:
		if not pose is Dictionary or not valid_id(pose.get("id")) or by_id.has(pose.id):error="Malformed tracked presentation identity.";return false
		# Invalid/stale visual tracking is discarded without discarding native state.
		if not finite_point(pose.get("position")) or not is_finite(float(pose.get("heading_radians",NAN))):continue
		var age:=float(pose.get("age_ms",INF))
		if not is_finite(age) or age<0 or age>POSE_TTL_MS:continue
		by_id[pose.id]=pose
	var next_players:Array=[]
	for native:Dictionary in world.players:
		if native.id==character_id:continue
		var row:=native.duplicate(true)
		row.tracking={}
		var pose:Dictionary=by_id.get(native.id,{})
		if not pose.is_empty() and str(pose.get("building_id","0"))==str(native.get("building_id","0")) and int(pose.get("cell_index",0))==int(native.get("cell_index",0)) and point(pose.position).distance_to(point(native.position))<=64.0:
			row.position=pose.position.duplicate();row.heading_radians=pose.heading_radians;row.pose_age_ms=pose.age_ms
			var tracking:Variant=pose.get("tracking",{})
			if tracking is Dictionary:
				for key in ["head","left_hand","right_hand"]:
					var target:Variant=tracking.get(key)
					if target is Dictionary and target.get("tracked",false) and finite_point(target.get("position")) and finite_rotation(target.get("rotation")) and point(target.position).distance_to(point(row.position))<=3.0:row.tracking[key]=target.duplicate(true)
		if int(native.posture)==0 and row.tracking.has("head"):
			var physical:Variant=pose.get("physical_posture",0)
			if (physical is int or physical is float) and float(physical)==float(int(physical)) and int(physical) in [0,1,2]:row.physical_posture=int(physical)
		next_players.append(row)
	var event_head:=int(response.get("event_sequence",event_sequence))
	var incoming_events:Variant=response.get("events",[])
	if event_head<event_sequence or not incoming_events is Array or incoming_events.size()>256:error="Invalid native event stream.";return false
	var next_events:Array=[]
	var event_seen:Dictionary={}
	for event in incoming_events:
		if not event is Dictionary or not (event.get("id") is int or event.get("id") is float) or int(event.id)<=event_sequence or int(event.id)>event_head or event_seen.has(int(event.id)) or not valid_id(event.get("actor_id")) or not finite_point(event.get("position")) or str(event.get("kind","")).is_empty():
			error="Malformed native action event.";return false
		event_seen[int(event.id)]=true;next_events.append(event.duplicate(true))
	event_sequence=event_head;events=next_events
	sequence=incoming;world_revision=revision;native_world=world.duplicate(true);players=next_players;actors=world.actors.duplicate(true)
	return true
