extends RefCounted
## Allow a small real-world difference between the two trigger edges.
const CHORD_WINDOW := .12
var armed := false
var waiting := false
var elapsed := 0.0
var consumed := false
var previous_main := false
func reset()->void:
	armed=false;waiting=false;elapsed=0;consumed=false;previous_main=false
func sample(delta:float,main:float,support:float,two_hands:bool,permitted:bool)->Dictionary:
	var out:Dictionary={"trigger":main,"ultimate":false,"reserved":false}
	if not permitted or not is_finite(delta) or delta<=0 or delta>.15:
		reset();out.trigger=0.0;out.reserved=true;return out
	var down:=main>=.75;var off:=support>=.75
	var released:=main<.2 and support<.2
	if consumed:
		if released:consumed=false;armed=true
		out.trigger=0.0;out.reserved=true;previous_main=down;return out
	if not two_hands:
		if waiting:
			waiting=false;consumed=true;armed=false;out.trigger=0.0;out.reserved=true;return out
		reset();return out
	if released and not waiting:armed=true
	if waiting:
		elapsed+=delta
		if off and down and elapsed<=CHORD_WINDOW:
			out.ultimate=true;consumed=true;waiting=false;armed=false
		elif not down or elapsed>=CHORD_WINDOW:
			out.trigger=1.0;waiting=false;armed=false;previous_main=down;return out
		out.trigger=0.0;out.reserved=true;previous_main=down;return out
	if armed and off and down:
		out.ultimate=true;out.trigger=0.0;out.reserved=true;consumed=true;armed=false
	elif armed and down and not previous_main:
		waiting=true;elapsed=0;out.trigger=0.0;out.reserved=true
	elif off:
		out.trigger=0.0;out.reserved=true
	previous_main=down
	return out
