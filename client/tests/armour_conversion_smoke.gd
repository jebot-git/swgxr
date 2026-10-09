extends SceneTree
const Model=preload("res://combat/armour_model.gd")
const State=preload("res://combat/weapon_state.gd")
var checks:=0
func check(value:bool,message:String)->void:
	checks+=1
	if not value:push_error(message);quit(1);assert(value,message)
func _initialize()->void:
	var types:Dictionary={1:"kinetic",2:"energy",4:"blast",8:"stun",16:"lightsaber",32:"heat",64:"cold",128:"acid",256:"electricity"}
	var cases:Array=JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/evidence/armour-model-cases.json"))
	for row:Array in cases:
		var profile:=Model.weapon(types[int(row[0])],int(row[1]))
		var resistance:Dictionary={profile.base_type:row[2],profile.element_type:row[3]}
		check(absf(Model.damage(1000,profile,resistance)-float(row[4]))<0.001,"Native/client damage parity")
	var catalog:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/assets/combat/catalog.json"))
	var state:=State.new()
	var data:Dictionary=catalog.weapons.pistol_cdef.duplicate(true)
	check(state.configure(data,data.core3.certificationsRequired),"Weapon config")
	var baseline:=state.effective_rpm()
	state.armour_scales={"output_scale":0.9,"recovery_scale":0.9}
	check(is_equal_approx(state.effective_rpm(),baseline*.9),"Live armour changes RoF")
	state.rounds=0;state.reload()
	check(is_equal_approx(state.reload_until-state.clock,float(data.reload_seconds)/.9),"Armour slows recharge without reducing Capacity")
	state.profile.rpm*=.9;state.profile.armour_scales={"output_scale":.9,"recovery_scale":.9}
	check(is_equal_approx(state.effective_rpm(),baseline*.9),"Native captured penalty is not applied twice")
	state.armour_scales={"output_scale":1.0,"recovery_scale":1.0}
	check(is_equal_approx(state.effective_rpm(),baseline),"Unequip removes penalty immediately")
	print(JSON.stringify({"test":"armour_conversion","checks":checks,"passed":true,"native_core3_executed":false,"hardware_tested":false}))
	quit()
