extends SceneTree
## Client allocation and presentation fixtures; does not simulate native genetics.
var checks:=0
var errors:Array[String]=[]
func check(value:bool,message:String)->void:
	checks+=1
	if not value:errors.append(message);push_error(message)
func _initialize()->void:call_deferred("run")
func run()->void:
	var craft:=preload("res://scripts/crafting_controller.gd").new()
	root.add_child(craft);craft.set_process(false)
	var definitions:Array=[];var inventory:Array=[]
	for i in range(5):
		definitions.append({"name":"Profile "+str(i),"type":"dna","quantity":1,"kind":2,"optional":false})
		inventory.append({"id":str(100+i),"quantity":1,"slots":[0,1,2,3,4],"quality":[{"name":"Hardiness","value":0.7,"raw":700,"slot":0},{"name":"Fortitude","value":0.4,"raw":400,"slot":0},{"name":"Dexterity","value":0.8,"raw":800,"slot":1}]})
		var cube:=MeshInstance3D.new();cube.mesh=BoxMesh.new();cube.add_child(Label3D.new());craft.add_child(cube);craft.slots.append(cube);craft.allocations.append([])
	craft.state={"stage":2,"schematic":{"slots":definitions},"inventory":inventory}
	check(craft.place_resource(0,0),"First DNA sample fills physique profile")
	check(not craft.place_resource(0,1),"A single sample cannot be consumed by two profiles")
	check(not craft.ready_to_assemble(),"Four empty profiles prevent assembly")
	for i in range(1,5):check(craft.place_resource(i,i),"Distinct sample fills profile "+str(i))
	check(craft.ready_to_assemble(),"Five distinct samples permit native assembly request")
	await process_frame
	craft.selected_resource=0;craft.update_slots();await process_frame
	check(craft.slots[0].get_children().filter(func(n):return n.has_meta("quality_bar")).size()==2,"Physique displays its two original DNA attribute bars")
	check(craft.slots[1].get_children().filter(func(n):return n.has_meta("quality_bar")).size()==1,"Prowess does not inherit physique bars")
	check("Hardiness 700" in craft.slots[0].get_child(0).text and not "Dexterity" in craft.slots[0].get_child(0).text,"Native DNA readings are labelled on their matching profile")
	check(inventory[0].quantity==1,"Client allocation does not consume DNA")
	craft.free()
	var report:Dictionary={"passed":errors.is_empty(),"checks":checks,"errors":errors,"mocked_data":true,"live_core3":false,"gpu_validation":false}
	FileAccess.open("res://../runtime/evidence/bioengineer-crafting-smoke.json",FileAccess.WRITE).store_string(JSON.stringify(report));print(JSON.stringify(report));quit(0 if errors.is_empty() else 1)
