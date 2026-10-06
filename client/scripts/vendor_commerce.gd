extends Node3D
## Local proposals only. Dropping an item opens a draft; Confirm invokes Core3.
const Hands=preload("res://scripts/tracked_hand_input.gd")
var app:Node
var mode:=""
var target:Dictionary={}
var item:Dictionary={}
var draft:Dictionary={}
var rules:Array=[]
var page:=0
var price:=100
var coarse:=0
var fine:=100
var galactic_search:=true
var busy:=false
var epoch:=-1
var generation:=0
var armed:=false
var both_grip_armed:=false
var both_trigger_armed:=false
var gesture_vendor:=""
var controls:Array=[]
var grabbed:=-1
var gripping:=false
var knob:MeshInstance3D
var knob_angle:=0.0
var knob_accum:=0.0
var title:Label3D
var note:Label3D
var preview:MeshInstance3D
var root_ui:Node3D
var action_buttons:Dictionary={}
var assets=preload("res://scripts/inventory_assets.gd").new()
var palettes:Dictionary={}
var uncertain:Dictionary={}
func setup(host:Node)->void:
	app=host;epoch=app.datapad_epoch;process_priority=122;assets.configure()
	var path:="res://../runtime/assets/vendors/customization.json"
	if FileAccess.file_exists(path):
		var parsed:Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary:palettes=parsed
	root_ui=Node3D.new();add_child(root_ui);root_ui.hide()
func reset()->void:
	generation+=1;epoch=app.datapad_epoch;busy=false;uncertain.clear();close();both_grip_armed=false;both_trigger_armed=false;gesture_vendor=""
func blocks_interactions()->bool:return busy or not mode.is_empty()
func close()->void:
	mode="";target.clear();item.clear();draft.clear();rules.clear();controls.clear();action_buttons.clear();grabbed=-1;gripping=false;armed=false
	for child in root_ui.get_children():child.queue_free()
	preview=null;knob=null;title=null;note=null;root_ui.hide()
func material(color:Color)->StandardMaterial3D:
	var m:=StandardMaterial3D.new();m.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;m.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;m.albedo_color=color;return m
func box(where:Vector3,extent:Vector3,color:Color)->MeshInstance3D:
	var node:=MeshInstance3D.new();var mesh:=BoxMesh.new();mesh.size=extent;node.mesh=mesh;node.material_override=material(color);root_ui.add_child(node);node.position=where;node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;return node
func label(text:String,where:Vector3,size:=23)->Label3D:
	var node:=Label3D.new();root_ui.add_child(node);node.font=preload("res://resources/fonts/Jupiteroid-Regular.ttf");node.text=text;node.position=where;node.font_size=size;node.pixel_size=.001;node.modulate=Color("c1f9ff");return node
func market_records()->Array:
	if not is_instance_valid(app.services) or app.services.state_age>8:return []
	var rows:Array=app.services.state.get("terminals",[]).filter(func(row):return row.get("kind","")=="bazaar")
	if is_instance_valid(app.vendor_placement):rows.append_array(app.vendor_placement.records.values())
	var identity:Dictionary=app.services.identity_payload()
	return rows.filter(func(row):return str(row.get("building_id","0"))==str(identity.building_id) and int(row.get("cell_index",0))==int(identity.cell_index) and app.player.global_position.distance_to(app.services.world(row.position))<=3)
func touches(row:Dictionary,point:Vector3)->bool:
	var id:=str(row.get("id",""))
	if row.get("kind","")=="vendor" and is_instance_valid(app.vendor_placement):
		var visual:MeshInstance3D=app.vendor_placement.placed.get(id)
		if is_instance_valid(visual):return visual.mesh.get_aabb().grow(.16).has_point(visual.to_local(point))
	return point.distance_to(app.services.world(row.position)+Vector3.UP*.9)<.7
func try_drop(held_item:Dictionary,pose:Transform3D)->bool:
	if held_item.get("gathering_hip",false) or blocks_interactions() or not app.world_ready or not pose.is_finite() or app.owned_inventory_item(str(held_item.get("id",""))).is_empty():return false
	for row:Dictionary in market_records():
		if not touches(row,pose.origin):continue
		# A vendor owned by somebody else is not an authorized sale destination.
		if row.get("kind","")=="vendor" and str(row.get("owner_id",""))!=app.datapad_character_id:
			app.inventory.finish_item_action(false);app.inventory.set_busy(false,"Only the vendor owner can stock it.");return true
		app.inventory.finish_item_action(true);app.inventory.set_open(false);app.update_inventory_presentation()
		open_sale(row,held_item);return true
	return false
