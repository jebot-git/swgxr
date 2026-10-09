extends RefCounted
## Delay one tap briefly so a double tap never also sends Tend Damage.
const HOLD_SECONDS := 0.65
const DOUBLE_TAP_SECONDS := 0.30
var armed := false
var pressing := false
var elapsed := 0.0
var waiting := false
var interval := 0.0
var second := false
var identity := ""
var double_valid := true

func reset() -> void:
	armed=false;pressing=false;elapsed=0.0;waiting=false;interval=0.0;second=false;identity="";double_valid=true

func active() -> bool:
	return pressing or waiting

func sample(delta:float,trigger:float,permitted:bool,context:="",double_permitted:=true)->String:
	if not permitted or not is_finite(delta) or delta<=0 or delta>.15 or not is_finite(trigger):
		reset();return ""
	if active() and identity!=context:
		reset();return ""
	if active():double_valid=double_valid and double_permitted
	if waiting:
		interval+=delta
		if interval+.00001>=DOUBLE_TAP_SECONDS:
			waiting=false;identity=""
			return "tenddamage"
	if trigger<.25:
		armed=true
		if pressing:
			pressing=false;elapsed=0.0
			if second:
				second=false;identity=""
				return "healmind" if double_valid else ""
			waiting=true;interval=0.0
		return ""
	if trigger>.7 and armed:
		armed=false;pressing=true;elapsed=0.0;second=waiting;waiting=false;identity=context
		if not second:double_valid=double_permitted
	if pressing:
		elapsed+=delta
		if elapsed+.00001>=HOLD_SECONDS:
			pressing=false;waiting=false;second=false;identity=""
			return "quickheal"
	return ""
