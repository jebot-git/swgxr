# Original media audit through Rage of the Wookiees

The intended content boundary is the original game, Jump to Lightspeed and Rage of the Wookiees. The five supplied Total Experience discs are sufficient to build the current test client locally, but **they do not contain every resource referenced by that content**. This is not a claim of complete expansion rendering or complete original-client parity.

All 58 TRE archives were extracted and hashed on Linux and Windows; the results matched. The combined index has 140,103 distinct paths. The 51 pinned archives retain precedence over the seven additional disc archives: the latter add 14,531 paths and override zero pinned resources. Server archive selection remains unchanged.

The discs include nine Kashyyyk terrain roots: `kashyyyk`, `kashyyyk_main`, `kashyyyk_dead_forest`, `kashyyyk_hunting`, `kashyyyk_north_dungeons`, `kashyyyk_pob_dungeons`, `kashyyyk_rryatt_trail`, `kashyyyk_south_dungeons` and `space_kashyyyk`. These source files are retained for subsequent conversion. This patch does not deploy Kashyyyk gameplay or certify its complete dependency graph. Content beyond Rage of the Wookiees is outside this audit's required scope.

## Which gaps matter?

| Finding | Relevance within the intended scope | Release behavior |
| --- | --- | --- |
| Two `shared_asteroid_molten_mammoth_0{1,2}.iff` templates | Referenced by original JtL asteroid field styles, including the current Dathomir reconstruction; needed for those exact variants | Those variants are omitted, with explicit conversion failures |
| `appearance/corellian_corvette_pob.pob` | Referenced by original corvette interior and player-corvette templates; needed for that interior variant, not every corvette exterior | Affected interior has no converted hull |
| Missing NPC wearables, such as female Tusken gloves and Twi'lek hair s10 | Original NPC CDFs refer to these in existing ground content; needed for exact outfits | Available body/outfit parts remain; incompleteness is recorded; VRM exports reject unresolved visible equipment |
| Missing creature sounds, ship CDFs, and `sound/ui_hover_move.snd` | Original CDFs and the original player sound table contain these references; applicable events cannot play the exact missing cue | No invented replacement; available cues are imported and played |
| Some hair/jacket templates and two building/installation templates | Character tables or backend definitions request absent client templates; each unavailable option needs a source or an explicit scope decision | Failures remain visible in conversion catalogs |
| Particle components and owner-bound clothing preview errors | Source files exist. These are conversion/context limitations, not missing installation media; they include base-game objects and a Kashyyyk ceremonial clothing preview | Reported separately; clothing worn by a character uses its owning material context |

An authored reference does not prove that every original live scenario used it. Conversely, these cannot all be dismissed as later-expansion files: original on-disc JtL, ground NPC and UI data themselves contain the references. Additional installation media cannot be assumed to repair spelling errors or orphaned authoring references. Similar filenames are not silently substituted.

The audit also found preparation defects unrelated to missing media: numeric NPC mood IDs mixed with named moods, and missing faction-reward preview preparation. The converter now uses the default stance for numeric placement moods and prepares the source-defined faction previews and NPCs. Clean-media verification produced all 54 faction reward records; the remaining recruiter appearance gap is an absent original hair mesh.

## Reproduction and evidence

Run against the complete extracted disc set and a prepared asset directory:

```sh
python3 tools/assets/audit_media_scope.py \
  --tre-dir runtime/original-game/tre \
  --assets runtime/assets \
  --output runtime/evidence/media-scope.json
```

The clean conversion audit found 165 unique absent referenced paths; repeated references are kept per catalog. The report records archive SHA-256 values, each failed catalog entry, exact absent paths, and matching referrers found in original IFF/CDF/SND and related resources. It separates absence from conversion/preparation limitations; it is a dependency investigation of the prepared features, not a blanket certification of every archived asset.

The release was checked with a fresh conversion using only the 58 disc archives, without a preconverted distribution. The 46 preparation stages were completed across debug/resume runs; fixes to faction previews and numeric NPC moods were checked against the same clean asset set. Packaged Linux and Windows (Wine) engines exported the saved native equipped-character snapshot as VRM 1.0 from that set. Headless verification does not validate GPU or headset rendering.

Original source data stays local and ignored. The launcher retains every extracted archive and can run newer conversion recipes without redistributing game assets. Missing files still require legitimate user-supplied source data if those exact variants are to be supported later.
