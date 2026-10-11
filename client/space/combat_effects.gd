extends Node3D
## Visualizes confirmed Core3 projectiles/contacts; never performs hit detection.
var seen:Dictionary={}
var effects:Array[Dictionary]=[]
var missiles:Dictionary={}
var missile_receipts:Dictionary={}
func receive(events:Array)->void:
	for event:Dictionary in events:
		var id:=str(event.get("id",""))
		if id.is_empty() or seen.has(id):continue
		seen[id]=Time.get_ticks_msec()
		if event.get("kind")=="missile":receive_missile(event);continue
		var age:=float(event.get("age_seconds",0))
		var point:Array=event.get("position",[])
		if point.size()!=3:continue
		var position:=Vector3(point[0],point[1],-point[2])
		var direction:=Vector3.ZERO;var duration:=.35
		var shape:PrimitiveMesh
		if event.get("kind")=="projectile":
			var v:Array=event.get("direction",[])
			if v.size()!=3:continue
			direction=Vector3(v[0],v[1],-v[2]).normalized()*float(event.get("speed",0))
			duration=float(event.get("range",0))/maxf(1,direction.length())
			if age>=duration:continue
			var bolt:=CylinderMesh.new();bolt.top_radius=.12;bolt.bottom_radius=.12;bolt.height=8;shape=bolt
		else:
			if age>=duration:continue
			var flash:=SphereMesh.new();flash.radius=2;flash.height=4;shape=flash
		var node:=MeshInstance3D.new();node.mesh=shape;node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var material:=StandardMaterial3D.new();material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;material.albedo_color=Color(1,.4,.12);node.material_override=material
		add_child(node)
		if direction.length_squared()>0:
			var axis:=direction.normalized();var side:=axis.cross(Vector3.UP)
			if side.length_squared()<.01:side=axis.cross(Vector3.RIGHT)
			side=side.normalized();node.basis=Basis(side,axis,side.cross(axis)).orthonormalized()
		effects.append({"node":node,"position":position,"velocity":direction,"age":age,"duration":duration})
	for id in seen.keys():
		if Time.get_ticks_msec()-int(seen[id])>10000:seen.erase(id)
func advance(delta:float,ship_pose:Transform3D)->void:
	transform=ship_pose.affine_inverse()
	for key in missiles.keys():
		var m:Dictionary=missiles[key];m.age+=delta
		if m.age>1.0:m.node.queue_free();missiles.erase(key);continue
		m.node.position=m.node.position.lerp(m.destination,1.0-exp(-delta/.08))
	for key in missile_receipts.keys():
		if Time.get_ticks_msec()-int(missile_receipts[key].stamp)>10000:missile_receipts.erase(key)
	for i in range(effects.size()-1,-1,-1):
		var e:Dictionary=effects[i];e.age+=delta
		if e.age>=e.duration:e.node.queue_free();effects.remove_at(i);continue
		e.node.position=e.position+e.velocity*e.age

func receive_missile(event:Dictionary)->void:
	var key:=str(event.get("ship_id",""))+":"+str(event.get("missile_id",""))
	var receipt:=int(event.get("id",0));var prior:Dictionary=missile_receipts.get(key,{})
	# Snapshots arrive newest-first and overlap. Never resurrect a finished missile.
	if receipt<=int(prior.get("id",0)):return
	missile_receipts[key]={"id":receipt,"stamp":Time.get_ticks_msec()}
	if event.get("done",false):
		if missiles.has(key):missiles[key].node.queue_free();missiles.erase(key)
		return
	var age:=float(event.get("age_seconds",0));var point:Array=event.get("position",[])
	if age>1.0 or point.size()!=3:return
	var destination:=Vector3(point[0],point[1],-point[2])
	if not missiles.has(key):
		var node:=MeshInstance3D.new();var shape:=SphereMesh.new();shape.radius=.7;shape.height=1.4;node.mesh=shape
		var material:=StandardMaterial3D.new();material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;material.albedo_color=Color(1,.85,.4);node.material_override=material;node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node);node.position=destination;missiles[key]={"node":node,"destination":destination,"age":age}
	missiles[key].destination=destination;missiles[key].age=age
