extends Node3D
## Source service geometry driven exclusively by current native discovery/state.
const Avatar = preload("res://scripts/avatar.gd")
const InventoryAssets = preload("res://scripts/inventory_assets.gd")
const MAX_SHUTTLES := 8
const MAX_DYNAMIC_TERMINALS := 64
const CULL_DISTANCE := 128.0
var catalog: Dictionary = {}
var directory := ""
var source_origin := Vector3.ZERO
var static_ids: Dictionary = {}
var shuttles: Dictionary = {}
var terminals: Dictionary = {}
var static_records: Dictionary = {}
var screens: Dictionary = {}
var models := InventoryAssets.new()
var observer := Vector3.ZERO
var errors: Array = []
var elapsed := 0.0
var last_snapshot := -100.0

func configure(origin: Vector3, path := "") -> void:
	reset()
	source_origin = origin
	if path.is_empty(): path = ProjectSettings.globalize_path("res://../runtime/assets/services/catalog.json")
	directory = path.get_base_dir()
	catalog = Avatar.read_json(path)
	for row in catalog.get("static_terminals", []):
		static_ids[str(row.id)] = true;static_records[str(row.id)]=row
	screens=Avatar.read_json(directory.path_join("screens.json")).get("templates",{})
	models.configure()

func reset() -> void:
	for entry in shuttles.values(): entry.actor.queue_free()
	for entry in terminals.values(): entry.node.queue_free()
	shuttles.clear()
	terminals.clear()
	static_ids.clear();static_records.clear();screens.clear()
	errors.clear()
	elapsed = 0.0
	last_snapshot = -100.0

func vec(value: Variant) -> Vector3:
	if not value is Array or value.size() != 3: return Vector3.INF
	return Vector3(float(value[0]), float(value[1]), float(value[2]))

func local_position(source: Vector3) -> Vector3:
	return Vector3(source.x-source_origin.x,source.y-source_origin.y,source_origin.z-source.z)

func source_position(local: Vector3) -> Array:
	return [local.x+source_origin.x,local.y+source_origin.y,source_origin.z-local.z]

func heading(row: Dictionary) -> float:
	return -float(row.get("heading_radians", 0.0))

