extends RefCounted
## Both presentations consume the same observer-specific native relation.
const COLORS={"neutral":Color("ffffff"),"attackable":Color("ffdd00"),"friendly":Color("00ff00"),"hostile":Color("ff0000")}
static func color(record:Dictionary)->Color:
	return COLORS.get(str(record.get("relation","neutral")),COLORS.neutral)
