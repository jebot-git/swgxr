extends SceneTree
const Clap = preload("res://entertainment/clap.gd")
const Fixture = preload("res://tests/entertainer_smoke.gd")
class Host extends Fixture.ControlHost:
	var xr_requested := true
	var xr_focused := true
class Native extends Fixture.NativeStub:
	func placed_instruments() -> Array: return [{"id":"placed"}]
var checks := 0
var errors: Array[String] = []
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: errors.append(label); push_error(label)
func _initialize() -> void:
	create_timer(30).timeout.connect(func(): quit(2))
	call_deferred("run")
func clap_poses(t: float, mode: String) -> Array:
	var half := .24-.18*clampf((t-.15)/.25,0,1)
	if mode=="slow": half=.24-.18*clampf((t-.15)/1.5,0,1)
	if mode=="touch": half=.06
	if mode=="jitter": half=.075+.006*sin(t*TAU*8)
	var left := Transform3D(Basis.IDENTITY,Vector3(-half,-.35,-.45))
	var right := Transform3D(Basis.IDENTITY,Vector3(half,-.35,-.45))
	if mode=="one_hand": left.origin.x=-.24; right.origin.x=.24-(.24-half)*2
	if mode=="outward": left.basis=Basis(Vector3.UP,PI); right.basis=left.basis
	if mode=="overhead": left.origin.y=.4; right.origin.y=.4
	if mode=="behind": left.origin.z=.3; right.origin.z=.3
	return [left,right]
func run() -> void:
	for hz in [45.0,72.0,90.0,120.0]:
		var clap := Clap.new(); var fired := 0
		for frame in range(int(hz*2)):
			var t:float=frame/hz; var poses:=clap_poses(t,"normal")
			var head:=Transform3D(Basis(Vector3.UP,t*.3),Vector3(t,1.7,t*.2))
			if clap.sample(1/hz,head,head*poses[0],head*poses[1],true): fired+=1
		check(fired==1,"One clap, including held contact, while walking/turning at %d Hz"%hz)
	for mode in ["slow","touch","jitter","one_hand","outward","overhead","behind","blocked"]:
		var clap:=Clap.new(); var fired:=false
		for frame in range(180):
			var poses:=clap_poses(frame/90.0,mode)
			fired=clap.sample(1.0/90,Transform3D.IDENTITY,poses[0],poses[1],mode!="blocked") or fired
		check(not fired,"Reject "+mode)
	var clap:=Clap.new()
	var wide:=clap_poses(0,"normal"); var closed:=clap_poses(1,"normal")
	clap.sample(.02,Transform3D.IDENTITY,wide[0],wide[1],true)
	clap.sample(.02,Transform3D.IDENTITY,wide[0],wide[1],false)
	check(not clap.sample(.1,Transform3D.IDENTITY,closed[0],closed[1],true),"Tracking return at contact cannot fabricate clap")
	var host:=Host.new(); root.add_child(host)
	var body:=Fixture.ControlBody.new(); host.add_child(body)
	var camera:=Camera3D.new(); body.add_child(camera)
	body.feedback=Fixture.GroundedFeedback.new(); body.feedback.configure(body,camera)
	var performer:=preload("res://entertainment/controller.gd").new(); host.add_child(performer)
	performer.set_process(false); performer.set_physics_process(false)
	performer.native.free(); performer.native=Native.new(); performer.add_child(performer.native)
	performer.host=host; performer.body=body; performer.head=camera; performer.context={"entertainer":true}
	for mode in ["dance","music","placed","idle","stale","menu","untracked","unfocused","unequipped","inactive"]:
		performer.clap.reset(); performer.native.calls.clear()
		performer.active_performance={} if mode=="idle" else {"id":"test"}
		performer.since_reply=5 if mode=="stale" else 0
		performer.item={"id":"instrument"} if mode in ["music","unequipped"] else {"id":"placed","placed":true} if mode=="placed" else {}
		performer.equipped_instrument={"id":"instrument"} if mode=="music" else {}
		host.xr_focused=mode!="unfocused"; body.active=mode!="inactive"
		if mode=="menu": performer.ui.open([{"id":"stop","label":"Stop"}],Transform3D.IDENTITY)
		else: performer.ui.close()
		for frame in range(180):
			var poses:=clap_poses(frame/90.0,"normal")
			performer.sample_clap(1.0/90,poses[0],poses[1],mode!="untracked")
		check(performer.native.calls.size()==(1 if mode in ["dance","music","placed"] else 0),"Production flourish routing: "+mode)
		if mode=="dance":
			for frame in range(90):
				var poses:=clap_poses(frame/90.0,"normal")
				performer.sample_clap(1.0/90,poses[0],poses[1],true)
			check(performer.native.calls.size()==2 and performer.native.calls.all(func(call):return call.action=="flourish"),"Fresh separated clap dispatches existing native flourish again")
	host.free(); await process_frame
	var report: Dictionary={"passed":errors.is_empty(),"checks":checks,"errors":errors,"mocked_tracking":true,"native_transport":"mocked","headset_tested":false}
	print(JSON.stringify(report)); FileAccess.open("res://../runtime/evidence/flourish-clap.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	quit(0 if errors.is_empty() else 1)
