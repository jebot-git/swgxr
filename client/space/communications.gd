extends Node3D
## Original mission receipts, readable without opening a modal during flight.
var seen:Dictionary={}
var lines:Array[Dictionary]=[]
var label:Label3D
func _ready()->void:
	label=Label3D.new();label.font=preload("res://resources/fonts/Jupiteroid-Regular.ttf");label.font_size=32;label.pixel_size=.0012;label.width=650;label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;label.no_depth_test=true;label.modulate=Color("a8ddff");add_child(label);hide()
func receive(rows:Array,audio:Node=null)->void:
	# Native receipts are newest-first. Preserve original arrival order.
	for index in range(rows.size()-1,-1,-1):
		var row:Dictionary=rows[index];var id:=str(row.get("id",""))
		if id.is_empty() or seen.has(id):continue
		seen[id]=true
		if float(row.get("age_seconds",0))>15:continue
		if row.get("kind")=="music":
			if is_instance_valid(audio) and audio.catalog.get("sounds",{}).has(str(row.get("sound",""))):audio.request_music(str(row.sound))
		elif not str(row.get("text","")).is_empty():
			lines.append({"text":(str(row.sender)+": " if not str(row.get("sender","")).is_empty() else "")+str(row.text),"expires":Time.get_ticks_msec()+12000})
			while lines.size()>3:lines.pop_front()
	while seen.size()>128:seen.erase(seen.keys()[0])
func update_view(head:Transform3D,allowed:bool)->void:
	while not lines.is_empty() and Time.get_ticks_msec()>int(lines[0].expires):lines.pop_front()
	visible=allowed and not lines.is_empty()
	if not visible:return
	global_transform=head*Transform3D(Basis.IDENTITY,Vector3(0,.48,-2))
	var text:PackedStringArray=[]
	for row:Dictionary in lines:text.append(row.text)
	label.text="INCOMING TRANSMISSION\n"+"\n".join(text)
func clear()->void:
	lines.clear();seen.clear();hide()
