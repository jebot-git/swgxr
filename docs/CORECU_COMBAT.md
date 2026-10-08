# CoreCU combat policy v1

The design target is **pre-CU progression with CU-inspired balance and combat feel**. Keep the pre-CU profession trees, skill-specific XP, training prerequisites, skill-point budget, mixed-profession builds and certification progression. Combat changes should improve damage pacing, armour tradeoffs, resource use, status resistance and encounter roles within that progression structure. CU combat levels, level-based equipment unlocks and player/enemy level-gap damage gates are not the progression target.

CoreCU is the local SWGXR fork of SWGEmu Core3. This pass replaces legacy PvE assumptions that relied on very high armour resistance, gives profession progression meaningful status resistance, and limits personal shields to elemental protection. The existing armour conversion remains the foundation: 8000 armour score gives 50% mitigation, or twice the effective survivability before other effects.

These are **provisional CoreCU values**, not recovered SOE server formulas. Advanced professions retain the Core3 skill boxes, prerequisites, certifications and ability definitions as skeleton templates. This pass adds balance policy around those templates; their remaining ability design and the doctor/buff redesign are deferred.

## Historical basis and limits

The [preserved SOE CU patch notes](https://swgreckoning.org/archive/data/20070126114830/content_001.html) document changes to NPC special-attack use, baseline damage, creature damage ranges, overly strong mission NPCs, and normal versus elite/boss pet statistics. They support treating enemy combat and group encounters separately from player armour conversion. The [post-launch developer interview](https://www.mmorpg.com/interviews/combat-upgrade-qanda-2000113886) describes ordinary solo progression alongside more demanding group content.

No authenticated, complete CU NPC stat table or numeric profession-resistance table was recovered. The formulas below therefore use local Core3 templates as source data with explicit CoreCU conversion. See [the preceding PvE audit](PVE_ARMOUR_STATUS_AUDIT.md) for the wider evidence and original problems. This is not a claim that the entire Core3 HAM, medical, pet or encounter system now reproduces CU.

## Enemy damage and durability

Wild NPCs and creatures use the following level bands. Levels are the existing Core3 template difficulty values, not a new player progression scale. These formulas tune enemy templates independently of player level; player resistance progression comes from learned profession boxes.

| Template level | Damage mean multiplier | Primary HAM multiplier | Special damage multiplier cap | Shared special cooldown |
| --- | ---: | ---: | ---: | ---: |
| 1–30 | 0.45 | 0.65 | 1.5 | 10 seconds |
| 31–80 | 0.55 | 0.80 | 1.5 | 10 seconds |
| 81–150 | 0.70 | 1.00 | 2.0 | 8 seconds |
| 151+ | 0.85 | 1.00 | 2.5 | 6 seconds |

Weapon damage spans 75–125% of the converted template mean. Non-pet primary, secondary, default and generated weapons use the NPC weapon cadence instead of accidentally inheriting unrelated player weapon speed. Special selection falls back to the default attack while the shared cooldown is active. The cooldown begins when a special is queued, including a special that subsequently fails execution.

The old NPC AP damage discount is removed. NPC weapons now pay the same bounded penetration/elemental conversion cost as player weapons; fixed-damage NPC commands also receive the level-band damage conversion. Existing attack lists, targeting and encounter scripts remain in place.

High-level and boss bands retain their original template HAM. They are deliberately not reduced to solo targets. These bands are a first tuning pass, not a guarantee that every template with the same level has equal difficulty. Pet damage, cadence and HAM are excluded from this wild-enemy rebalance.

Enemy resistance uses the armour score curve rather than shrinking legacy percentages into almost indistinguishable values:

```text
bias = clamp((legacy resistance - 30) × 20, -1000, 1000)
legacy vulnerability (-1) gives bias -1000
score = clamp(75 × clamp(level, 1, 80) + 400 × clamp(armour tier, 0, 3) + bias, 0, 8000)
resistance = score / (8000 + score)
```

Species weaknesses and strengths remain bounded differences. No enemy receives 90% body resistance from this conversion. Wild-enemy resistance no longer decays as HAM is depleted; pets retain their original resistance calculation. Damage channels and AP budgets follow [the armour implementation](ARMOUR_IMPLEMENTATION.md).

## Profession and status resistance

The 19 profiles in [corecu_professions.json](../server/combat/corecu_professions.json) cover the existing basic and advanced combat/support trees. They are editable skeleton balance profiles. A novice box contributes 10%, each of the sixteen branch boxes 5%, and master 10% of that profession's profile. Learned skills are read at use time, so unlearning immediately removes the contribution without a persisted bonus migration.

For each status, combine the strongest profession contribution with 25% of all other contributions, capped at 100 rating. Existing native resistance modifiers are retained when stronger rather than added again. Wild NPCs receive rating `min(level × 0.5, 100)`; the shared creature helper also supplies this baseline to AI-controlled pets.

```text
reduction = clamp(rating / (100 + rating), 0, 0.60)
application chance = clamp(original chance, 5, 95) × (1 - reduction)
duration = ceil(original duration × (1 - reduction)), at least 1 second
```

For example, rating 60 reduces application chance and duration by 37.5%; rating 100 reduces them by 50%. Existing stronger skill modifiers can reach the 60% reduction ceiling. Resistance remains valuable without automatically granting immunity. Explicit existing immunity rules remain separate.

Stun, blind, dizzy, intimidate, knockdown/posture changes, attack delay, bleeding, poison, disease and fire use the relevant ratings. NPC-applied command states have an eight-second duration ceiling before resistance. Knockdown/posture effects share an eight-second recovery window. Their recovery delay also scales with resistance. Existing direct Smuggler control effects use the policy; creature-trap debuffs receive a separate resistance roll and reduced duration after the original trap hit roll. Trap direct damage retains its existing template behaviour.

Scout Novice and each Scout trapping box add one percentage point to the second trap status roll (5 total). Each Ranger trapping box and Master Ranger add another point (10 combined). This bonus is applied after resistance, capped at 95%; the original trapping hit roll and resistance-based duration remain. Hard-control traps share the control recovery timer and leave at least two seconds after their duration before another hard-control trap can land, with an eight-second minimum timer. State-defense traps lower the derived resistance floor as well as native modifiers, preserving their usefulness against CoreCU enemies. Trap eligibility remains the existing non-pet creature scope.

The profession catalog displays each box's contribution. Player combat snapshots expose `corecu.name`, policy version/revision and derived profession resistance values. Those displayed values describe the profession profile; a stronger existing native modifier can still prevail during resolution.

## DoTs and wounds

Command and weapon DoTs seed strength from the damage that actually landed, after conversion and mitigation. Their durations are capped at 60 seconds. Each group has a total damage budget of at most 50% of its triggering hit, divided among its effects and expected ticks. Command and weapon groups have separate budgets, so a hit with both can seed up to 100% additional damage before resistance. Rounding, resistance and expiration can reduce the actual result.

Bleed uses a 20-second interval, poison/fire 10, disease 40, and Force Choke 5. A fresh effect schedules its first tick no later than halfway through its shortened duration, preventing short disease effects from expiring without a tick. Subsequent ticks retain their normal cadence. Ticks after expiration are rejected. Force Choke no longer applies shield mitigation a second time to an already mitigated seed. Its existing special potency semantics remain in place.

Weapon poison, disease and fire now use their native defence modifiers as well as profession resistance. Common DoT resistance reduces application chance and duration. Existing explicit immunities, cures, absorption, dissipation and source-based stacking rules remain in place. Negative-potency special effects retain their explicit application-roll exception.

Periodic secondary wounds are capped to the smaller of 10% of the budgeted tick and 1% of the relevant base pool. Disease wound ticks additionally respect remaining wound capacity and the 1% attribute cap. Disease remains a wound effect; this does not replace the medical system or rebalance doctor buffs. Independent scripted DoT producers outside command/weapon combat retain their own strength rules but pass through common resistance handling.

## Elemental-only personal shields

PSGs protect heat, cold, acid and electricity only. Kinetic and energy are primary damage channels and receive no shield mitigation. Legacy blast, stun and lightsaber hits are converted before elemental portions are resolved.

Shield quality is capped at 80 and mapped to at most 50% elemental resistance. For each elemental portion, use the **stronger** of body armour and shield resistance. Do not multiply the two layers. A shield therefore fills an elemental weakness without increasing the combined equipment resistance beyond 50%. Wear and mitigation reporting are attributed to the layer that contributed protection. This keeps the armour/AP survivability bound intact.

## Physical melee guarding

Patch `0071-physical-melee-guard.patch` adds held, directional guards to the ordinary gameplay session. Hold a certified melee weapon across the upper body to parry, or raise both fists beside the face while squeezing grip or trigger to use a boxing guard. A two-handed weapon requires its support grip. Detection uses tracked controller positions and the held weapon's longitudinal axis; it never changes the HMD, controller or physics-body pose.

The pose must settle for 120 ms. A punch or swing drops the local guard. The server independently checks submitted pose geometry, equipped weapon, certification, head proximity, posture and freshness, and imposes another 120 ms arming period after activation or interruption. Standing and kneeling are supported. Lost tracking, UI/focus capture, stowing, equipment changes, attacks and other native session actions invalidate or interrupt the guard. Client samples older than 150 ms cannot refresh it.

Direct melee attacks within 60 degrees of the submitted forward direction can be guarded. Weapon parries reduce damage by 65%; boxing guards reduce it by 45%. Each successful physical block spends Action equal to 10% of incoming pre-armour damage, rounded up, with a minimum cost of 5. If that would exhaust Action, the block fails and guard breaks for 1.2 seconds. Lowering and raising the hands cannot erase this recovery period. Holding the pose alone does not spend Action.

Physical guard and native passive block use the stronger reduction rather than multiplying together. Armour then resolves normally. Ranged, Force, area and cone attacks bypass this physical guard; existing status-effect rolls remain separate. Successful blocks produce native block feedback and a controller haptic when the authoritative receipt arrives.

This is a pose-driven frontal guard, not simulated blade-to-blade collision or a timed perfect-parry mechanic. The normal session refreshes a held guard every 350 ms, subject to existing serialized native requests; the server expires it after 850 ms without a valid refresh. Heavy requests or network delays may therefore drop protection. Client prediction never grants damage immunity.

Patch `0072-live-melee-trap-progression.patch` connects qualified weapon swings and unarmed punches to the owned native session. The server selects one attackable AI creature or lair inside a head-aimed cone with a 15-degree half-angle, using bounded target volume tolerance. Reach is the lesser of native weapon range and 4 m, or 2 m unarmed. It validates current equipment, certification, posture, range and line of sight, and resolves a normal native attack with CoreCU mitigation, threat, death and XP. The cone selects a single target; the resulting normal attack remains eligible for physical guarding.

Both fists and held weapons share native cadence. A committed swing spends native HAM once even when it hits nothing. No client damage or target selection is accepted, and player automatic attacks remain disabled. Default unarmed combat requires the native unarmed weapon; merely stowing a still-equipped ranged weapon does not change native equipment. Advanced profession abilities remain skeletons, and no progression requirements are added.

Confirmed melee and ranged hits provide a stronger controller pulse, alongside the existing swing/fire pulse and physical-block feedback. Successful inventory, crafting, gathering, medic, Scout, service, vehicle and entertainer mutations give a short pulse to the interacting tracked hand. Polling, rejected mutations, lost focus and untracked controllers stay silent. These feedback paths have headless mocked tests, not physical-controller validation.

Validation passed: 60,000 standalone damage/armour combinations plus pose, lease, weapon-change and guard-break cases; 16 mocked-pose client checks; 23 session lifecycle/guard-refresh checks; 22 existing gameplay-combat checks; and 12 Python protocol/session tests. Native combat and command-registration translation units passed syntax checks. These are not linked-server, live encounter or headset tests; the Podman build blocker below still applies.

Basic melee/trap/haptic validation on 2026-10-07: 31 mocked gameplay-combat checks (including shared fist timing, whiffs and confirmed receipts), 23 haptic filtering checks, 16 physical-guard checks, 62 headless ranged regressions and 28 Python protocol/progression/session tests passed. Standalone C++ tests cover cone boundaries, 350 trap progression levels and 7,176 existing CoreCU combinations. Three affected native translation units pass syntax checks, and patch 0072 applies with the complete stack. The gateway socket integration test is blocked by sandbox `PermissionError` when binding loopback; linked/live/VR testing remains unperformed. Evidence: `runtime/evidence/melee-traps-haptics-validation.json`.

## Brawler taunt gesture

Patch 0073 connects two deliberate chest beats to the existing native Brawler taunt. Novice Brawler and the granted `taunt` ability are required; branches, advanced prerequisites, skill modifiers and XP progression remain unchanged. A free clenched hand (grip held, trigger released) must withdraw between taps. Same-hand or alternating beats within 1.25 seconds qualify. Ordinary punches, static guards, menu use and tracking loss do not.

Taunt uses the head reticle, selecting the nearest eligible native AI under it with original 64 m range and LOS. It skips dead, incapacitated, friendly/unattackable, pet, untauntable and already-taunted targets. This is a narrow reticle query, separate from the wider melee swing cone. Existing native HAM, threat, taunt success and duration still apply. Native command recovery is shared with ordinary attack timing; a confirmed threat-state application pulses the completing hand. Advanced combat abilities other than this explicit taunt integration remain provisional.

Validation: 30 mocked gesture/routing checks, 39 gameplay-combat checks, 128 C++ reticle range/edge cases plus priority/invalid-input checks, and 24 Python protocol/progression/session tests passed. Both affected native command-registration units pass syntax checks. Full server linking, live encounters and VR hardware were not tested; see the environment blocker below.

## Identity, installation and validation

[CORECU.json](../server/CORECU.json), the native startup/logger, examination attributes, adapter health and combat snapshots identify the fork as CoreCU. The CMake project and produced server binary are `corecu`. A `core3` compatibility copy keeps existing service launchers working. The upstream target name, `vendor/Core3` directory, Core3 Lua namespace, database names, `core3client` and legacy backend protocol tag remain compatible.

`tools/configure_core3.py` installs the generated policy headers and applies the reproducible patch stack, including `0070-corecu-pve-status.patch`, `0071-physical-melee-guard.patch` and `0072-live-melee-trap-progression.patch`. Omitting `--planets` preserves the configured planet selection. This pass does not deploy or expand the Tatooine-only live environment.

Validation on 2026-10-07:

- 7,176 standalone C++ policy cases passed, covering armour/shield/AP combinations, enemy resistance, level bands, progression, status probabilities/durations and all DoT tick intervals.
- 20 Python tests passed, covering profession contributions, actual Core3 catalog box weights, armour conversion and weapon/unarmed protocol behaviour.
- Native Clang syntax checks passed for ten translation units covering the affected combat, AI, armour, DoT, command-registration and startup translation units. They use the actual generated native headers.
- The complete patch stack applies from the pinned upstream source and configuration completes. Configuration reports one missing source mesh, `appearance/mesh/twk_f_hair_s10.lmg`, in a Twi'lek reward wearable; this is separate from combat compilation.

A linked native build and live encounter validation remain outstanding. Podman cannot start in this session: `Failed to obtain podman configuration: set sticky bit on: chmod /run/user/1000/libpod: read-only file system`. Syntax and arithmetic checks do not establish runtime encounter balance or successful linking. VR testing was skipped as requested. No updated server deployment is claimed.
