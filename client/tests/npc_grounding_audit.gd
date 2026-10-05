extends SceneTree
func _initialize()->void:call_deferred("run")
func run()->void:
	var evaluator:=SwgTerrainEvaluator.new();evaluator.configure(JSON.parse_string(FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://../runtime/assets/terrain/tatooine.json"))))
	var rows:Array=[];scan(JSON.parse_string(FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://../runtime/evidence/core2/remote-starport-npcs.json"))),rows)
	var errors:Array=[]
	for r:Dictionary in rows:
		if str(r.get("building_id","0"))!="0" or int(r.get("posture",0))!=0:continue
		var height:float=evaluator.sample_height(float(r.position[0]),float(r.position[2]));var difference:float=height-float(r.position[1])
		errors.append({"id":r.id,"name":r.name,"template":r.template,"position":r.position,"terrain_height":height,"penetration":difference})
	errors.sort_custom(func(a,b):return a.penetration>b.penetration)
	FileAccess.open(ProjectSettings.globalize_path("res://../runtime/evidence/alpha-grounding-regression/native-terrain-audit.json"),FileAccess.WRITE).store_string(JSON.stringify(errors,"  "))
	print("ROWS ",errors.size());print(JSON.stringify(errors.slice(0,15)));quit()
func scan(value:Variant,rows:Array)->void:
	if value is Dictionary:
		if value.get("kind","")=="creature" and value.has("position"):rows.append(value)
		for v:Variant in value.values():scan(v,rows)
	elif value is Array:
		for v:Variant in value:scan(v,rows)
