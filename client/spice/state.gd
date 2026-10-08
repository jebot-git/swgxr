extends RefCounted
## Owner-only presentation of authoritative native spice phases; never grants buffs.
var revision:=-1
var effect:Dictionary={}
var elapsed:=0.0
var remaining:=0.0
func reset()->void:revision=-1;effect={};elapsed=0;remaining=0
func observe(value:Dictionary)->void:
	var incoming:Variant=value.get("effects")
	if not incoming is Array or incoming.size()>1:return
	var version:=int(value.get("revision",0))
	if incoming.is_empty():revision=version;effect={};elapsed=0;remaining=0;return
	var row:Variant=incoming[0]
	if not row is Dictionary or str(row.get("episode_id","")).is_empty() or str(row.get("spice_id","")).is_empty() or row.get("phase","") not in ["active","withdrawal"]:return
	for key in ["elapsed_seconds","remaining_seconds","duration_seconds"]:
		if not is_finite(float(row.get(key,NAN))) or float(row.get(key,-1))<0:return
	var same:bool=str(effect.get("episode_id",""))==str(row.episode_id) and effect.get("phase","")==row.phase and effect.get("spice_id","")==row.spice_id
	revision=version;effect=row.duplicate(true)
	elapsed=maxf(elapsed,float(row.elapsed_seconds)) if same else float(row.elapsed_seconds)
	remaining=maxf(0,float(row.remaining_seconds)-(elapsed-float(row.elapsed_seconds)))
func advance(delta:float)->void:
	if not is_finite(delta) or delta<0:return
	var amount:=minf(delta,remaining);elapsed+=amount;remaining=maxf(0,remaining-delta)
func is_phase(id:String,phase:String)->bool:return remaining>0 and effect.get("spice_id","")==id and effect.get("phase","")==phase
func policy()->Dictionary:
	var result:={"monochrome":0.0,"psychedelic":0.0,"noise":0.0,"tint":Color.WHITE,"tint_amount":0.0,"darkness":0.0,"pain":0.0,"tremor":0.0,"lag_seconds":0.0,"sticky_aim":false,"hostile_illusion":false,"outlines":false,"elapsed":elapsed,"episode_id":str(effect.get("episode_id",""))}
	if remaining<=0:return result
	var id:=str(effect.spice_id);var withdrawal:bool=effect.phase=="withdrawal"
	if not withdrawal:
		match id:
			"giggledust":result.outlines=true
			"muon_gold":result.tint=Color(1.0,.92,.6);result.tint_amount=.10
			"pyrepenol":result.tint=Color(1.0,.16,.22);result.tint_amount=.12
			"sedative_h4b":result.noise=.10
			"neutron_pixey":result.tint=Color(1.0,.58,.82);result.tint_amount=.10
			"booster_blue":result.monochrome=1.0;result.sticky_aim=true
	else:
		match id:
			"sweetblossom":result.pain=(.5-.5*cos(elapsed*TAU/8.0))*.075
			"giggledust":result.psychedelic=1.0
			"yarrock","muon_gold":result.tremor=.014
			"droid_lube","gunjack":result.darkness=(.5-.5*cos(elapsed*TAU/30.0))*.65
			"pyrepenol":result.hostile_illusion=true
			"neutron_pixey":result.tint=Color(.55,.7,1.0);result.tint_amount=.10
			"booster_blue":result.monochrome=1.0;result.lag_seconds=.24
	return result

func hand_pose(pose:Transform3D,head:Transform3D,side:="right")->Transform3D:
	return preload("res://spice/gunhand.gd").shake(pose,head,policy(),side)