func apply_snapshot(snapshot: Dictionary, observer_position: Vector3) -> void:
	observer = observer_position
	last_snapshot = elapsed
	var keep := {}
	for row: Dictionary in snapshot.get("shuttles", []):
		var id := str(row.get("id", ""))
		var p := vec(row.get("position", []))
		if id.is_empty() or not p.is_finite() or local_position(p).distance_to(observer)>CULL_DISTANCE: continue
		if keep.size() >= MAX_SHUTTLES: break
		var template := str(row.get("template", ""))
		if not catalog.get("races", {}).has(template):
			continue # Never substitute a guessed shuttle for unknown native art.
		keep[id] = true
		if not shuttles.has(id):
			var actor := Avatar.new()
			actor.name = "Core3Shuttle_"+id
			actor.catalog = catalog
			actor.catalog_directory = directory
			actor.tracking_mode = true # Generic character locomotion must not alter it.
			add_child(actor)
			var result: Dictionary = actor.configure(template,{"height":1.0})
			if not str(result.get("error", "")).is_empty():
				errors.append(result)
				actor.queue_free()
				keep.erase(id)
				continue
			actor.visual_root.transform = Transform3D.IDENTITY
			var descriptor: Dictionary = catalog.races[template]
			var attached: Dictionary = actor.equipment_attachments.attach(actor,descriptor.attachments,directory,false)
			actor.rigid_equipment = attached.items
			errors.append_array(attached.failures)
			if actor.animation_player != null: actor.animation_player.stop()
			shuttles[id] = {"actor":actor,"source":descriptor,"row":{},"phase":"","time":0.0,"sample_clock":0.0,"door_local":Vector3.INF,"rate":1.0}
		var entry: Dictionary = shuttles[id]
		entry.actor.position = local_position(p)
		entry.actor.rotation.y = heading(row)
		entry.row = row.duplicate(true)
		var phase := phase_for(row)
		if phase == "loop_sky" and entry.phase == "loop_ground": phase = "take_off"
		if phase == "loop_sky" and entry.phase == "take_off" and float(entry.time)<float(entry.source.clips.take_off.length): phase = "take_off"
		if phase != entry.phase:
			entry.phase = phase
			entry.time = float(row.get("phase_elapsed_seconds", 0.0))
			entry.rate = 1.0
			entry.door_local = Vector3.INF
			entry.sample_clock = 1.0
		if phase == "land" and float(row.get("landing_duration_seconds",0.0))>0.0:
			entry.rate = float(entry.source.clips.land.length)/float(row.landing_duration_seconds)
			entry.time = float(row.get("phase_elapsed_seconds",0.0))*float(entry.rate)
			entry.sample_clock = 1.0
		# Missing state means unavailable, never assume boarding on presence.
		entry.actor.visible = not phase.is_empty()
	for id in shuttles.keys():
		if not keep.has(id):
			shuttles[id].actor.queue_free()
			shuttles.erase(id)
	keep.clear()
	for row: Dictionary in snapshot.get("terminals", []):
		# Trainers reuse the authored ambient/native NPC, never a terminal mesh.
		if str(row.get("kind", "")) in ["trainer","vendor","recruiter"]: continue
		var id := str(row.get("id", ""))
		if id.is_empty() or static_ids.has(id): continue
		var p := vec(row.get("position", []))
		if not p.is_finite() or local_position(p).distance_to(observer)>CULL_DISTANCE: continue
		if keep.size() >= MAX_DYNAMIC_TERMINALS: break
		keep[id] = true
		if not terminals.has(id):
			var template := str(row.get("template", ""))
			if template.is_empty() and str(row.get("kind", "")) == "travel": template = "object/tangible/terminal/terminal_travel.iff"
			var mesh: ArrayMesh = models.model(template)
			if mesh == null: continue
			var node := MeshInstance3D.new()
			node.mesh = mesh # Source meters/origin: no inventory preview centering.
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			node.name = "Core3Terminal_"+id
			add_child(node)
			terminals[id] = {"node":node}
		terminals[id].node.position = local_position(p)
		terminals[id].node.rotation.y = heading(row)
	for id in terminals.keys():
		if not keep.has(id):
			terminals[id].node.queue_free()
			terminals.erase(id)
	advance(0.0)

func phase_for(row: Dictionary) -> String:
	if bool(row.get("boarding", false)): return "loop_ground"
	if bool(row.get("is_landing", false)): return "land"
	var state := str(row.get("state", ""))
	if state in ["landing", "land"]: return "land"
	if state in ["departing", "take_off", "takeoff"]: return "take_off"
	if state in ["away", "flying", "sky"]: return "loop_sky"
	if bool(row.get("landed", false)): return "loop_ground"
	if row.has("landed"): return "loop_sky"
	return ""

func advance(delta: float) -> void:
	elapsed += maxf(delta, 0.0)
	for entry in shuttles.values():
		entry.time += maxf(delta,0.0)*float(entry.rate)
		entry.sample_clock += maxf(delta,0.0)
		if entry.phase.is_empty() or entry.sample_clock < 0.05: continue
		entry.sample_clock = 0.0
		var clip: Dictionary = entry.source.clips.get(entry.phase,{})
		sample(entry.actor.skeleton,clip,float(entry.time))

func sample(skeleton: Skeleton3D, clip: Dictionary, seconds: float) -> void:
	var duration := maxf(float(clip.get("length",0.1)),0.001)
	var time := fmod(seconds,duration) if bool(clip.get("loop",false)) else clampf(seconds,0.0,duration)
	for track: Dictionary in clip.get("tracks",[]):
		var bone := skeleton.find_bone(str(track.get("name","")))
		if bone < 0: continue
		var positions: Array = track.get("positions",[])
		if not positions.is_empty():
			var keys := neighbors(positions,time)
			var a: Array = keys[0]; var b: Array = keys[1]
			skeleton.set_bone_pose_position(bone,Vector3(a[1],a[2],a[3]).lerp(Vector3(b[1],b[2],b[3]),float(keys[2])))
		var rotations: Array = track.get("rotations",[])
		if not rotations.is_empty():
			var keys := neighbors(rotations,time)
			var a: Array = keys[0]; var b: Array = keys[1]
			skeleton.set_bone_pose_rotation(bone,Quaternion(a[1],a[2],a[3],a[4]).normalized().slerp(Quaternion(b[1],b[2],b[3],b[4]).normalized(),float(keys[2])))
	skeleton.force_update_all_bone_transforms()