func anchor(row:Dictionary)->void:
	var position:Vector3=app.services.world(row.position)
	var eye:Vector3=app.player.global_position+Vector3.UP*1.5
	if app.xr_requested:eye=app.xr_origin.get_node("XRCamera3D").global_position
	var forward:=eye-position;forward.y=0
	if forward.length_squared()<.001:forward=Vector3.BACK
	forward=forward.normalized();root_ui.global_position=position+forward*.6+Vector3.UP*1.2
	root_ui.global_basis=Basis.looking_at(-forward,Vector3.UP)
	root_ui.show()
	if is_instance_valid(app.services.ui):app.services.ui.set_allowed(false)
	if is_instance_valid(app.combat_rig):app.combat_rig.stow()
func open_sale(row:Dictionary,held_item:Dictionary)->void:
	close();mode="sale";target=row.duplicate(true);item=held_item.duplicate(true);price=100;coarse=0;fine=100;galactic_search=true;var prior:Dictionary=uncertain.get(("vendor_sell" if row.get("kind","")=="vendor" else "bazaar_sell")+":"+str(held_item.id),{})
	if not prior.is_empty():coarse=int(prior.price)/1000;fine=int(prior.price)%1000;galactic_search=prior.galactic_search
	anchor(row);build()
func open_customization(row:Dictionary)->void:
	close();mode="customize";target=row.duplicate(true);draft=row.get("customization",{}).duplicate(true);rules=row.get("customization_controls",[]).duplicate(true);page=0
	var prior:Dictionary=uncertain.get("vendor_customize:"+str(row.id),{})
	if not prior.is_empty():draft.merge(prior.customization,true)
	anchor(row);build()
func rule_metadata(rule:Dictionary)->Dictionary:
	for value:Dictionary in palettes.get(str(target.get("template","")),[]):
		if str(value.get("id","" )).get_file()==str(rule.id).get_file():return value
	return {}
func add_slider(key:String,text:String,y:float,allowed:Array=[])->void:
	var track:=box(Vector3(0,y,0),Vector3(.36,.009,.008),Color(.15,.6,.75,.65))
	var handle:=box(Vector3(0,y,.01),Vector3(.016,.029,.015),Color(.7,1,1,.9))
	var readout:=label(text,Vector3(0,y+.032,.005),19)
	controls.append({"key":key,"track":track,"handle":handle,"label":readout,"allowed":allowed})
	if mode=="customize":
		var metadata:=rule_metadata({"id":key});var colors:Array=metadata.get("colors",[])
		if colors.size()>1 and allowed.size()>1:
			var gradient:=Gradient.new();var points:=PackedColorArray();var offsets:=PackedFloat32Array()
			for i in range(allowed.size()):
				var color:Array=colors[clampi(int(allowed[i]),0,colors.size()-1)]
				points.append(Color(color[0],color[1],color[2],1));offsets.append(float(i)/(allowed.size()-1))
			gradient.colors=points;gradient.offsets=offsets
			var texture:=GradientTexture1D.new();texture.gradient=gradient
			track.material_override.albedo_color=Color.WHITE;track.material_override.albedo_texture=texture
func build()->void:
	for child in root_ui.get_children():child.queue_free()
	controls.clear();action_buttons.clear();grabbed=-1;gripping=false;knob=null;preview=null
	box(Vector3(0,0,-.018),Vector3(.59,.66,.008),Color(.015,.12,.17,.55))
	title=label("SELL · "+str(item.get("name","Item")) if mode=="sale" else "CUSTOMIZE · "+str(target.get("name","Vendor")),Vector3(0,.285,.01),25)
	note=label("",Vector3(0,-.205,.01),18)
	if mode=="sale":
		add_slider("coarse","",.14);add_slider("fine","",.025)
		knob=MeshInstance3D.new();var cylinder:=CylinderMesh.new();cylinder.top_radius=.024;cylinder.bottom_radius=.024;cylinder.height=.025;knob.mesh=cylinder;knob.material_override=material(Color(.2,.8,1,.8));root_ui.add_child(knob);knob.position=Vector3(-.16,-.115,.03);knob.rotation.x=PI/2
		label("Galactic search\nGrip and turn",Vector3(.04,-.10,.01),20)
	else:
		for i in range(page*4,mini(page*4+4,rules.size())):
			var rule:Dictionary=rules[i];add_slider(str(rule.id),"",.17-(i-page*4)*.095,rule.allowed)
		if rules.is_empty():note.text="This original model has no editable appearance controls."
		for direction in [-1,1]:
			var key:="previous" if direction<0 else "next";action_buttons[key]=box(Vector3(direction*.24,.235,.01),Vector3(.045,.04,.025),Color(.15,.65,.8,.7));label("‹" if direction<0 else "›",Vector3(direction*.24,.235,.028),26)
	for key in ["cancel","confirm"]:
		var x:=-.145 if key=="cancel" else .145
		action_buttons[key]=box(Vector3(x,-.285,.01),Vector3(.23,.055,.025),Color(.1,.5,.65,.8));label(key.capitalize(),Vector3(x,-.285,.028),23)
	update_controls();update_preview()
