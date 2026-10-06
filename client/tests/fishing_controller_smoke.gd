extends SceneTree
class Session extends Node:
	var live:=true
	var session_id:="native-fixture"
class Host extends Node:
	var datapad_account:="fixture"
	var datapad_character_id:="42"
	var datapad_epoch:=1
	var inventory:Node3D
	var inventory_snapshot:Dictionary={}
	var live_combat:Node
	var gameplay_session:Node
	var reply:Dictionary={}
	var calls:Array=[]
	var change_epoch:=false
	var equipment_syncs:=0
	func source_position_at(p:Vector3)->Vector3:return Vector3(p.x,p.y,-p.z)
	func api(method:int,path:String,payload:Dictionary)->Dictionary:
		calls.append({'method':method,'path':path,'payload':payload.duplicate(true)})
		await get_tree().process_frame
		if change_epoch:datapad_epoch+=1
		return reply.duplicate(true)
	func reconcile_inventory_presentations()->void:pass
	func update_inventory_presentation()->void:pass
	func sync_inventory_equipment()->void:equipment_syncs+=1
var checks:=0
var errors:Array=[]
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:errors.append(message);push_error(message)
func _initialize()->void:run.call_deferred()
func run()->void:
	var host:=Host.new();root.add_child(host);host.live_combat=Session.new();host.add_child(host.live_combat)
	var rig:XROrigin3D=load('res://xr/player_rig.tscn').instantiate();host.add_child(rig)
	var body:=rig.get_node('PlayerBody');body.set_physics_process(false)
	var bag=preload('res://scripts/xr_inventory.gd').new();host.add_child(bag);bag.configure(rig,body);bag.set_process(false);bag.allowed=true;host.inventory=bag
	var control=preload('res://fishing/controller.gd').new();host.add_child(control);control.setup(host,bag);control.set_process(false)
	var item:Dictionary={'id':'100','template':'object/tangible/fishing/fishing_pole.iff','name':'Fishing pole','tool_kind':'fishing','equippable':true}
	bag.take_item(item)
	check(control.owns('100'),'Taking original fishing pole binds fishing controller')
	var model:Node3D=bag.held_model.get_child(0)
	check(model.scale.is_equal_approx(Vector3.ONE) and model.position.is_zero_approx(),'Held rod keeps full source dimensions and object-origin grip')
	check((model.basis*Vector3.UP).dot(Vector3.FORWARD)>.99,'Original rod shaft points along controller aim')
	bag.update_held_trigger(0,Transform3D.IDENTITY);bag.update_held_trigger(1,Transform3D.IDENTITY)
	check(not bag.hologram.active and host.calls.is_empty(),'Cast trigger cannot open ordinary equipment hologram')
	host.reply={'ok':true,'source_kind':'core3_services','character_id':'42','state':{'fishing':{'rod_id':'100','equipped':true,'stage':0,'bait_id':'200','bait_status':'Fresh','freshness':0},'inventory':{'source_kind':'core3_inventory','character_id':'42','items':[item]}}}
	await control.request('open')
	check(control.opened and control.age==0 and host.equipment_syncs==1,'Confirmed equip adopts native fishing state and synchronizes equipment')
	check(host.calls[-1].payload.live_session_id=='native-fixture' and host.calls[-1].payload.rod_id=='100','Fishing uses authenticated live session and rod identity')
	await control.request('action',{'gesture':4,'session_id':'cast-fixture'})
	check(host.calls[-1].payload.session_id=='cast-fixture' and host.calls[-1].payload.live_session_id=='native-fixture','Fishing attempt token is separate from transport session')
	var count:int=host.calls.size();control.busy=true;await control.request('cast',{'cast_position':[5,0,0]});control.busy=false
	check(host.calls.size()==count,'Busy requests do not queue a delayed cast')
	var before:Dictionary=control.state.duplicate(true)
	host.reply.state.fishing.rod_id='wrong';host.reply.state.fishing.freshness=9
	await control.request('status')
	check(control.state==before,'Foreign rod reply cannot alter local fishing state')
	host.reply.state.fishing.rod_id='100';host.reply.state.inventory.character_id='different'
	await control.request('status')
	check(control.state==before,'Foreign inventory reply is rejected before state adoption')
	host.reply.state.inventory.character_id='42';host.change_epoch=true
	await control.request('status')
	check(control.state==before and not control.busy,'Late reply from prior character cannot update fishing state')
	host.change_epoch=false;control.set_allowed(true)
	check(control.busy_hand('left') and not control.busy_hand('right'),'Reeling offhand is reserved independently of rod hand')
	check(control.try_drop(item) and bag.held_item.is_empty() and control.pending_stow=='100','Releasing rod queues stow and releases only its local presentation')
	check(host.calls.size()==count+3,'Dropping rod never creates a cast or bait-consumption request')
	await control.request('stow',{},'100')
	check(host.calls[-1].path=='/services/fishing_stow','Stow is an explicit native request')
	control.reset();check(control.rod.is_empty() and control.state.is_empty() and body.fishing_stick_side=='','Character reset clears gestures and locomotion capture')
	host.free()
	var result:Dictionary={'passed':errors.is_empty(),'checks':checks,'errors':errors,'native':'mocked','renderer':'headless dummy','live_headset':false}
	var f:=FileAccess.open('res://../runtime/evidence/fishing-controller.json',FileAccess.WRITE);f.store_string(JSON.stringify(result,'  ')+'\n');print(JSON.stringify(result));quit(0 if errors.is_empty() else 1)
