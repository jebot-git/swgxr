extends SceneTree
const State=preload("res://spice/state.gd")
const Gunhand=preload("res://spice/gunhand.gd")
const World=preload("res://spice/world_effects.gd")
class Actor extends Node3D:
	var record:Dictionary
	var visual:MeshInstance3D
	var label:Label3D
var checks:=0
var errors:Array=[]
var target_point:=Vector3(1,1.5,-5)
func _initialize()->void:call_deferred("run")
func check(value:bool,label:String)->void:
	checks+=1
	if not value:errors.append(label);push_error(label)
static func envelope(id:String,phase:String,duration:=180.0,elapsed:=0.0,revision:=20)->Dictionary:
	return {"revision":revision,"effects":[{"episode_id":"dose-1","spice_id":id,"phase":phase,"duration_seconds":duration,"remaining_seconds":duration-elapsed,"elapsed_seconds":elapsed}]}
func actor(id:String,aggressive:bool,point:Vector3)->Actor:
	var value:=Actor.new();root.add_child(value);value.position=point;value.record={"id":id,"kind":"creature","dead":false,"aggressive":aggressive,"relation":"neutral"}
	value.visual=MeshInstance3D.new();value.visual.mesh=BoxMesh.new();value.add_child(value.visual);value.label=Label3D.new();value.add_child(value.label);return value
