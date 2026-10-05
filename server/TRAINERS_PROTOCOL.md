# Native basic profession trainers

The six original Artisan, Brawler, Entertainer, Marksman, Medic and Scout NPC types use the existing authenticated `/services` bridge. Discovery contains real spawned Core3 NPC object IDs, original templates, source positions and cells. Rendered authored NPCs are reused; appearance variants are not trainer identities.

`POST /services/open` accepts `terminal_id` and the usual owned account/character, source position, building and cell fields. A trainer terminal has `kind: "trainer"`, short `profession`, exact `trainer_type`, localized `trainer_text`, available `skill_points`, and all 18 original skill boxes. Each `skills` row contains:

- `id`, localized `name` and `description`.
- `learned`, `eligible`, and `blocked_reason`.
- `credit_cost`, `skill_point_cost`, `xp_type`, localized `xp_name`, `xp_cost`, and `xp_available`.
- Original required skill IDs in `prerequisites`.

`POST /services/trainer_train` additionally requires `skill_id` and an 8–64 character unique `request_id`. An existing live session is reused through the normal services `session_id`. No independent login is attempted while that character is live. The native receipt includes `skill_id`, `credits_paid`, `xp_spent`, and `skill_points_spent`. Replaying the same request returns its receipt without charging or learning twice; reusing its ID for different input fails.

Native authorization uses the actual AiAgent creature-template identity, the exact catalogue from pinned `trainerData.lua`, the original conversation's five metre and same-cell bounds, and Core3 line-of-sight checks. All prerequisites, species restrictions, XP and available skill points are checked by the original SkillManager. `awardSkill(..., awardRequiredSkills=false, noXpRequired=false)` performs the real mutation, XP deduction, skill-point deduction, abilities, modifiers and schematic updates. Fees follow the original trainer Lua's force-persuade discount and cash-first/bank-remainder payment. The grant and receipt persist through Core3; the adapter never maintains a parallel skill store.

Services snapshots return full owner `skills` with `skills_complete: true`, and full `experience` maps with `experience_complete: true`. Missing XP pools mean zero only when that complete flag is present. Legacy datapad reads decode the actual owner PLAY8 map; live combat snapshots now expose the same complete native XP map instead of the previous two combat pools. Client profession trees can show shared XP pools without treating a learned box's cost as current XP progress.

Source references are local pinned Core3 `scripts/screenplays/trainers/skillTrainer.lua`, `trainerConvHandler.lua`, `trainerData.lua`, `SkillManager.cpp`, and `NpcConversationStartCommand.h`. `tools/server/prepare_trainer_catalog.py` generates the six exact catalogue lists with a source SHA256; it contains public server skill IDs, not copied proprietary data. Names, descriptions and teacher text resolve from the user's original media.

Native verification is `tools/server/trainers_smoke.py`; evidence is `runtime/evidence/trainers-native.json`. Disposable fixture console preparation supplies credits and XP, and uses original administrative grants on a second fixture to exhaust skill points. Actual tested training never bypasses requirements. Live session tests exercise native backend sessions with no live VR launch or headset validation.
