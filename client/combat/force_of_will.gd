extends RefCounted
## Snapshot eligibility only; Core3 owns recovery and cooldown.
static func available(context: Dictionary) -> bool:
 var state: Variant = context.get("force_of_will", {})
 if not state is Dictionary: return false
 var remaining: Variant = state.get("cooldown_remaining_seconds", INF)
 return int(context.get("posture", 0)) == 13 and not bool(context.get("feigning_death", false)) and not bool(context.get("cloning", false)) and bool(state.get("learned", false)) and bool(state.get("conditions_met", false)) and (remaining is float or remaining is int) and is_finite(float(remaining)) and float(remaining) == 0.0
