extends SceneTree
const Controller=preload("res://chatter/controller.gd")
class Stage extends Node3D:
	var current_cell:Dictionary={"building_object_id":"0","cell_id":"0:0"}
class Player extends Node3D:
	var eye:Camera3D
	func get_camera()->Camera3D:return eye
class Entities extends Node3D:
	var actors:Dictionary={}
class Sync extends Node:
	var entities:Node3D
class Host extends Node3D:
	var active_planet:="tatooine"
	var world_ready:=true
	var loading_stage:=false
	var xr_requested:=false
	var xr_focused:=true
	var stage:Node3D
	var player:Node3D
	var multiplayer_sync:Node
	var live_combat:Node
var failures:Array=[]
var checks:=0
func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures.append(label);push_error(label)
func event(id:String="1",speaker:String="42")->Dictionary:return {"id":id,"actor_id":speaker,"zone":"tatooine","building_id":"0","cell_index":0,"language_key":"rodese","text":"Neeka vonn cha.","comprehension_before":0,"comprehension_after":2.5,"age_ms":0,"lifetime_ms":6000}
func _initialize()->void:call_deferred("run")
func run()->void:
	var host:=Host.new();root.add_child(host);host.stage=Stage.new();host.add_child(host.stage);host.player=Player.new();host.add_child(host.player)
	host.player.eye=Camera3D.new();host.player.add_child(host.player.eye);host.player.eye.position=Vector3(0,1.7,4);host.player.eye.current=true
	host.multiplayer_sync=Sync.new();host.add_child(host.multiplayer_sync);host.multiplayer_sync.entities=Entities.new();host.add_child(host.multiplayer_sync.entities)
	var actor:=preload("res://combat/live_actor.gd").new();host.add_child(actor)
	var ok:bool=actor.configure({"id":"42","kind":"creature","template":"object/mobile/dressed_commoner_tatooine_rodian_male_01.iff","dead":false,"name":"Native fixture","health":100,"max_health":100,"scale":1.0},"fixture",RefCounted.new(),RefCounted.new(),ProjectSettings.globalize_path("res://../runtime/assets/ambient_npcs/catalog.json"));actor.set_process(false)
	host.multiplayer_sync.entities.actors["42"]=actor
	check(ok and is_instance_valid(actor.visual.skeleton),"Actual original NPC appearance and skeleton load")
	var original_meshes:Array[MeshInstance3D]=actor.visual.meshes
	var pending_meshes:Array[MeshInstance3D]=[]
	actor.visual.meshes=pending_meshes
	check(preload("res://chatter/head_anchor.gd").crown(actor)==null,"Skeleton without finished head geometry has no invented or nonfinite crown")
	var cached:Dictionary=actor.get_meta("speech_head");cached.cache_test=true
	check(preload("res://chatter/head_anchor.gd").crown(actor)==null and actor.get_meta("speech_head").get("cache_test",false),"Unchanged missing-head layout stays cached without repeated vertex scans")
	actor.visual.meshes=original_meshes
	var ready:Variant=preload("res://chatter/head_anchor.gd").crown(actor)
	check(ready is Vector3 and ready.is_finite() and not actor.get_meta("speech_head").has("cache_test"),"Original source head meshes attached to same skeleton invalidate unready crown cache")
	cached=actor.get_meta("speech_head");cached.cache_test=true
	preload("res://chatter/head_anchor.gd").crown(actor)
	check(actor.get_meta("speech_head").get("cache_test",false),"Unchanged ready source geometry reuses cached head bounds")
	var manager:=Controller.new();host.add_child(manager);manager.setup(host);manager.set_process(false)
	manager.accept({"sequence":1,"events":[event()],"languages":[{"id":1,"comprehension":2.5}]});manager._process(.01)
	check(manager.active.size()==1 and manager.active["42"].bubble.visible,"Native actor event creates visible bounded source-head bubble")
	var bubble:Node3D=manager.active["42"].bubble
	check(bubble.words.text=="Neeka vonn cha." and not bubble.words.no_depth_test and manager.statistics().viewports==0,"Server garbling is displayed unchanged with depth testing and no viewport/input layer")
	check(not actor.label.visible,"Visible speech temporarily suppresses overlapping native nameplate")
	var wide:=preload("res://chatter/bubble.gd").fit_text("W".repeat(200),36,3)
	var fitted:=wide.split("\n");var widths_ok:=true
	for line in fitted:widths_ok=widths_ok and preload("res://chatter/bubble.gd").FONT.get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,-1,36).x<=450
	check(fitted.size()==3 and widths_ok and wide.ends_with("…"),"Unbroken wide alien syllables fit three measured lines with ellipsis")
	check(preload("res://chatter/bubble.gd").FONT.get_height(36)*3*.003<.44 and bubble.words.autowrap_mode==TextServer.AUTOWRAP_OFF,"Measured text height fits fixed panel without secondary renderer wrapping")
	var before:Vector3=bubble.global_position;var skeleton:Skeleton3D=actor.visual.skeleton;var index:=skeleton.find_bone("head")
	skeleton.set_bone_pose_position(index,skeleton.get_bone_pose_position(index)+Vector3(.2,.1,0));skeleton.force_update_all_bone_transforms();manager._process(.01)
	check(bubble.global_position.distance_to(before)>.1 and (bubble.global_transform*preload("res://chatter/bubble.gd").TAIL_TIP).distance_to(preload("res://chatter/head_anchor.gd").crown(actor)+Vector3.UP*.035)<.001,"Animated source crown stays fixed to actual billboard tail tip")
	var crown:Vector3=preload("res://chatter/head_anchor.gd").crown(actor)
	check(crown.y>preload("res://pets/creature_targeting.gd").head_anchor(actor).y+.03,"Source crown is above the head bone inside the face")
	actor.scale=Vector3.ONE*1.3;actor.rotation.y=.45;actor.position.y=.2;host.player.eye.position.x=1;manager._process(.01)
	check((bubble.global_transform*preload("res://chatter/bubble.gd").TAIL_TIP).distance_to(preload("res://chatter/head_anchor.gd").crown(actor)+Vector3.UP*.035)<.001,"Tail remains crown-anchored through source scale, floor offset and observer rotation")
	actor.scale=Vector3.ONE;actor.rotation.y=0;actor.position=Vector3.ZERO;host.player.eye.position.x=0;manager._process(.01)
	manager.accept({"sequence":1,"events":[event()]});check(manager.created==1 and manager.active.size()==1,"Repeated snapshot/event does not duplicate a bubble or presentation learning")
	manager.accept({"sequence":0,"events":[event("2")]});check(manager.sequence==1 and manager.seen.size()==1,"Older native speech sequence cannot replay presentation")
	manager.accept({"sequence":2,"events":[event("2")]});check(manager.created==1 and manager.active.size()==1,"New sentence replaces the same speaker using pooled visual")
	var wall:=StaticBody3D.new();host.add_child(wall);wall.collision_layer=1;var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(4,4,.2);shape.shape=box;wall.add_child(shape);wall.position=Vector3(0,1.7,2)
	await physics_frame;manager.active["42"].occlusion_due=0;manager._process(.01)
	check(not bubble.visible,"Opaque world geometry occludes speech bubble")
	check(actor.label.visible,"Occluded speech restores prior native nameplate visibility")
	wall.free();await physics_frame;manager.active["42"].occlusion_due=0;manager._process(.01);check(bubble.visible,"Bubble reappears after obstruction clears")
	host.xr_requested=true;host.xr_focused=false;manager._process(.01);check(not bubble.visible and actor.label.visible,"Loss of XR focus hides speech without retaining altered nameplates")
	host.xr_requested=false
	actor.position=Vector3(0,0,6);manager._process(.01);check(not bubble.visible,"Behind-head speech is frustum culled")
	actor.position=Vector3(0,0,-40);manager._process(.01);check(not bubble.visible,"Distant speech is culled at fixed32m cap")
	actor.position=Vector3.ZERO;actor.hide();manager._process(.01);check(not bubble.visible,"Hidden source-cell actor never leaves a visible speech overlay")
	actor.show();host.stage.current_cell={"building_object_id":"99","cell_id":"99:1"};manager._process(.01);check(manager.active.is_empty(),"Cell transition removes old-cell speech immediately")
	host.stage.current_cell={"building_object_id":"0","cell_id":"0:0"};var stale:=event("stale");stale.age_ms=6001;manager.accept({"sequence":3,"events":[stale]});check(manager.active.is_empty(),"Expired server speech is not revived by packet arrival")
	var events:Array=[]
	for i in range(20):events.append(event(str(10+i),str(100+i)))
	manager.accept({"sequence":4,"events":events});check(manager.active.size()==8 and manager.created==8,"Burst of native speech respects global eight-bubble allocation cap")
	for entry:Dictionary in manager.active.values():entry.expires=0
	manager._process(.01);check(manager.active.is_empty() and manager.pool.size()==8,"Expired visuals return to bounded reusable pool")
	manager.clear();check(manager.sequence==-1 and manager.seen.is_empty() and manager.languages.is_empty(),"Session reset clears dedupe and native language state")
	host.free();await process_frame
	var report:Dictionary={"passed":failures.is_empty(),"checks":checks,"failures":failures,"native_events":"mocked","source_actor":"original Rodian commoner","renderer":"dummy","live_xr":false};FileAccess.open("res://../runtime/evidence/chatter-client.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "));print(JSON.stringify(report));quit(0 if failures.is_empty() else 1)
