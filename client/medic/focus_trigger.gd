extends RefCounted
## A short squeeze fires on release; a hold fires once, without a preceding tap.
const HOLD_SECONDS := 0.65
var armed := false
var pressing := false
var elapsed := 0.0

func reset() -> void:
	armed=false; pressing=false; elapsed=0.0

func sample(delta:float,trigger:float,permitted:bool)->String:
	if not permitted or not is_finite(delta) or delta<=0 or delta>.15 or not is_finite(trigger):
		reset();return ""
	if trigger<.25:
		var tap:=pressing
		armed=true;pressing=false;elapsed=0.0
		return "tenddamage" if tap else ""
	if trigger>.7 and armed:
		armed=false;pressing=true;elapsed=0.0
	if pressing:
		elapsed+=delta
		if elapsed+.00001>=HOLD_SECONDS:
			pressing=false
			return "quickheal"
	return ""
