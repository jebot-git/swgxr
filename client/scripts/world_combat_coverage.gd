extends RefCounted
## Coverage proves the complete source index was loaded, including empty ground.
## Object AABBs select dependencies; they never define holes in empty-space coverage.
const MAX_TILES:=128
var chunk_size:=256.0
var descriptors:Dictionary={}
var dependencies:Dictionary={}
var active:Dictionary={}
var prefix:=""
func configure(manifest:Dictionary,key_prefix:String)->void:
	chunk_size=float(manifest.get("chunk_size",256))
	descriptors=manifest.get("chunks",{});prefix=key_prefix;dependencies.clear();active.clear()
func bounds(key:Vector2i)->AABB:
	return AABB(Vector3(key.x*chunk_size,-100000,key.y*chunk_size),Vector3(chunk_size,200000,chunk_size))
func required_chunks(key:Vector2i)->Array:
	if dependencies.has(key):return dependencies[key]
	var tile:=bounds(key);var required:Array=[]
	for id:String in descriptors:
		var entry:Dictionary=descriptors[id];var low:Array=entry.bounds_min;var high:Array=entry.bounds_max
		# Inclusive edges are conservative for geometry straddling adjacent tiles.
		if float(high[0])>=tile.position.x and float(low[0])<=tile.end.x and float(high[2])>=tile.position.z and float(low[2])<=tile.end.z:required.append(id)
	dependencies[key]=required
	return required
func refresh(collision:SwgCombatCollision,chunks:Dictionary,observers:Array,transform:Transform3D)->void:
	var wanted:Dictionary={}
	for observer:Vector3 in observers:
		var local:=transform.affine_inverse()*observer
		var center:=Vector2i(floori(local.x/chunk_size),floori(local.z/chunk_size))
		for z in range(center.y-1,center.y+2):
			for x in range(center.x-1,center.x+2):
				if wanted.size()<MAX_TILES:wanted[Vector2i(x,z)]=true
	var ready:Dictionary={}
	for key:Vector2i in wanted:
		var complete:=true
		for id:String in required_chunks(key):
			if not chunks.has(id) or not chunks[id].get("published",false):complete=false;break
		if complete:ready[key]=true
	for key:Vector2i in active:
		if not ready.has(key):collision.remove_geometry(prefix+str(key))
	for key:Vector2i in ready:
		if not active.has(key):collision.set_geometry(prefix+str(key),[],transform*bounds(key),1)
	active=ready
	for key in dependencies.keys():
		if not wanted.has(key):dependencies.erase(key)
func clear(collision:SwgCombatCollision)->void:
	for key:Vector2i in active:collision.remove_geometry(prefix+str(key))
	active.clear();dependencies.clear()