func neighbors(keys: Array, time: float) -> Array:
	var lo := 0
	var hi := keys.size()-1
	while lo < hi:
		var mid := (lo+hi+1)/2
		if float(keys[mid][0])<=time: lo=mid
		else: hi=mid-1
	var next := mini(lo+1,keys.size()-1)
	var span := float(keys[next][0])-float(keys[lo][0])
	return [keys[lo],keys[next],clampf((time-float(keys[lo][0]))/span,0.0,1.0) if span>0.000001 else 0.0]

func boarding_rows() -> Array:
	var rows: Array = []
	if elapsed-last_snapshot > 5.0: return rows # Stale discovery cannot open a gate.
	for entry in shuttles.values():
		var row: Dictionary = entry.row.duplicate(true)
		if not bool(row.get("boarding",false)): continue
		var bone: String = str(entry.source.get("door_bone",""))
		var index: int = entry.actor.skeleton.find_bone(bone) if not bone.is_empty() else -1
		if index>=0:
			var door: Transform3D = entry.actor.skeleton.global_transform * entry.actor.skeleton.get_bone_global_pose(index)
			var world: Vector3 = door.origin
			# The source hardpoint is the hinge, above the traversable ramp.
			# Use the lowest authored ramp vertices as the walking threshold.
			for attached: Dictionary in entry.actor.rigid_equipment if not entry.door_local.is_finite() else []:
				if str(attached.source.bone) != bone: continue
				var points: Array[Vector3] = []
				var low := INF
				for surface in range(attached.instance.mesh.get_surface_count()):
					var vertices: PackedVector3Array = attached.instance.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
					for vertex in vertices:
						var point: Vector3 = door * vertex
						points.append(point)
						low = minf(low,point.y)
				var total := Vector3.ZERO
				var count := 0
				for point in points:
					if point.y <= low+0.08:
						total += point
						count += 1
				if count>0: world=total/float(count)
				entry.door_local = entry.actor.to_local(world)
			if entry.door_local.is_finite(): world=entry.actor.to_global(entry.door_local)
			row["door_position"] = source_position(to_local(world))
			row["door_source"] = bone
		elif row.has("collector_position"):
			row["door_position"] = row.collector_position
			row["door_source"] = "native_ticket_collector"
		else: continue
		rows.append(row)
	return rows

func statistics() -> Dictionary:
	return {"shuttles":shuttles.size(),"dynamic_terminals":terminals.size(),"source_static_terminals":static_ids.size(),"errors":errors,"native_snapshot_age":elapsed-last_snapshot}

func static_record(record: Dictionary) -> Dictionary:
	var id:=str(record.get("id",""))
	if static_records.has(id):return static_records[id]
	var point:=vec(record.get("position"))
	if not point.is_finite():return {}
	for candidate: Dictionary in static_records.values():
		if candidate.get("kind")==record.get("kind") and vec(candidate.get("position")).distance_squared_to(point)<.25:
			return candidate
	return {}

func terminal_basis(record: Dictionary) -> Basis:
	var original:=static_record(record)
	var rotation: Array=original.get("godot_quaternion",[])
	if rotation.size()==4:return Basis(Quaternion(rotation[0],rotation[1],rotation[2],rotation[3])).orthonormalized()
	return Basis(Vector3.UP,heading(record))

func screen_offsets(record: Dictionary) -> Array:
	var template:=str(record.get("template",""))
	if template.is_empty():template=str(static_record(record).get("template",""))
	var result: Array=[]
	for screen: Dictionary in screens.get(template.replace("/shared_","/"),[]):
		var center:=vec(screen.get("center"));var normal:=vec(screen.get("normal")).normalized()
		if not center.is_finite() or not normal.is_finite() or normal.length_squared()<.5:continue
		var up:=Vector3.UP.slide(normal).normalized()
		result.append(Transform3D(Basis(up.cross(normal).normalized(),up,normal),center+normal*.055))
	if result.is_empty():
		# Unavailable screen data: fixed facade-relative presentation, never world-axis/billboard.
		result.append(Transform3D(Basis(Vector3.LEFT,Vector3.UP,Vector3.FORWARD),Vector3(0,1.3,-.4)))
	return result