func update_controls()->void:
	var limit:=99999999 if target.get("kind","")=="vendor" else 20000
	price=clampi(coarse*1000+fine,1,limit)
	for control:Dictionary in controls:
		var fraction:=0.0
		if mode=="sale":
			fraction=float(coarse)/maxi(1,int(limit/1000)) if control.key=="coarse" else float(fine)/999
			control.label.text=("Thousands: %d"%coarse) if control.key=="coarse" else ("Credits: %d"%fine)
		else:
			var choices:Array=control.allowed;var metadata:=rule_metadata({"id":control.key});var value:=int(draft.get(control.key,metadata.get("default",choices[0])))
			fraction=float(maxi(0,choices.find(value)))/maxi(1,choices.size()-1)
			control.label.text=str(metadata.get("label",str(control.key).get_file().replace("_"," ")))+": "+str(value)
		control.handle.position.x=lerpf(-.18,.18,fraction)
	if mode=="sale":note.text="%d credits · Galactic search %s\nTouch Confirm + trigger to list"%[price,"ON" if galactic_search else "OFF"]
	elif not rules.is_empty():note.text="Grip sliders · Touch Confirm + trigger\nPage %d / %d"%[page+1,maxi(1,ceili(rules.size()/4.0))]
func update_preview()->void:
	if mode=="customize" and is_instance_valid(preview):
		assets.apply_morphs(preview,draft)
		for i in range(preview.mesh.get_surface_count()):
			var material:Material=preview.get_surface_override_material(i)
			if material==null:
				material=preview.mesh.surface_get_material(i).duplicate()
				preview.set_surface_override_material(i,material)
			if material is ShaderMaterial:preload("res://scripts/avatar_materials.gd").apply(material,draft)
		return
	if is_instance_valid(preview):preview.queue_free()
	var row:Dictionary=item if mode=="sale" else target
	preview=assets.instance(str(row.get("template","")),.43,row.get("customization",{}) if mode=="sale" else draft)
	if preview!=null:root_ui.add_child(preview);preview.position+=Vector3(.58,.02,.04);preview.rotation.y=.4
func change_slider(index:int,local_x:float)->void:
	var control:Dictionary=controls[index];var fraction:=clampf((local_x+.18)/.36,0,1)
	if mode=="sale":
		if control.key=="coarse":
			var next:=roundi(fraction*(99999 if target.get("kind","")=="vendor" else 20))
			if next==coarse:return
			coarse=next
		else:
			var next:=roundi(fraction*999)
			if next==fine:return
			fine=next
	else:
		var choices:Array=control.allowed;var next:=int(choices[roundi(fraction*(choices.size()-1))])
		if draft.get(control.key,-1)==next:return
		draft[control.key]=next
		for rule:Dictionary in rules:
			if str(rule.id)==str(control.key) and int(draft[control.key])!=0 and not str(rule.get("pair","")).is_empty():draft[str(rule.pair)]=0
		update_preview()
	update_controls()
func editor_frame(tracked:bool,hand:Transform3D,grip:float,trigger:float)->void:
	if mode.is_empty():return
	if not tracked or not hand.is_finite():close();return
	if busy:return
	var p:=root_ui.to_local(hand.origin)
	if grip<.35:gripping=false;grabbed=-1
	elif grip>=.65 and not gripping:
		gripping=true
		if is_instance_valid(knob) and hand.origin.distance_to(knob.global_position)<.065:grabbed=-2;knob_angle=twist(hand);knob_accum=0
		else:
			for i in range(controls.size()):
				if absf(p.x)<=.22 and absf(p.y-controls[i].track.position.y)<.035 and absf(p.z)<.08:grabbed=i;break
	if gripping and grabbed>=0:change_slider(grabbed,p.x)
	if gripping and grabbed==-2:
		var angle:=twist(hand);knob_accum+=wrapf(knob_angle-angle,-PI,PI);knob_angle=angle
		if absf(knob_accum)>=deg_to_rad(25):galactic_search=knob_accum>0;knob_accum=0;knob.rotation.z=deg_to_rad(-35 if galactic_search else 35);update_controls()
	if trigger<.3:armed=true
	if trigger<.55 or not armed or gripping:return
	armed=false
	for key in action_buttons:
		if hand.origin.distance_to(action_buttons[key].global_position)>.07:continue
		if key=="cancel":close()
		elif key=="confirm":submit()
		elif mode=="customize":page=clampi(page+(-1 if key=="previous" else 1),0,maxi(0,ceili(rules.size()/4.0)-1));build()
		return
