extends RefCounted
## Proposal-only physical slider capture. No inventory/server mutation is performed.
var capture:Dictionary={}
var grip_ready:=false
var trigger_ready:=false
func cancel()->void:
	capture={};grip_ready=false;trigger_ready=false
static func controls(root:Control)->Array:
	var result:Array=[]
	if root is HSlider or root.has_method("handle_rect"):result.append(root)
	for child in root.find_children("*","Control",true,false):
		if child is HSlider or child.has_method("handle_rect"):result.append(child)
	return result
static func enabled(control:Control)->bool:
	return control.is_visible_in_tree() and (control.editable and control.max_value>control.min_value if control is HSlider else bool(control.get("enabled")))
static func clipped_rect(control:Control,rect:Rect2)->Rect2:
	if not control.is_visible_in_tree() or preload("res://scripts/frontend_choice.gd").active(control.get_viewport()):return Rect2()
	var bounds:=Rect2(Vector2.ZERO,control.get_viewport_rect().size)
	var parent:=control.get_parent()
	while parent!=null:
		if parent is Control and parent.clip_contents:bounds=bounds.intersection(parent.get_global_rect())
		parent=parent.get_parent()
	return rect.intersection(bounds)
static func visible_handle(control:Control)->bool:
	var rect:=handle_rect(control)
	# A partly clipped thumb remains in the 2D canvas; omit its 3D extrusion.
	return rect.has_area() and clipped_rect(control,rect).encloses(rect)
static func handle_rect(control:Control)->Rect2:
	if not control is HSlider:return control.get_global_transform()*control.handle_rect()
	var icon:Texture2D=control.get_theme_icon("grabber","HSlider")
	var thumb:Vector2=icon.get_size()
	var point:=Vector2(thumb.x*.5+control.ratio*maxf(1,control.size.x-thumb.x),control.size.y*.5)
	return control.get_global_transform()*Rect2(point-thumb*.5,thumb)
static func hand_pixel(surface:Dictionary,position:Vector3)->Vector2:
	var p:Vector3=surface.mesh.to_local(position)
	return Vector2((p.x/surface.meters.x+.5)*surface.viewport.size.x,(.5-p.y/surface.meters.y)*surface.viewport.size.y)
static func near_handle(surface:Dictionary,position:Vector3)->Dictionary:
	var p:Vector3=surface.mesh.to_local(position)
	if absf(p.z)>.075:return {}
	var pixel:=hand_pixel(surface,position)
	var padding:=Vector2(.014/surface.meters.x*surface.viewport.size.x,.014/surface.meters.y*surface.viewport.size.y)
	for control:Control in controls(surface.control):
		if not enabled(control) or not visible_handle(control):continue
		var rect:=handle_rect(control)
		if rect.grow_individual(padding.x,padding.y,padding.x,padding.y).has_point(pixel):return {"control":control,"pixel":rect.get_center()}
	return {}
func frame(surfaces:Array,hit:Dictionary,pose:Transform3D,grip:float,trigger:float,available:bool)->bool:
	if not available:cancel();return false
	if grip<.35:grip_ready=true
	if trigger<.35:trigger_ready=true
	if not capture.is_empty():
		var slider:HSlider=capture.control
		if not is_instance_valid(slider) or not enabled(slider) or not clipped_rect(slider,slider.get_global_rect()).has_area():cancel();return true
		if (grip<.35 if capture.button=="grip" else trigger<.35):capture={};return true
		var surface:Dictionary=surfaces[capture.surface]
		var pixel:=hand_pixel(surface,pose.origin)
		slider.ratio=clampf(float(capture.ratio)+(pixel.x-float(capture.anchor_x))/maxf(1,slider.size.x-slider.get_theme_icon("grabber","HSlider").get_width()),0,1)
		return true
	var candidate:Dictionary={}
	var button:=""
	if grip>=.65 and grip_ready:
		grip_ready=false
		for index in range(surfaces.size()):
			candidate=near_handle(surfaces[index],pose.origin)
			if not candidate.is_empty() and candidate.control is HSlider:candidate.surface=index;button="grip";break
			candidate={}
	elif trigger>=.55 and trigger_ready:
		trigger_ready=false
		if not hit.is_empty():
			for control:Control in controls(surfaces[int(hit.surface)].control):
				if control is HSlider and enabled(control) and clipped_rect(control,control.get_global_rect()).has_point(hit.pixel):candidate={"control":control,"surface":int(hit.surface),"pixel":hit.pixel};button="trigger";break
	if candidate.is_empty():return false
	var slider:HSlider=candidate.control
	if button=="trigger":
		var local:Vector2=slider.get_global_transform().affine_inverse()*Vector2(candidate.pixel)
		var width:float=slider.get_theme_icon("grabber","HSlider").get_width()
		slider.ratio=clampf((local.x-width*.5)/maxf(1,slider.size.x-width),0,1)
	capture={"control":slider,"surface":candidate.surface,"button":button,"ratio":slider.ratio,"anchor_x":hand_pixel(surfaces[candidate.surface],pose.origin).x}
	return true

static var custom_thumb:Texture2D
static func sync_handles(surfaces:Array)->void:
	# The front repeats the square UI thumb; translucent sides expose 18 mm of
	# physical depth without obscuring the track or changing its hit coordinates.
	if custom_thumb==null:custom_thumb=preload("res://scripts/datapad_theme.gd").slider_handle()
	for surface:Dictionary in surfaces:
		if not surface.has("slider_handles"):surface.slider_handles={}
		var retained:Array=[]
		for control:Control in controls(surface.control):
			var id:int=control.get_instance_id();retained.append(id)
			var handle:MeshInstance3D=surface.slider_handles.get(id)
			if not is_instance_valid(handle):
				handle=MeshInstance3D.new();handle.mesh=BoxMesh.new();handle.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				var side:=StandardMaterial3D.new();side.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;side.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;side.albedo_color=Color(.12,.65,.88,.28);handle.material_override=side
				var front:=MeshInstance3D.new();front.name="Thumb";front.mesh=QuadMesh.new();front.position.z=.0092;front.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				var ink:=StandardMaterial3D.new();ink.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;ink.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;ink.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR;front.material_override=ink
				handle.add_child(front);surface.mesh.add_child(handle);surface.slider_handles[id]=handle
			handle.visible=visible_handle(control)
			if not handle.visible:continue
			var rect:=handle_rect(control)
			var meters:=Vector2(rect.size.x/surface.viewport.size.x*surface.meters.x,rect.size.y/surface.viewport.size.y*surface.meters.y)
			var pixel:=rect.get_center()
			handle.position=Vector3((pixel.x/surface.viewport.size.x-.5)*surface.meters.x,(.5-pixel.y/surface.viewport.size.y)*surface.meters.y,.01)
			handle.mesh.size=Vector3(meters.x,meters.y,.018)
			var front:MeshInstance3D=handle.get_node("Thumb");front.mesh.size=meters
			front.material_override.albedo_texture=control.get_theme_icon("grabber" if control.editable else "grabber_disabled","HSlider") if control is HSlider else custom_thumb
		for id in surface.slider_handles.keys():
			if id not in retained:
				if is_instance_valid(surface.slider_handles[id]):surface.slider_handles[id].queue_free()
				surface.slider_handles.erase(id)
