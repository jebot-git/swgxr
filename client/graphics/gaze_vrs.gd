extends RefCounted
## Adapted from FPSloppa; see docs/XR_GRAPHICS.md for provenance and limits.
## Stereo gaze shading for generic Vulkan VRS. A persistent two-layer mask
## avoids allocating a new texture on each eye movement. Native density maps
## remain runtime-owned. All gaze math uses the forward ray and each eye view.
const ATTACHMENT_VRS_FEATURE:=2 # Godot 4.7 Features enum; omitted from script constants.
const SIZE:=Vector2i(128,128)
var texture: Texture2DArray
var images: Array[Image]=[]
var kernel: Image
var preset:=-1
var aspect:=1.0
var centers:=PackedVector2Array()
var pixels: Array[Vector2i]=[]
var gaze_valid:=false
var attached:=false
var update_count:=0
static func project_gaze(view: Transform3D,projection: Projection,gaze: Transform3D) -> Vector2:
	var point:=view.affine_inverse()*(gaze.origin-gaze.basis.z*10.0)
	var clip:=projection*Vector4(point.x,point.y,point.z,1)
	if clip.w<=.001 or not clip.is_finite():return Vector2.INF
	return Vector2(clip.x,clip.y)/clip.w
func build(size: int,ratio: float):
	preset=size;aspect=ratio;pixels.clear()
	kernel=Image.create(SIZE.x*2,SIZE.y*2,false,Image.FORMAT_RG8)
	var radius: float=[0.0,.25,.40,.55][size]*SIZE.y*.5
	for y in kernel.get_height():
		for x in kernel.get_width():
			var delta:=Vector2((x-SIZE.x)*ratio,y-SIZE.y)
			var outside: bool=delta.length()>radius
			# 128 encodes 2x2 in Godot's VRS conversion (factor 2); never 4x4.
			kernel.set_pixel(x,y,Color(128.0/255 if outside else 0,128.0/255 if outside else 0,0,1))
	images.clear()
	for eye in 2:images.append(Image.create(SIZE.x,SIZE.y,false,Image.FORMAT_RG8))
	if texture==null:texture=Texture2DArray.new();texture.create_from_images(images)
func supported(xr) -> bool:
	var rd:=RenderingServer.get_rendering_device()
	return xr!=null and xr.is_initialized() and xr.is_eye_gaze_interaction_supported() and not xr.is_foveation_supported() and xr.get_view_count()==2 and rd!=null and rd.has_feature(ATTACHMENT_VRS_FEATURE)

func update(viewport: Viewport,xr,origin: XROrigin3D,gaze: XRController3D,focused: bool,size: int) -> void:
	if not supported(xr) or size==0:
		if attached:
			viewport.vrs_mode=Viewport.VRS_DISABLED
			RenderingServer.viewport_set_vrs_texture(viewport.get_viewport_rid(),RID())
		attached=false;gaze_valid=false;return
	var target: Vector2=xr.get_render_target_size()
	var ratio:=target.x/maxf(1,target.y)
	if preset!=size or not is_equal_approx(aspect,ratio):build(size,ratio)
	if not attached or viewport.vrs_mode!=Viewport.VRS_TEXTURE:
		viewport.vrs_mode=Viewport.VRS_TEXTURE
		viewport.vrs_update_mode=Viewport.VRS_UPDATE_ALWAYS
		RenderingServer.viewport_set_vrs_texture(viewport.get_viewport_rid(),texture.get_rid());attached=true
	var valid: bool=focused and gaze!=null and gaze.get_has_tracking_data()
	update_mask(xr,origin.global_transform,gaze.global_transform if valid else Transform3D.IDENTITY,valid,ratio)

func update_mask(xr,origin: Transform3D,gaze_pose: Transform3D,valid: bool,ratio: float) -> void:
	var changed: bool=gaze_valid!=valid or pixels.is_empty()
	gaze_valid=valid;centers.clear()
	for eye in 2:
		var view: Transform3D=xr.get_transform_for_view(eye,origin)
		var projection: Projection=xr.get_projection_for_view(eye,ratio,.05,100)
		var center:=project_gaze(view,projection,gaze_pose) if valid else Vector2.ZERO
		if not center.is_finite():gaze_valid=false;center=Vector2.ZERO
		centers.append(center.clamp(Vector2(-1,-1),Vector2(1,1)))
	changed=changed or gaze_valid!=valid
	for eye in 2:
		var pixel:=Vector2i(roundi((centers[eye].x+1)*SIZE.x*.5),roundi((1-centers[eye].y)*SIZE.y*.5))
		if changed or pixels.size()<=eye or pixel!=pixels[eye]:
			if gaze_valid:images[eye].blit_rect(kernel,Rect2i(SIZE-pixel,SIZE),Vector2i.ZERO)
			else:images[eye].fill(Color.BLACK) # Full rate through blinks/tracking loss.
			texture.update_layer(images[eye],eye);update_count+=1
		if pixels.size()<=eye:pixels.append(pixel)
		else:pixels[eye]=pixel
