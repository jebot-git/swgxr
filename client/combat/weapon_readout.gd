extends Node3D
## Capacity and firing mode only; fixed to the original weapon's rear face.
const SEMI_COLOR=Color("319eff")
const RAPID_COLOR=Color("ff3946")
var fill:MeshInstance3D
var led:MeshInstance3D
var fill_material:StandardMaterial3D
var led_material:StandardMaterial3D
var bar_width:=.07
var bar_left:=0.0
var charge_capacity:=0
var native_charge_baseline:=false
var report:Dictionary={}
func material(color:Color)->StandardMaterial3D:
	var result:=StandardMaterial3D.new();result.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	result.albedo_color=color;result.emission_enabled=true;result.emission=color;result.emission_energy_multiplier=.5
	return result
func quad(size:Vector2,point:Vector3,color:Color)->MeshInstance3D:
	var mesh:=MeshInstance3D.new();add_child(mesh);var shape:=QuadMesh.new();shape.size=size;mesh.mesh=shape
	mesh.position=point;mesh.material_override=material(color);mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mesh
func configure(bounds:AABB)->void:
	name="WeaponCapacityAndMode"
	var width:=clampf(bounds.size.x*.85,.065,.12)
	# Local -Z is the established muzzle direction. Tilt the rear face upward
	# toward the holder; never billboard or alter the gun/controller pose.
	rotation.x=deg_to_rad(-30)
	position=Vector3(bounds.get_center().x,bounds.end.y-.014,bounds.end.z+.012)
	quad(Vector2(width,.022),Vector3.ZERO,Color("071a25"))
	bar_width=width-.019;bar_left=-width*.5+.004
	quad(Vector2(bar_width,.009),Vector3(bar_left+bar_width*.5,0,.001),Color("153f50"))
	fill=quad(Vector2(bar_width,.009),Vector3(bar_left+bar_width*.5,0,.002),Color("72edff"));fill_material=fill.material_override
	led=MeshInstance3D.new();add_child(led);var dot:=SphereMesh.new();dot.radius=.0035;dot.height=.007;dot.radial_segments=12;dot.rings=6;led.mesh=dot
	led.position=Vector3(width*.5-.006,0,.003);led.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	led_material=material(SEMI_COLOR);led.material_override=led_material;visible=false
func update_state(state:RefCounted,held:bool)->void:
	visible=held and not state.is_melee()
	if state.is_melee():return
	var capacity:=maxi(1,int(state.profile.capacity))
	var remaining:=int(state.rounds)
	if state.profile.get("charge_limited",false):
		# Consumable uses are native counts, independent of magazine statistics.
		var native_charges:=int(state.profile.get("charges",-1))
		if native_charges>=0:
			if not native_charge_baseline:charge_capacity=0;native_charge_baseline=true
			charge_capacity=maxi(charge_capacity,native_charges)
			remaining=mini(remaining,native_charges)
		else:charge_capacity=maxi(charge_capacity,remaining)
		capacity=maxi(1,charge_capacity)
	var fraction:=clampf(float(remaining)/capacity,0,1)
	fill.visible=fraction>0
	fill.scale.x=maxf(.0001,fraction);fill.position.x=bar_left+bar_width*fraction*.5
	var color:=SEMI_COLOR if state.mode=="semi" else RAPID_COLOR
	# Burst has three red flashes so three supported modes remain distinguishable
	# using only the requested two LED colors, without extra labels or symbols.
	var bright:bool=state.mode!="burst" or (fmod(float(state.clock),1.2)<.54 and fmod(float(state.clock),.18)<.10)
	led_material.albedo_color=color if bright else color*.18
	led_material.emission=color if bright else Color.BLACK
	report={"fraction":fraction,"capacity":capacity,"remaining":remaining,"mode":str(state.mode),"mode_color":color,"mode_bright":bright,"cooling":state.reload_until>=0}
