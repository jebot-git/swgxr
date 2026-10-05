extends SceneTree
const Assets=preload("res://scripts/inventory_assets.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	var assets:=Assets.new();assets.configure(ProjectSettings.globalize_path("res://../runtime/assets/vehicles/catalog.json"))
	var failures:Array=[];var models:Array=[]
	for template:String in assets.catalog.get("items",{}):
		var descriptor:Dictionary=assets.descriptor(template);var mesh:=assets.model(template)
		if mesh==null or mesh.get_surface_count()==0 or mesh.get_aabb().size.length()<1:failures.append("Missing original vehicle geometry: "+template);continue
		if descriptor.get("seats",[]).is_empty() or descriptor.get("controls",[]).size()!=2:failures.append("Missing original vehicle saddle metadata: "+template)
		var shared:=template.get_base_dir()+"/shared_"+template.get_file()
		if assets.model(shared)!=mesh:failures.append("Native/shared alias does not resolve exact model: "+template)
		models.append({"template":template,"surfaces":mesh.get_surface_count(),"bounds":mesh.get_aabb().size,"source_appearance":descriptor.get("appearance","")})
	if models.size()!=6:failures.append("Expected all six supported original source vehicle families")
	if assets.model("object/mobile/vehicle/unknown_vehicle.iff")!=null:failures.append("Unknown vehicle silently substituted")
	var report:Dictionary={"passed":failures.is_empty(),"failures":failures,"models":models,"renderer":"headless dummy","headset_validated":false,"native_call_tested":false}
	FileAccess.open(ProjectSettings.globalize_path("res://../runtime/evidence/core2/vehicle-assets-smoke.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  "));print(JSON.stringify(report));quit(0 if failures.is_empty() else 1)
