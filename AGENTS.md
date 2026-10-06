# SWGXR rough prototype workflow

Build a VR-first Godot client using standard OpenXR, Godot XR Tools, user-provided SWG assets and a local Core3 backend. Initial hardware is Quest through SteamVR or WiVRn on Linux; keep client XR code runtime-neutral for a possible Windows target. Core3 retains character/persistent RPG systems. Movement, AI and combat need not match the original game. Head/hands and physical posture are tracking-driven. Original or original-derived clips may drive untracked pelvis, spine and legs for locomotion and physical crouching, blended with ground IK; animation must never drive the HMD, controllers or physics body. Desktop mode remains an explicit regression/asset-inspection tool. The current scope supports Forward+ on Vulkan only; standalone VR, Mobile, Compatibility, and other graphics drivers are unsupported. Headless tests use the dummy renderer and must not claim GPU validation.

## Ownership and coordination

- Asset agent: tools/assets; extract the supplied ISOs, audit TRE compatibility, reconstruct a bounded Mos Eisley starport stage, produce local scene data and collision inputs.
- Backend agent: server and tools/server; pinned local Core3 build/runtime, persistent character creation and selection, loopback-only adapter.
- Client agent: client; character UI, asset loading, first-person locomotion, collision and meaningful automated smoke tests.
- Use C++ through GDExtension for reusable locomotion and bulk geometry/collision construction. Keep GDScript for UI and orchestration. Native changes must pass the same actual-stage movement tests.
- Integrator: root scripts, documentation, end-to-end validation, launch workflow and evidence.

Agree on scene manifest and backend API before implementing consumers. Send interface changes to affected agents immediately. Avoid edits in another agent's owned directories without coordination.

## Live test deployment scope

- User direction (2026-10-05): keep the live test server and its testing environment Tatooine-only until the player test server is ready.
- Keep restored planets and interplanetary expansion in local development. Do not deploy or enable planet restoration on the live test VPS as part of unrelated updates.
- More RAM or successful local validation does not lift this hold; wait for the user's direction that the player test server is ready before expanding live planet scope.

## Data and truthfulness

Original media and extracted/converted game assets must remain in ignored local directories. Do not fetch replacement proprietary assets or commit user media. Record source hashes and conversion failures. Never describe a placeholder scene or local JSON character store as a real Core3 integration. An offline asset viewer must be clearly labeled.

## Milestone and verification

The prototype lets a user create a persistent character on local Core3, select it, and enter the reconstructed Mos Eisley starport with streamed Tatooine. XR Tools head/controller tracking, controller UI, locomotion and collision are the primary target; desktop WASD/mouse remains a debug harness. Tests should cover actual backend readiness, creation/selection/persistence, asset provenance, Godot script loading, spawn grounding, collision and entering the scene. Capture rendered evidence when possible.

Record exact blockers such as missing patch TREs separately from code/build failures. Continue independent asset/client work when server provisioning is blocked. Keep services loopback-bound unless the user authorizes network exposure.

Always pass `--xr-mode off` for headless, editor-import, mocked-tracking and desktop render tests; project settings otherwise initialize OpenXR before application code. Keep XR Tools pinned and unmodified through tools/client/install_xr_tools.py. Do not claim mocked tracking or a desktop Vulkan capture validates live headset rendering.
