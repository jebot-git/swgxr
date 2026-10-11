extends Node3D
## Only confirmed native receipts create text. No predicted damage numbers.
const LIMIT:=64
const LIFETIME:=1.1
var entries:Array=[]
static func outcome(mutation:Dictionary)->Dictionary:
	if not mutation.get("success",false):return {}
	var damage:=maxi(0,int(mutation.get("damage",0)))
	var before:Dictionary=mutation.get("before",{});var after:Dictionary=mutation.get("after",{})
	if before.get("ham") is Array and after.get("ham") is Array and before.ham.size()==3 and after.ham.size()==3:
		damage=0
		for i in 3:damage+=maxi(0,int(before.ham[i])-int(after.ham[i]))
	var resolution:=str(mutation.get("resolution",""))
	var label:String={"blocked":"Blocked","dodged":"Dodged","countered":"Countered","deflected":"Deflected","resisted":"Resisted","miss":"Miss","applied":"Warcry","ineffective":"No effect"}.get(resolution,"")
	if damage>0:return {"text":str(damage)+( " · "+label if not label.is_empty() else ""),"color":Color("ffdc75")}
	return {"text":label if not label.is_empty() else "No damage","color":Color("a9d8f5")}
func present(mutation:Dictionary,point:Vector3)->void:
	var result:=outcome(mutation)
	if result.is_empty() or not point.is_finite():return
	while entries.size()>=LIMIT:
		var old:Dictionary=entries.pop_front();old.label.queue_free()
	var label:=Label3D.new();label.text=result.text;label.font=preload("res://resources/fonts/Jupiteroid-Regular.ttf")
	label.font_size=44;label.pixel_size=.003;label.billboard=BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate=result.color;label.outline_modulate=Color(0,0,0,.9);label.outline_size=6
	label.no_depth_test=false;add_child(label);label.global_position=point
	entries.append({"label":label,"origin":point,"age":0.0,"color":result.color})
func _process(delta:float)->void:
	for i in range(entries.size()-1,-1,-1):
		var row:Dictionary=entries[i];row.age+=delta
		if row.age>=LIFETIME:row.label.queue_free();entries.remove_at(i);continue
		row.label.global_position=row.origin+Vector3.UP*row.age*.4
		row.label.modulate=Color(row.color,clampf((LIFETIME-row.age)/.35,0,1))
