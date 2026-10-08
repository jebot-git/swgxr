extends RefCounted
## Local prediction of server/combat/ArmourModel.h. Native Core3 owns live hits.

static func weapon(original: String, ap: int, broken := false) -> Dictionary:
	var budget: float = [0.0, 0.05, 0.10, 0.20][clampi(0 if broken else ap, 0, 3)]
	var base := "kinetic" if original == "blast" else "energy" if original in ["stun", "lightsaber"] else original
	var element := "heat"
	var fraction := 0.0
	if original in ["heat", "cold", "acid", "electricity"]:
		base = "kinetic" if original in ["cold", "acid"] else "energy"
		element = original
		fraction = 0.20
	elif original in ["blast", "stun", "lightsaber"]:
		element = "electricity" if original == "stun" else "heat"
		fraction = 0.20
	elif budget > 0:
		element = "electricity" if original == "kinetic" else "heat"
		fraction = minf(0.10, budget * 0.5)
	var bypass := budget * 0.5 if fraction > 0 else budget
	return {"version":1,"base_type":base,"element_type":element,"element_fraction":fraction,
		"penetration":bypass,"damage_scale":minf(1,(1+budget)/(1+fraction+bypass*(1-fraction)))}

static func damage(raw: float, profile: Dictionary, resistance: Dictionary) -> float:
	var fraction := float(profile.element_fraction)
	var bypass := float(profile.penetration)
	var base := clampf(float(resistance.get(profile.base_type, 0))/100, 0, 0.5)
	var element := clampf(float(resistance.get(profile.element_type, 0))/100, 0, 0.5)
	return raw * float(profile.damage_scale) * ((1-fraction)*(1-base*(1-bypass))+fraction*(1-element*(1-bypass)))
