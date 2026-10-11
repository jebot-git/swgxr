# XR graphics settings

Settings → Graphics provides MSAA, foveation and the desktop mirror selector.
Changes apply immediately and persist in `user://swgxr_graphics.cfg`. Existing
installations keep foveation Off and the third-person mirror by default.

## Foveation

The implementation adapts the local FPSloppa stereo foveation policy and gaze
mask code. Without eye-gaze capability, the menu offers **Fixed foveation:
Off / Low / Medium / High**. With eye-gaze capability it instead offers
**Eye-tracked foveation · sharp region: Off / Small / Medium / Large**.
Both choices are saved independently. Runtime capability changes restore the
appropriate choice; individual invalid gaze samples do not change the menu.

Native OpenXR foveation profiles are used where supported. Otherwise the fixed
path uses Godot's XR VRS map; the gaze path uses a persistent two-layer 128×128
VRS texture on GPUs supporting attachment VRS. Each eye projects the forward
gaze ray through its own view and projection. The sharp region follows gaze;
peripheral shading is limited to 2×2. Generic gaze tracking or focus loss restores
full-rate shading in both eyes. Native gaze behavior remains runtime-owned.
The action map includes the standard `eye_gaze_pose` binding, and the project
requests the eye-gaze and native eye-tracked foveation extensions.

Fixed Low/Medium/High use minimum radii 55/40/25 and strengths 0.5/1.0/1.5.
Gaze Small/Medium/Large use radii 25/40/55 with constant peripheral strength;
native profiles map these sizes to High/Medium/Low. Native and generic profiles
are approximate counterparts, not measured visual equivalents. Off disables
viewport VRS while retaining a nonzero native profile for later swapchain use.

FPSloppa's gaze-following behavior is distinct from OpenXR's
`foveation_dynamic`, which adapts strength to workload. As in FPSloppa, manual
presets disable workload adaptation. No quad-view support is claimed. Only the
headset viewport receives VRS; desktop and menu render targets retain full-rate
shading. `XR_FOVEATION` logs capability and requested/effective viewport policy,
without recording gaze samples or claiming measured GPU savings.

Reference inspection: FPSloppa working tree at commit
`bb5d0b19939ab807186bbb61ca2f1618c0621fe1`:

- `deathmatch/vr/foveation.gd`, SHA-256
  `9cc90edd3ec38427773e438bd965eff4bc5cdc9e0351f30789b080ff0feed051`
- `deathmatch/vr/gaze_vrs.gd`, SHA-256
  `096b14ddd15f75b545ac1b992a374deac5f58ce976bde63492a16c1b726c87bc`
- `docs/XR-FOVEATION.md`, rig integration and foveation tests.

The Godot 4.7.2 source confirms attachment VRS in Forward+ and stereo texture
layers in its VRS conversion. See also the
[OpenXR interface](https://docs.godotengine.org/en/stable/classes/class_openxrinterface.html)
and [VRS documentation](https://docs.godotengine.org/en/stable/tutorials/3d/variable_rate_shading.html).

## Desktop mirror

**Third-person** retains the existing collision-aware 30 FPS observer camera.
**Standard OpenXR · left eye** attaches the existing headset viewport to the
desktop window, invoking OpenXR's native left-eye blit. It disables spectator
render requests and removes its camera from ground and ship-interior visibility
calculations. Window resizing preserves the selected source. Returning to
third-person restores the root window presentation and observer rendering.
The headset camera, tracking transforms and XR viewport ownership do not change.
`--no-spectator` overrides both mirror modes for diagnostic runs.
Desktop play is unaffected.

## Validation (2026-10-11)

- `xr_foveation_smoke.gd`: 125 dummy-renderer checks, including native/generic
  policy, independent gaze sizes, Off→On, stable native profile writes, stereo
  projections, mask sizes, stationary-gaze upload suppression, full-rate tracking
  loss and recovery, and actual OpenXR action-map bindings.
- `settings_navigation_smoke.gd`: 54 checks for real menu controls, capability
  switching, persistence, malformed values and existing settings navigation.
- `xr_spectator_smoke.gd`: switching both mirror modes and the diagnostic
  override, disabled spectator renders, unchanged HMD camera/pose, and existing
  observer collision and frame-rate behavior.
- `xr_menu_pointer_smoke.gd`: existing controller-pointer settings regression.
- `xr_bottleneck_suite_smoke.gd`: 31 existing diagnostic lifecycle checks pass.
- Desktop Forward+ Vulkan Graphics-page capture inspected on Intel Arc A770;
  54 settings checks pass. This validates UI rendering, not XR foveation.

Every invocation uses `--xr-mode off`; no headset was launched. Live OpenXR
mirror output, native density maps, eye-tracked GPU shading and performance
remain hardware-validation work. No FPS improvement is claimed.
