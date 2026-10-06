# Wenrexa holographic interface

Interface artwork by **Wenrexa**, from [Free UI Hologram Interface](https://opengameart.org/content/free-ui-hologram-interface), published under [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/).

Only empty panel artwork and the four button states are included. No icons from
the pack are included or used. These public-domain interface files are separate
from the user-supplied SWG media held under ignored runtime directories.

PNGs are unchanged from the archive; filenames identify their runtime role.
`provenance.json` records source URLs, the archive hash and every included file's
original archive path and SHA-256. Godot handles scaling, nine-slice margins and
state tinting without baking derivatives.

The shared theme keeps the original blue/cyan hologram palette by tinting the
unchanged artwork at runtime. Panel art uses nine-slice frames; inventory models,
map markers and all existing game imagery retain their original sources.

Holographic lists use discrete joystick selection with automatic reveal; moving
the stick never submits a gameplay action. Map panning and descriptive text retain
continuous scrolling. Sliders keep ordinary pointer input and add near-handle grip
dragging in XR, cancelling capture on release, close or tracking loss.

Local verification uses `--xr-mode off`: `hologram_navigation_smoke.gd`,
`slider_drag_smoke.gd` and the existing inventory, datapad, survey, service,
crafting, factory, harvester, voice and ranger smoke tests. Desktop Forward+ Vulkan
captures verify layout; dummy-renderer and mocked-tracking checks do not verify a
live headset.
