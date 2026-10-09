extends RefCounted
## Controller-driven two-hand strikes. End the slam above the physical floor.
var phase:=""
var age:=0.0
var hold:=0.0
var start:=Vector3.ZERO
var previous:=Vector3.INF
var head_start:=Vector3.ZERO
var capturing:=false
var latched:=false
var chord_armed:=false
var chord_consumed:=false
var chord_waiting:=false
var chord_age:=0.0
func clear()->void:
	phase="";age=0;hold=0;previous=Vector3.INF;capturing=false;latched=false;chord_armed=false;chord_consumed=false;chord_waiting=false;chord_age=0
func sample(delta:float,p:Vector3,head:Vector3,main_trigger:float,support_trigger:float,permitted:bool,available:Array,ultimate_selected:bool)->String:
	capturing=false
	if not permitted or not is_finite(delta) or delta<=0 or delta>.1 or not p.is_finite() or not head.is_finite() or not is_finite(main_trigger) or not is_finite(support_trigger):clear();return ""
	if previous.is_finite() and p.distance_to(previous)>.35:clear();return ""
	previous=p
	var both_released:bool=main_trigger<.2 and support_trigger<.2
	if both_released:chord_armed=true;chord_consumed=false;chord_waiting=false;chord_age=0
	var main_down:bool=main_trigger>=.75
	var support_down:bool=support_trigger>=.75
	if ultimate_selected and not both_released:
		if chord_consumed:capturing=true;return ""
		if chord_armed and (main_down or support_down):
			if chord_waiting:chord_age+=delta
			else:chord_waiting=true;chord_age=0
			if main_down and support_down and chord_age<=.12:
				chord_consumed=true;chord_armed=false;phase="";hold=0;capturing=true
				return "armour_break" if "armour_break" in available else ""
			if chord_age>=.12:chord_armed=false;chord_waiting=false
			else:capturing=true;phase="";hold=0;return ""
		if support_down:capturing=true;phase="";hold=0;return ""
	if main_trigger>.25 or support_trigger>.25:phase="";hold=0;latched=false;return ""
	var ready:bool=absf(p.x)<.7 and p.z>-.85 and p.z<.1 and p.y<-.15 and p.y>-.5
	if latched:
		capturing=true;hold=hold+delta if ready else 0.0
		if hold>=.2:latched=false;phase="ready";hold=0;age=0;start=p;head_start=head
		return ""
	if phase.is_empty():
		hold=hold+delta if ready else 0.0
		if hold>=.15:phase="ready";age=0;start=p;head_start=head
		return ""
	age+=delta
	if age>1.6 or head.distance_to(head_start)>.15 or absf(p.x-start.x)>.45 or absf(p.z-start.z)>.5:phase="";hold=0;return ""
	if phase=="ready" and p.y>.25:phase="overhead";start=p;age=0
	var result:=""
	if phase=="overhead" and start.y-p.y>=.6 and p.y<-.25 and age<=.9:result="overhead_cleave"
	elif phase=="ready" and start.y-p.y>=.5 and p.y<-.85 and age<=.9:result="ground_slam"
	if result.is_empty():return ""
	phase="";latched=true;hold=0;capturing=true
	return result if result in available else ""
