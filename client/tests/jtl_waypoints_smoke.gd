extends SceneTree
const SectorMap=preload("res://space/sector_map.gd")
class Sector extends Node3D:
	var visual_ship_pose:=Transform3D.IDENTITY
var failures:Array[String]=[]
var checks:=0
func check(value:bool,message:String)->void:
	checks+=1
	if not value:failures.append(message);push_error(message)
func _initialize()->void:call_deferred("run")
func run()->void:
	var map:=SectorMap.new();root.add_child(map);map.size=Vector2(800,600)
	var sector:Dictionary={"source_zone":"space_tatooine","name":"Tatooine","markers":[],"navigation":[]}
	var q:=Quaternion(Vector3.UP,PI/2)
	var ship:Dictionary={"position":[200,300,400],"quaternion":[q.x,q.y,q.z,q.w]}
	var first:Dictionary={"id":"123","kind":"waypoint","position":[1200,800,-400],"name":"Patrol"}
	map.set_sector(sector,ship,[first]);map.center_on_player()
	check(map.sector_forward.is_equal_approx(Vector3.RIGHT),"Map heading follows native ship quaternion")
	check(map.world_to_screen(map.sector_ship).is_equal_approx(map.size*.5),"Center on ship uses all native coordinates")
	var point:=Vector3(1200,800,-400)
	var expected:Array[Vector2]=[Vector2(1000,-800),Vector2(1000,500),Vector2(-800,500)]
	for projection in range(3):
		map.projection=projection;map.center_on_player()
		var delta:Vector2=expected[projection]
		check(map.world_to_screen(point).is_equal_approx(map.size*.5+Vector2(delta.x,-delta.y)*map.pixels_per_meter()),"Waypoint respects sector projection %d"%projection)
	map.set_sector(sector,ship,[{"id":"124","kind":"waypoint","position":[-900,600,700]}])
	check(map.contacts.size()==1 and map.contacts[0].id=="124","Objective replacement removes previous map marker")
	map.set_sector({"source_zone":"space_naboo"},ship,[])
	check(map.contacts.is_empty() and map.center==Vector2.ZERO and map.zoom==1,"Sector switch clears supplied markers and resets projection center")
	map.set_sector({}, {}, [])
	check(map.sector.is_empty() and map.contacts.is_empty(),"Landing restores ground map without stale space markers")
	var scene:=Sector.new();root.add_child(scene)
	var hud:=preload("res://space/waypoint_hud.gd").new();root.add_child(hud)
	var head:=Transform3D.IDENTITY
	hud.update_view(scene,[{"id":"1","name":"Objective","position":[0,0,1000]}],head)
	check(hud.markers.size()==1 and not hud.markers["1"].get_meta("outside"),"Forward waypoint is drawn from native XYZ")
	check(hud.markers["1"].get_node("Label").text=="Objective\n1000 m","Waypoint uses ship distance in metres")
	hud.update_view(scene,[{"id":"2","name":"Behind","position":[0,0,-1000]}],head)
	check(hud.markers.size()==1 and hud.markers.has("2") and hud.markers["2"].get_meta("outside"),"Behind-head objective replaces old marker with edge arrow")
	check(hud.markers["2"].position.is_finite() and hud.markers["2"].position.z<0,"Directly behind arrow remains stable in front of head")
	hud.update_view(scene,[{"id":"3","position":[0,0,50]}],head)
	check(hud.markers.is_empty(),"Original SWG 50m indicator suppression")
	scene.visual_ship_pose=Transform3D(Basis(Vector3.UP,PI/2),Vector3(100,200,-300))
	head=Transform3D(Basis(Vector3.UP,.4),Vector3(0,1,0))
	hud.update_view(scene,[{"id":"4","position":[100,200,1300]}],head)
	check(hud.markers["4"].get_node("Label").text.ends_with("1000 m"),"Turned ship retains true three-dimensional waypoint distance")
	hud.clear();check(hud.markers.is_empty() and not hud.visible,"Landing/disconnect cleanup clears all guidance")
	hud.queue_free();scene.queue_free()
	map.queue_free();await process_frame
	print(JSON.stringify({"passed":failures.is_empty(),"checks":checks,"failures":failures,"validation":"Headless map logic; no GPU or headset validation"}))
	quit(0 if failures.is_empty() else 1)
