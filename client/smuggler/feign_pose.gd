extends RefCounted
## Physical intent only. Core3 owns eligibility, incapacitation and release.
const HOLD_SECONDS := 0.45
var elapsed := 0.0
var candidate := ""
var intent := ""
var tracked := false

func reset() -> void:
	elapsed=0;candidate="";intent="";tracked=false

func sample(context: Dictionary, head_basis: Basis, standing_height: float, delta: float) -> Dictionary:
	var height:=float(context.get("eye_height",NAN))
	tracked=bool(context.get("tracked",false)) and head_basis.is_finite() and is_finite(height) and height>=0 and is_finite(standing_height) and standing_height>0
	if not tracked:
		elapsed=0;candidate=""
		return payload()
	var upward:=(-head_basis.z.normalized()).dot(Vector3.UP)
	var upright_head:=head_basis.y.normalized().dot(Vector3.UP)
	var ratio:=height/standing_height
	var next:=""
	if bool(context.get("grounded",false)):
		if upward>=0.94 or (ratio<=0.46 and upward>=0.65):next="feign"
		elif ratio>=0.86 and upward<0.5 and upright_head>0.7:next="upright"
	if next!=candidate:elapsed=0;candidate=next
	if next.is_empty():elapsed=0
	elif is_finite(delta) and delta>0:
		elapsed+=minf(delta,0.1)
		if elapsed>=HOLD_SECONDS:intent=next
	return payload()

func payload() -> Dictionary:
	return {"tracked":tracked,"feign":tracked and intent=="feign","upright":tracked and intent=="upright"}
