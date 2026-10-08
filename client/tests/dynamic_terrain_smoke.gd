extends SceneTree
const Stream=preload("res://scripts/terrain_stream.gd")
const Policy=preload("res://scripts/terrain_modifications.gd")
var checks:=0
func check(value:bool,label:String)->void:
	checks+=1
	assert(value,label)
func _initialize()->void:call_deferred("run")
func run()->void:
	create_timer(90).timeout.connect(func():quit(2))
	var source:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/assets/terrain/tatooine.json"))
	var catalog:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../runtime/assets/terrain_modifications/catalog.json"))
	var original:=SwgTerrainEvaluator.new();check(original.configure(source),"Original planet evaluator loads")
	var center:=Vector2(-1080,-4330)
	var height:=original.sample_height(center.x,center.y)
	var camp:Dictionary={"id":"test-camp","template":"object/building/poi/scout_camp_s0.iff","position":[center.x,height,center.y],"heading_radians":.7}
	var modifications:=Policy.resolve([camp],catalog)
	check(modifications.size()==1 and modifications[0].bounds.size.x>30,"Original camp boundary extracted; no guessed platform")
	var changed:=source.duplicate(false);changed.modifications=modifications
	var modified:=SwgTerrainEvaluator.new();check(modified.configure(changed),"Placed layer configures immutable evaluator")
	for x in [-8.0,0.0,8.0]:
		for z in [-8.0,0.0,8.0]:check(absf(modified.sample_height(center.x+x,center.y+z)-height)<.001,"Camp support is level inside authored feather boundary")
	check(absf(modified.sample_height(center.x+25,center.y)-original.sample_height(center.x+25,center.y))<.001,"Unmodified ground outside camp remains exact")
	var camp_profiles:Array=[]
	for template:String in catalog.templates:
		var row:=camp.duplicate(true);row.template=template
		var profile:=source.duplicate(false);profile.modifications=Policy.resolve([row],catalog)
		var sampler:=SwgTerrainEvaluator.new();check(sampler.configure(profile),"Original camp tier layer configures")
		var original_min:=INF;var original_max:=-INF;var maximum_error:=0.0
		for x in [-8.0,0.0,8.0]:
			for z in [-8.0,0.0,8.0]:
				var base:=original.sample_height(center.x+x,center.y+z)
				original_min=minf(original_min,base);original_max=maxf(original_max,base)
				maximum_error=maxf(maximum_error,absf(sampler.sample_height(center.x+x,center.y+z)-height))
		check(maximum_error<.001,"All original camp tiers level their central support")
		check(absf(sampler.sample_height(center.x+80,center.y)-original.sample_height(center.x+80,center.y))<.001,"Every camp tier preserves distant source terrain")
		camp_profiles.append({"template":template,"original_height_span":original_max-original_min,"level_error":maximum_error})
	check(Policy.resolve([{"id":"x","template":"missing","position":[0,0,0]}],catalog).is_empty(),"Unknown templates cannot invent terrain layers")
	# Rectangle rotation exercises the local-to-source transform independently of
	# circular camp assets. Original planet rules still supply outside heights.
	var flat:Dictionary={"fractals":[],"layers":[{"affectors":[{"type":"AHCN","height":3}]}],"modifications":[{"position":[100,12,200],"heading_radians":PI/2,"layers":[{"boundaries":[{"type":"BREC","rect":[-8,-2,8,2]}],"affectors":[{"type":"AHCN","height":0}]}]}]}
	var rotated:=SwgTerrainEvaluator.new();check(rotated.configure(flat),"Rotated layer accepted")
	check(rotated.sample_height(100,206)==12 and rotated.sample_height(106,200)==3,"Authored rectangle rotates with structure heading")
	var stream:=Stream.new();root.add_child(stream)
	check(stream.configure("res://../runtime/assets/terrain/tatooine.json",Vector3.ZERO),"Actual terrain worker starts")
	var solver:=SwgXRStepSolver.new();solver.configure_terrain(stream.evaluator,Vector3.ZERO,1.3);stream.bind_movement_solver(solver)
	var location:=Vector3(center.x,height,-center.y)
	stream.update_observer(location)
	while not stream.ready_near(location,0):await process_frame
	var revision:=stream.modification_revision
	stream.set_modification_group("camps",[camp])
	check(stream.modification_revision==revision+1 and not stream.ready_near(location,0),"Placement invalidates affected collision before allowing movement")
	stream.set_modification_group("camps",[camp])
	check(stream.modification_revision==revision+1,"Repeated native snapshots do not rebuild unchanged camps")
	while not stream.ready_near(location,0):await process_frame
	for _i in 3:await physics_frame
	var world:World3D=stream.get_world_3d()
	var ray:=PhysicsRayQueryParameters3D.create(location+Vector3.UP*30,location-Vector3.UP*30,2)
	var hit:=world.direct_space_state.intersect_ray(ray)
	check(not hit.is_empty() and absf(float(hit.position.y)-height)<.002,"Rebuilt rendered chunk collision uses camp plane")
	var body:=CharacterBody3D.new();root.add_child(body);body.position=location
	var support:=solver.terrain_support(body,location,50,50)
	check(support.get("valid",false) and absf(float(support.height)-height)<.002,"Existing locomotion solver follows replacement evaluator")
	stream.set_modification_group("camps",[])
	while not stream.ready_near(location,0):await process_frame
	check(absf(stream.evaluator.sample_height(center.x+8,center.y)-original.sample_height(center.x+8,center.y))<.001,"Camp removal restores exact source terrain")
	body.queue_free();stream.queue_free();await process_frame
	var report:Dictionary={"passed":true,"checks":checks,"camp_profiles":camp_profiles,"renderer":"headless dummy","headset_validated":false,"source":"Original poi_small.lay, poi_medium.lay and actual Tatooine terrain"}
	FileAccess.open("res://../runtime/evidence/core5-dynamic-terrain.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "));print(JSON.stringify(report));quit()
