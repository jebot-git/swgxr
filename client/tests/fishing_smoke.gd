extends SceneTree
const Gestures=preload("res://fishing/gestures.gd")
var checks:=0
var failures:Array=[]
func check(value:bool,message:String)->void:
	checks+=1
	if not value:failures.append(message);push_error(message)
func _initialize()->void:run.call_deferred()
func seeded(stage:int=0)->RefCounted:
	var g=Gestures.new();g.sample(Transform3D.IDENTITY,Vector3.ZERO,0,false,.01,true,stage,true);g.sample(Transform3D.IDENTITY,Vector3.ZERO,0,false,.01,true,stage,true);return g
func cast_at(rate:float)->Dictionary:
	var g=seeded();var pose:=Transform3D.IDENTITY;var dt:=1/rate
	g.sample(pose,Vector3.ZERO,1,false,dt,true,0,true)
	for i in int(rate*.2):pose.origin.z+=1.5*dt;g.sample(pose,Vector3.ZERO,1,false,dt,true,0,true)
	for i in int(rate*.2):pose.origin.z-=2.0*dt;g.sample(pose,Vector3.ZERO,1,false,dt,true,0,true)
	return g.sample(pose,Vector3.ZERO,0,false,dt,true,0,true)
func run()->void:
	for script in ['res://fishing/controller.gd','res://fishing/bait_slots.gd','res://scripts/main.gd']:check(load(script)!=null,'Script loads '+script)
	var distances:Array=[]
	for rate in [72.0,90.0,120.0]:
		var result:=cast_at(rate);check(result.has('cast_direction'),'Backswing and forward release casts at %s Hz'%rate)
		if result.has('cast_direction'):
			check(result.cast_direction.dot(Vector3.FORWARD)>.99,'Cast follows hand heading, not head');distances.append(result.cast_distance)
	check(distances.size()==3 and absf(float(distances.max())-float(distances.min()))<.1,'Physical cast stable across headset frame rates')
	var g=seeded();var pose:=Transform3D.IDENTITY
	g.sample(pose,Vector3.ZERO,1,false,.01,true,0,true)
	check(g.sample(pose,Vector3.ZERO,0,false,.01,true,0,true).is_empty(),'Click without cast cannot launch')
	var still:=true
	for i in 60:still=still and g.sample(pose,Vector3.ZERO,0,false,.01,true,1,false).is_empty()
	check(still,'Still hands never issue a fishing action')
	g=seeded(4)
	var output:Dictionary={}
	for i in 15:
		pose.origin.y+=.012
		var step:Dictionary=g.sample(pose,Vector3.ZERO,0,false,.01,true,4,false)
		if not step.is_empty():output=step
	check(output.get('gesture',0)==1,'Quick upward lift sets hook')
	check(g.sample(pose,Vector3.ZERO,0,false,.01,true,4,false).is_empty(),'Holding raised rod does not repeat hook')
	g=seeded(4);pose=Transform3D.IDENTITY;output={}
	for i in 30:
		pose.origin.x-=.012
		var step:Dictionary=g.sample(pose,Vector3.ZERO,0,false,.01,true,4,false)
		if not step.is_empty():output=step
	check(output.get('gesture',0)==3,'Physical left pull maps to native tug left')
	g=seeded(7);pose=Transform3D.IDENTITY;output={}
	for i in 100:
		var angle:=float(i)*.06
		var other:=Vector3(0,cos(angle)*.08,sin(angle)*.08)
		var step:Dictionary=g.sample(pose,other,0,true,.01,true,7,false)
		if not step.is_empty():output=step
	check(output.get('gesture',0)==4,'Offhand circular crank requests native reel')
	g=seeded(7);output={}
	for i in 100:
		var step:Dictionary=g.sample(pose,Vector3(0,.08,0),0,true,.01,true,7,false)
		if not step.is_empty():output=step
	check(output.is_empty(),'Holding reel without motion cannot retrieve line')
	g=seeded();g.sample(pose,Vector3.ZERO,1,false,.01,true,0,true)
	pose.origin=Vector3(100,100,100)
	check(g.sample(pose,Vector3.ZERO,1,false,.01,true,0,true).is_empty(),'Tracking teleport rejected')
	check(g.sample(pose,Vector3.ZERO,0,false,.01,true,0,true).is_empty(),'Teleport release cannot cast')
	g.reset();g.sample(pose,Vector3.ZERO,1,false,.01,false,0,true)
	check(g.sample(pose,Vector3.ZERO,1,false,.01,true,0,true).is_empty(),'Tracking reacquisition requires fresh release')
	check(g.sample(pose,Vector3.ZERO,0,false,.2,true,0,true).is_empty(),'Long frame cannot score motion')
	g=seeded();check(g.sample(Transform3D(Basis.IDENTITY,Vector3.ZERO),Vector3.ZERO,1,false,.01,true,0,false).is_empty() and not g.casting,'Missing bait cannot begin cast')
	var assets=preload('res://scripts/inventory_assets.gd').new();assets.configure()
	for template in ['object/tangible/fishing/fishing_pole.iff','object/tangible/fishing/marker.iff','object/tangible/fishing/bait/bait_worm.iff','object/tangible/fishing/bait/bait_insect.iff','object/tangible/fishing/bait/bait_chum.iff']:
		check(assets.model(template)!=null,'Original fishing model available '+template)
	var slots=preload('res://fishing/bait_slots.gd').new();root.add_child(slots);slots.setup(assets)
	var rows:Array=[{'id':'44','template':'object/tangible/fishing/bait/bait_worm.iff','name':'Worm','use_count':3}]
	slots.configure(rows,'Fresh',true)
	var received:Array=[];slots.dropped.connect(func(row):received.append(row))
	slots.sample(slots.cubes[0].global_position,0,Vector2.ZERO,true)
	slots.sample(slots.cubes[0].global_position,1,Vector2.ZERO,true)
	check(not slots.selected.is_empty(),'Grip selects actual bait model from filtered grid')
	slots.sample(Vector3(0,0,2),0,Vector2.ZERO,true)
	check(received.is_empty(),'Release outside slot cancels without request')
	slots.sample(slots.cubes[0].global_position,1,Vector2.ZERO,true);slots.sample(slots.slot.global_position,0,Vector2.ZERO,true)
	check(received.size()==1 and received[0].id=='44','Dropping into bait cube sends original inventory ID once')
	slots.sample(slots.slot.global_position,0,Vector2.ZERO,true);check(received.size()==1,'Held release cannot duplicate bait loading')
	slots.sample(slots.cubes[0].global_position,1,Vector2.ZERO,true);slots.sample(slots.slot.global_position,0,Vector2.ZERO,false)
	check(received.size()==1 and slots.selected.is_empty(),'Tracking loss cancels bait drag')
	slots.configure(rows,'Soggy',false);check(slots.cubes.is_empty() and slots.label.text.contains('Soggy'),'Server freshness displayed and active fishing cannot change bait')
	slots.free()
	var evidence:Dictionary={'passed':failures.is_empty(),'checks':checks,'failures':failures,'tracking':'mocked','renderer':'headless dummy','native_execution':false,'live_headset':false}
	var file:=FileAccess.open('res://../runtime/evidence/fishing-client.json',FileAccess.WRITE);file.store_string(JSON.stringify(evidence,'  ')+'\n');print(JSON.stringify(evidence));quit(0 if failures.is_empty() else 1)
