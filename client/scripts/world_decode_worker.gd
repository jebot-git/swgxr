extends RefCounted
## A single persistent worker with one private input/result slot. No scene/GPU calls.
const MAX_FILE_BYTES := 32 * 1024 * 1024
const MAX_RESULT_BYTES := 64 * 1024 * 1024
const MAX_PUBLISH_TRIANGLES := 500000
var thread := Thread.new()
var mutex := Mutex.new()
var semaphore := Semaphore.new()
var job: Dictionary = {}
var result: Dictionary = {}
var busy := false
var stopping := false

func start() -> void:
	thread.start(_run)

func submit(request: Dictionary) -> bool:
	mutex.lock()
	if busy or stopping:
		mutex.unlock()
		return false
	job = request.duplicate()
	busy = true
	mutex.unlock()
	semaphore.post()
	return true

func take_result() -> Dictionary:
	mutex.lock()
	var value := result
	if not value.is_empty():
		result = {}
		busy = false
	mutex.unlock()
	return value

func is_busy() -> bool:
	mutex.lock()
	var value := busy
	mutex.unlock()
	return value

func shutdown() -> void:
	mutex.lock()
	stopping = true
	mutex.unlock()
	semaphore.post()
	if thread.is_started():
		thread.wait_to_finish()
	job.clear()
	result.clear()

func _run() -> void:
	var builder := SwgMeshBuilder.new()
	while true:
		semaphore.wait()
		mutex.lock()
		var stop := stopping
		var request := job
		job = {}
		mutex.unlock()
		if stop:
			return
		var start_us := Time.get_ticks_usec()
		var output := _decode(request, builder)
		output["job"] = request
		output["decode_ms"] = (Time.get_ticks_usec() - start_us) / 1000.0
		mutex.lock()
		result = output
		mutex.unlock()

func _decode(request: Dictionary, builder: SwgMeshBuilder) -> Dictionary:
	if request.kind == "publish":
		var triangle_count := 0
		for surface: Dictionary in request.surfaces:
			triangle_count += surface.get("faces",PackedVector3Array()).size()/3
			if triangle_count > MAX_PUBLISH_TRIANGLES:
				return {"error":"Combat snapshot triangle budget exceeded: "+str(request.key)}
		var geometry := SwgCombatCollision.new()
		geometry.set_geometry("prepared",request.surfaces,request.coverage,0) # Source-index tile publication owns coverage.
		var support := SwgGroundSupport.new()
		if not support.configure([{"transform":request.transform,"cells":request.definitions}]):
			return {"error":"Invalid authored floor data in chunk " + str(request.key)}
		return {"geometry":geometry,"support":support,"error":""}
	var file := FileAccess.open(str(request.path), FileAccess.READ)
	if file == null or file.get_length() > MAX_FILE_BYTES:
		return {"error": "Missing or oversized source file: " + str(request.path)}
	var text := file.get_as_text()
	var data = JSON.parse_string(text)
	if not data is Dictionary:
		return {"error": "Invalid source JSON: " + str(request.path)}
	if request.kind == "chunk":
		var definitions := {}
		for id: String in data.get("cells",{}):
			if not request.retained_cells.has(id): definitions[id] = data.cells[id]
		var classifier := SwgCellClassifier.new()
		classifier.configure(definitions)
		var entries: Array = []
		for source: Dictionary in data.get("instances",[]):
			if not request.retained_objects.has(str(int(source.get("object_id",-1)))):
				entries.append(source)
		entries.sort_custom(func(a,b): return _position(a.position).distance_squared_to(request.observer) < _position(b.position).distance_squared_to(request.observer))
		var installs: Array = []
		var meshes := {}
		for id: String in definitions: installs.append({"chunk":request.key,"floor":id})
		for source: Dictionary in entries:
			installs.append({"chunk":request.key,"entry":source})
			meshes[str(source.get("mesh",""))] = true
		return {"definitions":definitions,"classifier":classifier,"installs":installs,"meshes":meshes.keys(),"bytes":text.length()*4,"error":""}
	var surfaces: Array = data.get("surfaces", [])
	var prepared := builder.prepare_mesh(surfaces)
	if prepared.is_empty() or int(prepared.get("bytes", 0)) > MAX_RESULT_BYTES:
		return {"error": "Invalid or oversized source geometry: " + str(request.path)}
	var images := {}
	var texture_errors: Array = []
	var material_surfaces: Array = []
	var bytes := int(prepared.bytes)
	for surface: Dictionary in surfaces:
		# Keep only material descriptors; raw JSON geometry is released here.
		var material := {"color": surface.get("color", [0.73,0.61,0.44]), "alpha": surface.get("alpha", false), "texture": surface.get("texture", "")}
		material_surfaces.append(material)
		var path := str(material.texture)
		if path.is_empty():
			continue
		if not path.is_absolute_path():
			path = str(request.directory).path_join(path)
		if images.has(path):
			continue
		var image := Image.load_from_file(path)
		if image == null:
			texture_errors.append(path)
			continue
		image.generate_mipmaps()
		var image_bytes := image.get_data_size()
		if bytes + image_bytes > MAX_RESULT_BYTES:
			return {"error": "Decoded texture budget exceeded: " + str(request.path)}
		images[path] = image
		bytes += image_bytes
	return {"prepared":prepared,"surfaces":material_surfaces,"images":images,"bytes":bytes,"texture_errors":texture_errors,"error":""}

func _position(value: Array) -> Vector3:
	return Vector3(value[0],value[1],value[2])
