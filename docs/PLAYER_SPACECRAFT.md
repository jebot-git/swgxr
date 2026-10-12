# Player spacecraft integration

The test.21 JTL patch enables 44 native player templates reachable through
Shipwright chassis deeds or pilot certifications, plus the existing Luxury
Yacht entitlement: **45 templates in total**. Native ownership, certifications,
component compatibility, crafting, redemption fees and launch checks still apply.
Enabling a hull does not grant it or its certification to ordinary accounts.
The original Black Sun light s03 deed referenced nonexistent
`player_ablacksun_light_s03.iff`; the patch corrects that crafting redemption
target to its registered `player_blacksun_light_s03.iff` hull. The original POB
limit also tested the new deed instead of each stored ship when excluding the
Yacht; that check now permits the intended one regular POB plus the Yacht. The
ordinary total-ship cap remains in force.

| Family | Enabled variants |
| --- | --- |
| A-wing | Standard |
| B-wing | Standard |
| X-wing | Standard, including the approved baked central stick |
| Z-95 Headhunter | Standard, basic, prototype |
| Y-wing | Standard, Longprobe |
| TIE Fighter | Standard, basic, prototype, Light Duty, TIE/In |
| Other TIEs | Advanced, Aggressor, Bomber, Interceptor, Oppressor |
| Black Sun light fighters | s01, s02, s03, s04 |
| Black Sun medium fighters | s01, s02, s03, s04 |
| Black Sun heavy fighters | s01, s02, s03, s04 |
| Hutt light fighters | s01, s02, basic, prototype |
| Hutt medium fighters | s01, s02 |
| Hutt heavy fighters | s01, s02 |
| Hutt turret fighter | `hutt_turret_ship` |
| Firespray | Standard |
| VT-49 Decimator | Walkable POB |
| YKL-37R | Walkable POB |
| YT-1300 | Standard and decorated POB |
| Sorosuub Luxury Yacht | Existing walkable, noncombat entitlement |

All 25 ship-certificate names in the supplied skills table were audited. The
original Aggressor template uses the Advanced certificate; its hull is enabled
while that native certification rule is preserved.

The source allowlist is `server/jtl_catalog.py`. Original cockpit/exterior meshes
are prepared for all 40 fighter templates; the other five use original POB rooms,
floors, portals and fixed children. POB pilot positions and cell IDs come from
native chairs. Leaving a station uses native cabin launch points, rather than
the Yacht's coordinates. The original player-corvette fixture has neither a
crafting path nor a pilot certification and remains excluded.

All hulls retain the existing motion-stick, pose-HOTAS and physical-HOTAS input
paths. Authored grab/hand attachment controls are available where a verified
control mesh exists (Z-95/X-wing central sticks and shared TIE/Hutt-light yokes).
This patch does not invent grab handles for the other cockpit meshes. Native
multiseat capacities remain in effect; gunner-turret control and countermeasure
activation are still presentation/control gaps. It is not a claim that every
ship's combat balance or all crew stations have passed gameplay testing.

The Total Experience media supplied all enabled hull/cockpit/POB geometry. One
source appearance, `appearance/pob_station_warning_lighthousing.apt`, is empty;
its decorative fixture occurrences are omitted with provenance in each affected
POB catalog. No missing room, flight control or interactive terminal is accepted
by that exception. Existing missing NPC-corvette and two Dathomir asteroid assets
remain separate documented media gaps.

Collision data must accompany the native patch. After preparing the sectors,
run `python tools/space/prepare_collision.py`. It writes the private generated
`vendor/Core3/MMOCoreORB/bin/conf/swgxr-space-collision.json`; runtime packaging
checks its source hashes against the client sector catalog and includes it with
the server configuration. Launch refuses sectors without collision data.

Flight sweeps the hull radius against native ship/scenery volumes and 17,106
seeded asteroid extents across the ten sectors. Original mesh tests retain holes
in stations; the mesh sweep conservatively stops by at most one quarter of hull
radius before contact. Asteroids use enclosing extents, which may stop a craft
before an irregular rock's visible surface. Held thrust stops on contact until
released or the ship turns away. Native docking/hyperspace motion is separate.
No new collision damage or forced camera rotation is introduced.
