extends SceneTree
const Holo=preload("res://scripts/datapad_theme.gd")
const Drag=preload("res://scripts/xr_slider_drag.gd")
var errors:Array=[]
var checks:=0
func check(value:bool,message:String)->void:
	checks+=1
	if not value:errors.append(message);push_error(message)
func _initialize()->void:run.call_deferred()
func world_point(surface:Dictionary,pixel:Vector2,depth:float=.03)->Vector3:
	return surface.mesh.to_global(Vector3((pixel.x/surface.viewport.size.x-.5)*surface.meters.x,(.5-pixel.y/surface.viewport.size.y)*surface.meters.y,depth))
func run()->void:
	var origin:XROrigin3D=load("res://xr/player_rig.tscn").instantiate();root.add_child(origin)
	var body:CharacterBody3D=origin.get_node("PlayerBody");body.set_physics_process(false)
	var owner=preload("res://scripts/xr_datapad.gd").new();root.add_child(owner);owner.set_process(false);owner.rig=origin;owner.body=body
	var control:=Control.new();control.size=Vector2(660,660);control.theme=Holo.build();owner.ui=control
	owner.add_surface(control,Vector2i(660,660),Vector2(.66,.66));owner.allowed=true;owner.is_open=true
	var slider:=HSlider.new();control.add_child(slider);slider.position=Vector2(50,200);slider.size=Vector2(560,44);slider.max_value=100;slider.step=1;slider.value=25
	await process_frame
	var surface:Dictionary=owner.surfaces[0]
	var icon:Texture2D=slider.get_theme_icon("grabber","HSlider")
	check(icon.get_width()>=28 and icon.get_height()>=40,"Shared sliders have extended square-corner grabbers")
	var start:=world_point(surface,Drag.handle_rect(slider).get_center())
	owner.slider_frame({},Transform3D(Basis.IDENTITY,start),0,0,true)
	check(owner.slider_frame({},Transform3D(Basis.IDENTITY,start),.8,0,true),"Hand near thumb captures grip without pointer ray")
	check(slider.value==25,"Physical grab does not jump the selected amount")
	var handle:MeshInstance3D=surface.slider_handles[slider.get_instance_id()]
	check(is_equal_approx(handle.mesh.size.z,.018) and handle.visible,"Physical slider has a visible 18 mm square grip")
	check(handle.position.distance_to(surface.mesh.to_local(world_point(surface,Drag.handle_rect(slider).get_center(),.01)))<.0001,"Grip mesh stays aligned with the actual UI thumb")
	owner.slider_frame({},Transform3D(Basis.IDENTITY,start+Vector3(.1,0,0)),.8,0,true)
	check(slider.value>40 and slider.value<50,"Captured hand translation drags amount with no ray hit")
	owner.slider_frame({},Transform3D(Basis.IDENTITY,start+Vector3(5,0,0)),.8,0,true)
	check(slider.value==100,"Physical drag clamps to the authoritative proposal range")
	owner.slider_frame({},Transform3D(Basis.IDENTITY,start),0,0,true)
	check(owner.slider_dragger.capture.is_empty(),"Grip release ends capture without confirming a payment")
	slider.value=25;var distant:=start+Vector3(0,0,.4)
	check(not owner.slider_frame({},Transform3D(Basis.IDENTITY,distant),.8,0,true),"Distant hand cannot grab a slider without reaching it")
	owner.slider_frame({},Transform3D(Basis.IDENTITY,start),0,0,true)
	owner.slider_frame({},Transform3D(Basis.IDENTITY,start),.8,0,true)
	owner.slider_frame({},Transform3D(Basis.IDENTITY,start+Vector3(.1,0,0)),.8,0,false)
	check(owner.slider_dragger.capture.is_empty() and slider.value==25,"Tracking loss cancels drag without changing amount")
	check(not owner.slider_frame({},Transform3D(Basis.IDENTITY,start),.8,0,true),"Tracking recovery needs a fresh grip edge")
	owner.slider_frame({},Transform3D(Basis.IDENTITY,start),0,0,true)
	var pixel:=Vector2(50+14+(560-28)*.8,222)
	var hit:Dictionary={"surface":0,"pixel":pixel,"world":world_point(surface,pixel)}
	check(owner.slider_frame(hit,Transform3D(Basis.IDENTITY,start),0,.8,true) and slider.value==80,"Normal pointer trigger still places the slider on its track")
	owner.slider_frame({},Transform3D(Basis.IDENTITY,start+Vector3(.05,0,0)),0,.8,true)
	check(slider.value>85,"Trigger drag continues by hand translation after finger curl")
	owner.cancel_press();check(owner.slider_dragger.capture.is_empty(),"Closing or cancelling pointer cancels slider ownership")
	slider.editable=false;owner.slider_frame({},Transform3D(Basis.IDENTITY,start),0,0,true)
	check(not owner.slider_frame({},Transform3D(Basis.IDENTITY,start),.8,0,true),"Disabled proposal slider cannot capture a physical hand")
	var services=preload("res://scripts/xr_services.gd").new();root.add_child(services);services.configure(origin,body);services.set_process(false);services.allowed=true
	services.terminal={"id":"fixture","kind":"bank"};services.panel.configure(services.terminal,{"cash":1000,"bank":500});services.surface.show()
	services.panel.slider.amount=250
	var service_surface:Dictionary={"mesh":services.surface,"meters":services.PANEL_METERS,"viewport":services.viewport,"control":services.panel}
	var service_pos:=world_point(service_surface,Drag.handle_rect(services.panel.slider).get_center())
	var physical:Dictionary=services.physical_slider_hit(service_pos)
	check(not physical.is_empty(),"Bank/payment custom slider accepts a hand near the extended thumb")
	services.pointer_frame(physical,0,0);services.pointer_frame(physical,0,.8)
	check(services.pointer_button=="grip" and services.panel.slider.dragging,"Custom slider physical grab retains existing pointer ownership")
	var moved:=physical.duplicate();moved.pixel.x+=100;services.pointer_frame(moved,0,.8)
	check(services.panel.slider.amount>250,"Custom slider drag edits the amount without a confirmation action")
	services.pointer_frame(moved,0,0)
	check(not services.pointer_pressed and not services.panel.slider.dragging,"Custom slider release restores interaction ownership")
	services.set_pending(true)
	check(services.physical_slider_hit(service_pos).is_empty(),"Pending native mutation prevents new physical slider capture")
	var menu=preload("res://scripts/xr_menu.gd").new();root.add_child(menu);menu.set_process(false)
	var content:=Control.new();root.add_child(content);content.theme=Holo.build()
	var setting:=HSlider.new();content.add_child(setting);setting.position=Vector2(200,200);setting.size=Vector2(560,44);setting.value=25
	menu.configure(content,origin.get_node("XRCamera3D"));menu.set_open(true)
	await process_frame
	var menu_surface:Dictionary=menu.slider_surfaces()[0]
	var menu_hand:=world_point(menu_surface,Drag.handle_rect(setting).get_center())
	menu.physical_slider_frame("RightHand",Transform3D(Basis.IDENTITY,menu_hand),0,true)
	check(menu.physical_slider_frame("RightHand",Transform3D(Basis.IDENTITY,menu_hand),.8,true) and not menu.screen.enabled,"Appearance/settings slider grip captures the XR menu without competing pointer clicks")
	menu.physical_slider_frame("RightHand",Transform3D(Basis.IDENTITY,menu_hand+menu_surface.mesh.global_basis.x*.1),.8,true)
	check(setting.value>25,"Menu slider moves by physical hand translation")
	menu.set_input_active(false)
	check(menu.slider_capture_hand.is_empty() and not menu.screen.enabled,"Losing menu input cancels physical ownership")
	menu.set_input_active(true);check(menu.screen.enabled,"Normal XRTools pointer returns after physical capture cancellation")
	menu.free();services.free();owner.free();origin.free()
	print(JSON.stringify({"passed":errors.is_empty(),"checks":checks,"errors":errors,"renderer":"headless dummy","mocked_tracking":true,"native_mutations":false}));quit(0 if errors.is_empty() else 1)
