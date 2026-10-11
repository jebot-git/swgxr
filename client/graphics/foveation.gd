extends RefCounted
## Adapted from FPSloppa; see docs/XR_GRAPHICS.md for provenance and limits.
## Stereo foveation only. Quad views require renderer/engine support.
const LABELS=["OFF","LOW","MEDIUM","HIGH"]
const SIZE_LABELS=["OFF","SMALL","MEDIUM","LARGE"]
const FOVEA_RADII=[100.0,25.0,40.0,55.0]
const SIZE_LEVELS=[0,3,2,1]
# Generic Vulkan VRS: keep a broad full-rate center, especially at Low.
# Native runtime profiles use their own matching low/medium/high definitions.
const RADII=[100.0,55.0,40.0,25.0]
const STRENGTHS=[0.1,0.5,1.0,1.5]

static func mode(xr) -> String:
	if xr==null or not xr.is_initialized():return "inactive"
	return "gaze" if xr.is_eye_gaze_interaction_supported() else "static"

static func size_from_level(level: int) -> int:
	return SIZE_LEVELS[clampi(level,0,3)]

static func apply(viewport: Viewport,xr,level: int,fovea_size: int=-1) -> Dictionary:
	level=clampi(level,0,3)
	fovea_size=size_from_level(level) if fovea_size<0 else clampi(fovea_size,0,3)
	var active_mode:=mode(xr)
	var ready: bool=active_mode!="inactive"
	var native: bool=ready and xr.is_foveation_supported()
	var gaze: bool=active_mode=="gaze"
	var applied_level: int=SIZE_LEVELS[fovea_size] if gaze else level
	var radius: float=FOVEA_RADII[fovea_size] if gaze else RADII[level]
	# On generic VRS, size only changes the full-rate radius; peripheral
	# strength stays stable. Native runtimes expose coarse profiles instead.
	var strength: float=1.0 if gaze else STRENGTHS[level]
	if ready:
		if native:
			# "Dynamic" means workload-adaptive strength, not gaze tracking.
			# Manual presets should remain stable; the engine handles gaze separately.
			if xr.foveation_dynamic:xr.foveation_dynamic=false
			# Vulkan allocates native density-map support only with a nonzero
			# profile. Keep it allocated while Off disables the viewport's VRS;
			# otherwise starting/resizing while Off breaks later Off -> On.
			var profile_level: int=applied_level if applied_level>0 else maxi(1,int(xr.foveation_level))
			if xr.foveation_level!=profile_level:xr.foveation_level=profile_level
		if not is_equal_approx(xr.vrs_min_radius,radius):xr.vrs_min_radius=radius
		if not is_equal_approx(xr.vrs_strength,strength):xr.vrs_strength=strength
	viewport.vrs_mode=Viewport.VRS_XR if ready and applied_level>0 else Viewport.VRS_DISABLED
	return {"mode":active_mode,"requested_level":level,"fovea_size":fovea_size,"applied_level":applied_level,"vrs_radius":radius,"vrs_strength":strength,"xr_ready":ready,"runtime_profile":native,"native_profile_level":int(xr.foveation_level) if native else 0,"gaze_supported":gaze,"views":xr.get_view_count() if ready else 0,"vrs_mode":viewport.vrs_mode}

static func description(xr,level: int,fovea_size: int=-1) -> String:
	if xr==null or not xr.is_initialized():return "VR only. Without eye tracking, foveation keeps the center sharp and reduces peripheral detail. Requires a compatible GPU/runtime."
	if mode(xr)=="gaze":
		fovea_size=size_from_level(level) if fovea_size<0 else clampi(fovea_size,0,3)
		if fovea_size==0:return "Eye tracking is available. Foveation is off; full-rate shading is requested throughout the view."
		if xr.is_foveation_supported():return "Larger sizes request a wider sharp region using the headset's foveation presets. Exact size and eye-tracked movement depend on runtime support."
		return "Size of the sharp region around your gaze. Requires GPU VRS support. Larger keeps more detail; smaller reduces shading work. Keeps full detail if gaze is temporarily lost; peripheral shading is limited to 2×2."
	if level==0:return "Foveation is off. Full-rate shading is requested throughout the view."
	if xr.is_foveation_supported():return "Static foveation requested using the headset's presets. Lower levels keep more peripheral detail."
	return "Static foveation requested. Turn your head to inspect peripheral detail, or choose a lower level for clearer edges. Requires GPU VRS support."
