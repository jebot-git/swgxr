extends RefCounted
## Detection uses tracked poses only; native CoreCU decides mitigation and cost.
const HOLD_SECONDS:=0.12
var held:=0.0
var previous:Dictionary={}
var current:Dictionary={"mode":"none"}
func clear()->void:
	held=0;previous={};current={"mode":"none"}
static func hand(point:Vector3,boxing:bool)->bool:
	return point.is_finite() and absf(point.x)<=.55 and point.y>=(-.35 if boxing else -.70) and point.y<=.20 and point.z>=-.80 and point.z<=-.10
static func qualifies(mode:String,left:Vector3,right:Vector3,axis:Vector3,main:String)->bool:
	if mode=="boxing":return hand(left,true) and hand(right,true) and left.x<-.04 and right.x>.04 and right.x-left.x<=.85
	return mode=="parry" and hand(left if main=="left" else right,false) and axis.is_finite() and absf(axis.length()-1)<.05 and absf(axis.z)<=.65
func sample(delta:float,mode:String,left:Vector3,right:Vector3,axis:Vector3,main:String,item:String)->void:
	if delta<=0 or delta>.1 or not qualifies(mode,left,right,axis,main):clear();return
	var stable:bool=not previous.is_empty() and previous.mode==mode and previous.item==item
	if stable:
		# A swing or punch drops guard immediately; locomotion is removed by the head-relative frame.
		stable=left.distance_to(previous.left)/delta<2.5 and right.distance_to(previous.right)/delta<2.5
	held=held+delta if stable else 0.0
	previous={"mode":mode,"item":item,"left":left,"right":right}
	current={"mode":mode,"main":main,"item_id":item,"left":[left.x,left.y,left.z],"right":[right.x,right.y,right.z],"axis":[axis.x,axis.y,axis.z]} if held>=HOLD_SECONDS else {"mode":"none"}
