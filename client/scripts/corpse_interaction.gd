extends RefCounted
## Shared generous bounds; reward eligibility remains server-owned.
const BODY_MARGIN := .35
const ABOVE_BODY := .85
const COIN_RADIUS := .5
const CHOICE_RADIUS := .14
static func eligible(record: Dictionary) -> bool:
	var loot: Dictionary = record.get("loot",{})
	return record.get("dead",false) and record.get("loot_available",false) and (int(loot.get("credits",0))>0 or int(loot.get("item_count",0))>0)
static func above_body(record: Dictionary, point: Vector3) -> bool:
	if not record.get("dead",false) or not record.get("bounds") is AABB or str(record.get("id","")).is_empty(): return false
	var bounds: AABB = record.bounds
	return point.is_finite() and point.x>=bounds.position.x-BODY_MARGIN and point.x<=bounds.end.x+BODY_MARGIN and point.z>=bounds.position.z-BODY_MARGIN and point.z<=bounds.end.z+BODY_MARGIN and point.y>=bounds.end.y-.15 and point.y<=bounds.end.y+ABOVE_BODY
static func coin_position(bounds:AABB,ground_y:float=NAN)->Vector3:
	var floor_y:float=bounds.position.y if not is_finite(ground_y) else ground_y
	return Vector3(bounds.get_center().x,clampf(bounds.end.y+.35,floor_y+.45,floor_y+1.2),bounds.get_center().z)
