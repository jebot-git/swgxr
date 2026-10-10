extends SceneTree
func _initialize():call_deferred("run")
func run():
 var world:=Node3D.new();root.add_child(world)
 var camera:=Camera3D.new();world.add_child(camera);camera.position=Vector3(0,2,8);camera.current=true
 var mixer=preload("res://audio/spatial_audio.gd").new();world.add_child(mixer);mixer.configure(camera,null,"standard",true)
 var scenery=preload("res://scripts/service_world.gd").new();world.add_child(scenery);scenery.configure(Vector3.ZERO)
 var checks:=0
 for template in ["object/mobile/player_transport.iff","object/creature/npc/theme_park/player_shuttle.iff"]:
  for phase in ["land","take_off"]:
   var rows=[{"id":"shuttle","template":template,"position":[0,0,0],"state":phase,"phase_elapsed_seconds":0}]
   scenery.apply_snapshot({"shuttles":rows},Vector3.ZERO)
   var entry:Dictionary=scenery.shuttles.shuttle
   var event_name:="land" if phase=="land" else "takeoff"
   var events:Array=entry.audio_binding.clips[phase].filter(func(e):return e.event==event_name)
   assert(not events.is_empty(),"Missing original animation sound event");checks+=1
   scenery.advance(float(events[0].seconds)+.06)
   assert(event_name in entry.audio.events,"Animation did not emit original sound at its frame");checks+=1
   # Sound position must track original animated root, not the pad origin.
   var index:int=entry.actor.skeleton.find_bone("root")
   assert(index>=0 and entry.audio.global_position.is_equal_approx((entry.actor.skeleton.global_transform*entry.actor.skeleton.get_bone_global_pose(index)).origin));checks+=1
   var sound:String=entry.audio_binding.events[event_name]
   var deadline:=Time.get_ticks_msec()+10000
   var played:=false
   while Time.get_ticks_msec()<deadline:
    await process_frame
    for player in mixer.active:
     if player.get_meta("source_sound","")==sound and player.playing and player.stream.get_length()>0:played=true
    if played:break
   if not played:print(JSON.stringify({"template":template,"phase":phase,"position":str(entry.audio.global_position),"audible":entry.audio.audible(),"binding":mixer.mobile.binding(template),"channels":str(mixer.mobile.channels),"failed":mixer.mobile.cache.failed,"decoded":mixer.mobile.cache.decoded,"events":entry.audio.events}))
   assert(played,"Original shuttle recording did not reach the production spatial mixer: "+sound);checks+=1
   entry.audio.events.clear();scenery.advance(.05)
   assert(entry.audio.events.is_empty(),"Same animation event replayed next frame");checks+=1
   scenery.apply_snapshot({},Vector3.ZERO);await process_frame;await process_frame
   mixer.mobile.tick(.2)
   assert(mixer.mobile.channels.is_empty(),"Despawn retained shuttle audio");checks+=1
 world.queue_free();await process_frame
 print(JSON.stringify({"passed":true,"checks":checks,"source":"Original CDF/CEFT PSND and animation MESG frames","audio_driver":"Dummy","physical_audio_validated":false,"xr":false}));quit()
