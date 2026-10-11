extends Node
## Attach the existing XR target to the window for OpenXR's native left-eye blit.
## No extra camera/render and no change to the HMD camera or tracking hierarchy.
var window:Window
var headset:SubViewport
var spectator:CanvasLayer
var standard:=false
var screen_attached:=false

func configure(target:Window,xr_target:SubViewport,observer:CanvasLayer)->void:
	window=target;headset=xr_target;spectator=observer
	RenderingServer.frame_pre_draw.connect(sync_screen)

func set_mode(mode:int,disabled:bool=false)->void:
	standard=mode==1 and not disabled
	if is_instance_valid(spectator):spectator.enabled=not standard and not disabled
	sync_screen()

func sync_screen()->void:
	if not is_instance_valid(window) or not is_instance_valid(headset):return
	if DisplayServer.get_name()=="headless":return
	var rect:=Rect2(Vector2.ZERO,Vector2(window.size))
	if standard and headset.use_xr:
		# Window resizing can reattach the root; enforce the chosen source just
		# before drawing so its blank canvas cannot cover the native eye blit.
		RenderingServer.viewport_attach_to_screen(window.get_viewport_rid(),Rect2(),DisplayServer.INVALID_WINDOW_ID)
		RenderingServer.viewport_attach_to_screen(headset.get_viewport_rid(),rect,window.get_window_id())
		screen_attached=true
	elif screen_attached:
		RenderingServer.viewport_attach_to_screen(headset.get_viewport_rid(),Rect2(),DisplayServer.INVALID_WINDOW_ID)
		RenderingServer.viewport_attach_to_screen(window.get_viewport_rid(),rect,window.get_window_id())
		screen_attached=false

func _exit_tree()->void:
	standard=false;sync_screen()
	if RenderingServer.frame_pre_draw.is_connected(sync_screen):RenderingServer.frame_pre_draw.disconnect(sync_screen)