func twist(hand:Transform3D)->float:
	var axis:=root_ui.global_basis.inverse()*hand.basis.x
	return atan2(axis.y,axis.x)
func submit()->void:
	if busy or mode.is_empty() or not app.services.allowed or app.services.busy:return
	var action:="vendor_customize" if mode=="customize" else "vendor_sell" if target.get("kind","")=="vendor" else "bazaar_sell"
	var request:Dictionary={"vendor_id":str(target.id),"customization":{}} if mode=="customize" else {"terminal_id":str(target.id),"item_id":str(item.id),"price":price,"auction":false,"galactic_search":galactic_search}
	if mode=="customize":
		if rules.is_empty():return
		for rule:Dictionary in rules:
			if draft.has(str(rule.id)):request.customization[str(rule.id)]=int(draft[str(rule.id)])
	await mutate(action,request)
func mutate(action:String,request:Dictionary)->void:
	if busy or app.services.busy or not app.services.allowed:return
	var identity:=action+":"+str(request.get("item_id",request.get("vendor_id","")))
	# Ambiguous retries retain exactly the same proposal and receipt identifier.
	if uncertain.has(identity):request=uncertain[identity].duplicate(true)
	else:request.request_id="commerce-"+Crypto.new().generate_random_bytes(16).hex_encode()
	uncertain[identity]=request.duplicate(true);busy=true;var version:=generation
	if is_instance_valid(note):note.text="Waiting for Core3…"
	var response:Dictionary=await app.services.request(action,request)
	if version!=generation:return
	busy=false
	var confirmed:bool=response.get("ok",false) and response.get("mutation",{}).get("success",false) and response.get("mutation",{}).get("request_id","")==request.request_id
	if confirmed:uncertain.erase(identity)
	var message:="Vendor recovered." if action=="vendor_recover" else "Vendor appearance saved." if action=="vendor_customize" else "Item listed for sale."
	if not confirmed:message=str(response.get("error","Core3 did not confirm the operation. Retry keeps the original proposal."))
	close();app.datapad.ui.set_status(message);app.services.poll_clock=0.0
func gesture_frame(tracked:bool,left:Transform3D,right:Transform3D,grips:Vector2,triggers:Vector2)->void:
	if blocks_interactions():return
	if not tracked or not left.is_finite() or not right.is_finite():both_grip_armed=false;both_trigger_armed=false;gesture_vendor="";return
	var row:Dictionary={}
	for record:Dictionary in market_records():
		if record.get("kind","")=="vendor" and str(record.get("owner_id",""))==app.datapad_character_id and touches(record,left.origin) and touches(record,right.origin):row=record;break
	if row.is_empty():gesture_vendor="";both_grip_armed=false;both_trigger_armed=false;return
	if str(row.id)!=gesture_vendor:gesture_vendor=str(row.id);both_grip_armed=false;both_trigger_armed=false
	if grips.x<.35 and grips.y<.35:both_grip_armed=true
	if triggers.x<.3 and triggers.y<.3:both_trigger_armed=true
	if triggers.x>=.55 and triggers.y>=.55 and both_trigger_armed:
		both_trigger_armed=false;both_grip_armed=false;open_customization(row)
	elif grips.x>=.65 and grips.y>=.65 and both_grip_armed and triggers.x<.3 and triggers.y<.3:
		both_grip_armed=false;both_trigger_armed=false
		mutate("vendor_recover",{"vendor_id":str(row.id)})
func _process(_delta:float)->void:
	if epoch!=app.datapad_epoch:reset()
	if not app.world_ready or app.loading_stage or app.session_leaving or app.menu.visible or not app.xr_requested:
		if not mode.is_empty():close()
		both_grip_armed=false;both_trigger_armed=false;return
	var left:XRController3D=app.xr_origin.get_node("LeftHand");var right:XRController3D=app.xr_origin.get_node("RightHand")
	var tracker=XRServer.get_tracker("head");var head:XRPose=tracker.get_pose("default") if tracker!=null else null
	var tracked:bool=app.xr_focused and head!=null and head.has_tracking_data and Hands.controller_tracked(left) and Hands.controller_tracked(right)
	if not mode.is_empty():
		if app.player.global_position.distance_to(app.services.world(target.position))>3:close();return
		var main:XRController3D=right if app.vr_settings.offhand=="left" else left
		editor_frame(tracked,main.global_transform,main.get_float("grip"),main.get_float("trigger"))
	elif not busy and app.inventory.held_item.is_empty() and not app.inventory.is_open and not app.datapad.is_open and not app.vendor_placement.blocks_interactions():
		gesture_frame(tracked,left.global_transform,right.global_transform,Vector2(left.get_float("grip"),right.get_float("grip")),Vector2(left.get_float("trigger"),right.get_float("trigger")))