func acquire(_pose:Transform3D)->String:return "enemy"
func target(id:String)->Variant:return target_point if id=="enemy" else null
func run()->void:
	var state:=State.new()
	for id in ["muon_gold","pyrepenol","neutron_pixey"]:
		state.observe(envelope(id,"active"));check(state.policy().tint_amount>0,"Native active tint: "+id)
	state.observe(envelope("sedative_h4b","active"));check(state.policy().noise>0,"Sedative active noise")
	state.observe(envelope("giggledust","active"));check(state.policy().outlines and not state.policy().hostile_illusion,"Giggledust only reveals authoritative aggressive outlines")
	state.observe(envelope("giggledust","withdrawal",120));check(state.policy().psychedelic>0,"Giggledust withdrawal shifts colors")
	state.observe(envelope("sweetblossom","withdrawal",180,4));check(state.policy().pain>0,"Sweetblossom withdrawal has a slow pain pulse")
	for id in ["droid_lube","gunjack"]:
		state.reset();state.observe(envelope(id,"withdrawal",180,15));check(is_equal_approx(state.policy().darkness,.65),"30-second darkening maximum at 15 seconds: "+id)
		state.advance(15);check(is_zero_approx(state.policy().darkness),"30-second darkening returns smoothly to clear")
	state.reset();state.observe(envelope("pyrepenol","withdrawal",300));check(state.policy().hostile_illusion and not state.policy().outlines,"Pyrepenol withdrawal changes perception without granting xray outlines")
	state.observe(envelope("neutron_pixey","withdrawal",600));check(state.policy().tint.b>state.policy().tint.r,"Neutron withdrawal is blue")
	state.observe(envelope("booster_blue","active"));check(state.policy().sticky_aim and state.policy().monochrome==1,"Booster active greyscale and sticky aim")
	state.observe(envelope("booster_blue","withdrawal",300));check(not state.policy().sticky_aim and state.policy().lag_seconds>0 and state.policy().monochrome==1,"Booster withdrawal slow gunhand and greyscale")
	state.observe(envelope("crash_n_burn","withdrawal",300));check(state.policy().pain==0 and state.policy().tint_amount==0 and not state.policy().hostile_illusion,"Crash withdrawal does not disclose itself visually")
	state.reset();state.observe(envelope("yarrock","withdrawal",900));state.advance(20);state.observe(envelope("yarrock","withdrawal",900,15));check(state.elapsed==20 and state.remaining==880,"Duplicate delayed native observation cannot rewind pulse phase")
	state.advance(881);check(state.policy().tremor==0,"Local expired observation stops presentation without inventing next phase")
	state.observe({"revision":0,"effects":[]});check(state.effect.is_empty(),"Native empty revision-zero snapshot clears Buff identity")
	var head:=Transform3D(Basis.IDENTITY,Vector3(0,1.7,0));var raw:=Transform3D(Basis.IDENTITY,Vector3(0,1.4,-.5));var saved:=raw
	state.reset();state.observe(envelope("yarrock","withdrawal",900,1))
	var left:Transform3D=state.hand_pose(raw,head,"left");var right:Transform3D=state.hand_pose(raw,head,"right")
	check(raw==saved and left!=raw and right!=raw and left!=right,"Empty/tool hand tremor modifies independent visual copies, never tracking")
	state.observe(envelope("muon_gold","withdrawal",3600,1));check(state.hand_pose(raw,head)!=raw,"Muon withdrawal shares hand tremor")
	var filter:=Gunhand.new();state.observe(envelope("booster_blue","active"))
	var aimed:Transform3D=filter.sample(raw,raw,head,1,state.policy(),acquire,target)
	check(filter.locked_id=="enemy" and (-aimed.basis.z).dot((target_point-raw.origin).normalized())>.9999,"Ranged reticle acquisition steers virtual gunhand onto eligible enemy")
	filter.suspend();check(filter.locked_id=="enemy","Stowing cannot bypass sticky lock while the same spice phase remains active")
	target_point.x=2;var followed:Transform3D=filter.sample(raw,raw,head,1.02,state.policy(),acquire,target)
	check(followed!=aimed and raw==saved,"Virtual gunhand follows target movement while physical input remains identical")
	var lowered:=raw;lowered.origin.y-=.05
	filter.sample(lowered,lowered,head,1.12,state.policy(),acquire,target)
	check(filter.locked_id=="enemy","Gentle physical lowering does not cancel sticky aim")
	lowered.origin.y-=.4;filter.sample(lowered,lowered,head,1.17,state.policy(),acquire,target)
	check(filter.locked_id.is_empty(),"Forceful physical hand lowering below view releases target")
	filter.reset();state.observe(envelope("booster_blue","withdrawal",300))
	filter.sample(raw,raw,head,2,state.policy(),Callable(),Callable());var moved:=raw;moved.origin.x=1
	var slow:Transform3D=filter.sample(moved,moved,head,2.05,state.policy(),Callable(),Callable())
	check(slow.origin.x>0 and slow.origin.x<.3 and moved.origin.x==1,"Withdrawal slows virtual gunhand without delaying physical input")
	var world:=World.new();root.add_child(world)
	world.outline_material=ShaderMaterial.new();world.outline_material.shader=preload("res://spice/outline.gdshader")
	world.hostile_material=ShaderMaterial.new();world.hostile_material.shader=preload("res://spice/hostile_illusion.gdshader")
	var aggressive:=actor("a",true,Vector3(1,0,0));var neutral:=actor("b",false,Vector3(2,0,0));var far:=actor("c",true,Vector3(65,0,0));aggressive.hide()
	state.reset();state.observe(envelope("giggledust","active"));world.refresh([aggressive,neutral,far],[],Vector3.ZERO,state.policy())
	check(world.outlines.size()==1,"Only aggressive living creatures within64m receive outlines")
	var proxy:MeshInstance3D=world.outlines.values()[0].parts[0].proxy
	check(proxy.is_visible_in_tree() and proxy.mesh==aggressive.visual.mesh and not (proxy as Node) is CollisionObject3D,"Hidden actor gets separate original-mesh visible outline without collision")
	state.observe(envelope("pyrepenol","withdrawal",300));var original:=neutral.record.duplicate(true)
	world.refresh([aggressive,neutral,far],[],Vector3.ZERO,state.policy())
	check(world.outlines.is_empty() and neutral.visual.material_overlay==world.hostile_material and neutral.record==original,"False hostility changes local overlay, never native relation or AI record")
	state.observe({"revision":0,"effects":[]});world.refresh([],[],Vector3.ZERO,state.policy())
	check(neutral.visual.material_overlay==null and world.painted.is_empty(),"Expiry restores original actor materials")
	var vital:=preload("res://combat/vital_feedback.gd").new();vital.observe({"damage":1,"heal":2,"age_seconds":0});vital.prefer_latest_heal=true
	vital.observe({"damage":3,"heal":4,"age_seconds":0});vital.advance(.2)
	check(vital.strength("damage")==0 and vital.strength("heal")>0,"Crash self-heal shows only newest healing pulse despite real self damage")
	vital.observe({"damage":5,"heal":4,"age_seconds":0});vital.advance(.2)
	check(vital.strength("damage")>0,"Later genuine incoming damage still renders during Crash withdrawal")
	world.free();aggressive.free();neutral.free();far.free();await process_frame
	print(JSON.stringify({"checks":checks,"errors":errors,"renderer":"dummy","headset_validated":false,"native_state":"mocked"}));quit(0 if errors.is_empty() else 1)
