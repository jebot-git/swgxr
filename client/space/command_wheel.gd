extends Node3D
signal selected(command_id:String)
var rows:Array=[]
var current:=-1
var opened:=false
var labels:Array[Label3D]=[]
var heading:Label3D
var dialogue:Label3D
var dialogue_back:MeshInstance3D
func _ready()->void:
	heading=Label3D.new();heading.font=preload("res://resources/fonts/Jupiteroid-Regular.ttf");heading.font_size=26;heading.pixel_size=.001;heading.billboard=BaseMaterial3D.BILLBOARD_ENABLED;add_child(heading)
	dialogue_back=MeshInstance3D.new();var quad:=QuadMesh.new();quad.size=Vector2(.48,.25);dialogue_back.mesh=quad
	var material:=StandardMaterial3D.new();material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;material.albedo_color=Color(.01,.08,.12,.94)
	dialogue_back.material_override=material;dialogue_back.position.z=.002;add_child(dialogue_back);dialogue_back.hide()
	dialogue=Label3D.new();dialogue.font=heading.font;dialogue.font_size=20;dialogue.pixel_size=.00065;dialogue.width=680;dialogue.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;dialogue.position.z=.008;add_child(dialogue);dialogue.hide()
	hide()
func configure(commands:Array)->void:
	dialogue.hide();dialogue_back.hide();heading.position=Vector3.ZERO
	rows=commands.duplicate(true)
	for node in labels:node.queue_free()
	labels.clear()
	for index in rows.size():
		var label:=Label3D.new();label.font=heading.font;label.font_size=21;label.pixel_size=.00075;label.billboard=BaseMaterial3D.BILLBOARD_ENABLED
		var angle:=TAU*index/maxi(1,rows.size())-PI*.5
		label.position=Vector3(cos(angle)*.31,sin(angle)*-.24,0)
		label.text=str(rows[index].get("label",rows[index].get("id","")));label.modulate=Color("9dceea") if rows[index].get("available",false) else Color("67717a")
		add_child(label);labels.append(label)
	current=-1;heading.text="Ship commands\nStick · choose   Trigger · confirm"
func open(head:Transform3D,commands:Array)->void:
	configure(commands);global_transform=head*Transform3D(Basis.IDENTITY,Vector3(0,-.05,-.85));opened=true;show()
func close()->void:opened=false;hide();current=-1
func show_dialogue(text:String)->void:
	dialogue.text=text;dialogue.show();dialogue_back.show();heading.position.y=.20
	for index in labels.size():
		var angle:=TAU*index/maxi(1,rows.size())-PI*.5
		labels[index].position=Vector3(cos(angle)*.48,sin(angle)*-.34,0)
func choose(stick:Vector2)->void:
	if not opened or rows.is_empty():return
	current=-1 if stick.length()<.45 else posmod(roundi((atan2(-stick.y,stick.x)+PI*.5)/TAU*rows.size()),rows.size())
	for i in labels.size():labels[i].modulate=Color("ffe399") if i==current else Color("9dceea") if rows[i].get("available",false) else Color("67717a")
	heading.text=("Station communications" if dialogue.visible else "Ship commands") if current<0 else str(rows[current].get("label",""))+"\n"+("Trigger to select" if rows[current].get("available",false) else str(rows[current].get("reason","Unavailable")))
func confirm()->bool:
	if not opened or current<0 or not rows[current].get("available",false):return false
	var id:=str(rows[current].get("id",""));close();selected.emit(id);return true
