extends SceneTree
const Feedback=preload("res://combat/player_feedback.gd")
const Eligibility=preload("res://combat/force_of_will.gd")
class Body extends CharacterBody3D:
 var active:=true
 var presentation_height:=0.0
var errors:Array=[]
var checks:=0
var actions:Array=[]
var feedback=Feedback.new()
func check(ok:bool,label:String)->void:
 checks+=1
 if not ok:errors.append(label);push_error(label)
func context()->Dictionary:
 return {"character_id":"will","posture":13,"force_of_will":{"learned":true,"conditions_met":true,"cooldown_remaining_seconds":0}}
func hold(seconds:float,tracked:=true)->void:
 for i in range(roundi(seconds*100)):feedback.update_life_input(true,tracked,.01)
func fresh()->void:
 feedback.reset();feedback.observe(context());actions.clear()
func _initialize()->void:call_deferred("run")
func run()->void:
 var body:=Body.new();root.add_child(body);feedback.body=body
 feedback.life_action_requested.connect(func(action):actions.append(action))
 fresh();hold(4);check(actions.is_empty(),"Already-held stick on incapacitation cannot activate either recovery")
 feedback.update_life_input(false,true,.01);hold(1.1)
 check(actions==["recover"],"Ordinary one-second recovery remains available")
 feedback.resolve_life_action(true);var pending:=context();pending.recovery_requested=true;pending.recovery_remaining_seconds=10.;feedback.observe(pending)
 hold(2.1);check(actions==["recover","force_of_will"],"Continuous three-second hold crosses normal acknowledgement to request Force of Will")
 check(feedback.life_locked and feedback.observed_posture==13,"Request cannot revive locally")
 feedback.resolve_life_action(true);hold(4);check(actions.size()==2,"Held input after acknowledgement cannot repeat Force of Will")
 feedback.observe({"character_id":"will","posture":0});check(not feedback.life_locked,"Authoritative awake snapshot alone releases life lock")
 fresh();feedback.update_life_input(false,true,.01);hold(1.1);feedback.resolve_life_action(false);hold(4)
 check(actions==["recover"],"Rejection requires release before any further recovery")
 for mode:String in ["release","tracking","menu","gap","nan"]:
  fresh();feedback.observe(pending);feedback.update_life_input(false,true,.01);hold(2.)
  if mode=="release":feedback.update_life_input(false,true,.01)
  if mode=="tracking":feedback.update_life_input(true,false,.01)
  if mode=="menu":body.active=false;feedback.update_life_input(true,true,.01);body.active=true
  if mode=="gap":feedback.update_life_input(true,true,1.)
  if mode=="nan":feedback.update_life_input(true,true,NAN)
  hold(1.2);check(actions.is_empty(),mode+" cannot complete stale Force of Will hold")
 for mode:String in ["unlearned","weapon","cooldown","dead","feigning","cloning","missing","nan"]:
  fresh();var c:=context()
  if mode=="unlearned":c.force_of_will.learned=false
  if mode=="weapon":c.force_of_will.conditions_met=false
  if mode=="cooldown":c.force_of_will.cooldown_remaining_seconds=1
  if mode=="dead":c.posture=14
  if mode=="feigning":c.feigning_death=true
  if mode=="cloning":c.cloning=true
  if mode=="missing":c.erase("force_of_will")
  if mode=="nan":c.force_of_will.cooldown_remaining_seconds=NAN
  feedback.observe(c);check(not Eligibility.available(c) and not feedback.request_life_action("force_of_will"),mode+" denies Force of Will")
 # Both transports consume the same server eligibility projection.
 var session=preload("res://scripts/gameplay_session.gd").new();root.add_child(session);session.set_process(false);session.live=true;session.player_state=context()
 check(session.request_life_action("force_of_will"),"Lightweight gameplay session accepts owned Force of Will intent")
 check(not session.request_life_action("force_of_will"),"Gameplay session serializes duplicate intent")
 session.life_action_pending="";session.player_state.force_of_will.cooldown_remaining_seconds=10
 check(not session.request_life_action("force_of_will"),"Gameplay session rejects stale cooldown")
 var live=preload("res://combat/live_world.gd").new();root.add_child(live);live.set_process(false);live.live=true;live.player_state=context();live.player_state.force_of_will.conditions_met=false
 check(not live.request_life_action("force_of_will"),"Combat transport checks eligibility before clearing attack queue")
 var support:Dictionary={"id":"force_of_will","category":"gesture","activation":"life_recovery","ultimate":false}
 check(not preload("res://combat/loadout.gd").equipped(support,{"slots":["force_of_will","","",""],"ultimate":"force_of_will"}),"Support ability consumes neither targeting nor ultimate slot")
 session.free();live.free();body.free()
 var report:Dictionary={"checks":checks,"errors":errors,"passed":errors.is_empty(),"native_replies":"mocked","gpu_validation":false,"xr":"off"}
 FileAccess.open("res://../runtime/evidence/force-of-will-client.json",FileAccess.WRITE).store_string(JSON.stringify(report));print(JSON.stringify(report));quit(0 if errors.is_empty() else 1)
