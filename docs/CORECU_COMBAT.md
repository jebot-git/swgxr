# CoreCU combat policy v1

The design target is **pre-CU progression with CU-inspired balance and combat feel**. Keep the pre-CU profession trees, skill-specific XP, training prerequisites, skill-point budget, mixed-profession builds and certification progression. Combat changes should improve damage pacing, armour tradeoffs, resource use, status resistance and encounter roles within that progression structure. CU combat levels, level-based equipment unlocks and player/enemy level-gap damage gates are not the progression target.

CoreCU is the local SWGXR fork of SWGEmu Core3. This pass replaces legacy PvE assumptions that relied on very high armour resistance, gives profession progression meaningful status resistance, and limits personal shields to elemental protection. The existing armour conversion remains the foundation: 8000 armour score gives 50% mitigation, or twice the effective survivability before other effects.

These are **provisional CoreCU values**, not recovered SOE server formulas. Advanced professions retain the Core3 skill boxes, prerequisites, certifications and ability definitions as skeleton templates. This pass adds balance policy around those templates; their remaining ability design is deferred. The first Medic/Doctor and HAM/SAC pass is described below.

## Historical basis and limits

The [preserved SOE CU patch notes](https://swgreckoning.org/archive/data/20070126114830/content_001.html) document changes to NPC special-attack use, baseline damage, creature damage ranges, overly strong mission NPCs, and normal versus elite/boss pet statistics. They support treating enemy combat and group encounters separately from player armour conversion. The [post-launch developer interview](https://www.mmorpg.com/interviews/combat-upgrade-qanda-2000113886) describes ordinary solo progression alongside more demanding group content.

No authenticated, complete CU NPC stat table or numeric profession-resistance table was recovered. The formulas below therefore use local Core3 templates as source data with explicit CoreCU conversion. See [the preceding PvE audit](PVE_ARMOUR_STATUS_AUDIT.md) for the wider evidence and original problems. This is not a claim that the entire Core3 HAM, medical, pet or encounter system now reproduces CU.

## Health, resources and medicine: first pass (2026-10-08)

The user approved Health as the only player survival pool, with Action and Mind as resources. Ordinary combat involving a player now directs damage to Health and removes legacy pool spillover. Scripted Action/Mind damage and resource DoTs can drain those resources without incapacitating. Health depletion still uses native incapacitation/death rules. Pre-CU skills, prerequisites, certifications and equipment remain in place.

The provisional baseline is **3000 Health, 1000 Action, 1000 Mind**, with secondary attributes at 300. A versioned migration runs during native restoration or first gameplay-session start. It stores original base attributes, preserves effective-pool and wound fractions, and rebases old Doctor HAM enhancements to the cap below without filling pools or extending their remaining time. Dead, incapacitated and Sedative-withdrawal characters defer migration until eligible. This is an explicit local balance baseline, not a recovered CU stat table.

Recovery times in the table are before skill bonuses: the relevant treatment-speed rating reduces them by up to 25% at 100 rating. Heal Damage takes the stronger injury/ranged speed; Wound Medpack and enhancement use wound speed. Other treatments use injury speed.

Standing regeneration per second is 2% base Health and 4% base Action/Mind outside combat; in combat it is 0% Health, 1% Action and 0.8% Mind. Existing posture and spice multipliers apply. Ordinary weapon SAC transfers its former Health charge to Action and halves Mind cost. The retained secondary attributes reduce costs by at most 25% over their 300–600 range, so high attributes cannot make attacks free. Strength discounts the Health-derived Action component before transfer; Quickness discounts the original Action component. Constitution/Stamina/Willpower modify the corresponding regeneration rate by their relative change from base, capped at ±25%. These retained attributes are a deliberate local compatibility choice; original CU removed its drain stats. Native ability snapshots carry the policy and all nine current attributes for matching client prediction; offline legacy profiles retain their original arithmetic.

| Treatment | Action / Mind (% of base) | Recovery | Role |
| --- | --- | --- | --- |
| Held stim (native Heal Damage) | 2 / 3 | 6 s, injury group | Exact selected supply; ranged/area variants retained |
| Tend Damage | 4 / 6 | 8 s, injury group | Weaker supply-free fallback |
| Quick Heal | 10 / 15 | 30 s emergency + 6 s injury lock | Predictable emergency burst |
| Health Wound Medpack | 2 / 4 | 5 s, wound group | Exact held pack; no separate wound ability |
| Heal Mind | 6 / 10 | 15 s, resource group | Bounded Mind restoration to another patient |
| First Aid | 1 / 1 | 4 s, bleed group | Native bleeding treatment |
| Heal Enhance | 3 / 5 | 5 s, enhancement group | Bounded Doctor buffs; native wound-treatment lock also applies |
| Heal State / Cure Poison / Cure Disease / Extinguish Fire | 2 / 3 | 6 s, cure group | Native supplies and eligibility |
| Revive Player | 8 / 12 | 60 s | Native revive conditions and supplies |

Successful treatments pay once; failed checks do not pay. Costs round up and require more resources than the charge. Native supplies, range, LOS where applicable, environment restrictions, consent/PvP checks and skill requirements remain. Grey Gabaki scales recovery by 0.9. Alternating overlapping heals cannot bypass their shared recovery group. Tend and Quick Heal no longer wound the healer's Focus/Willpower.

For player and organic companion recipients, Heal Damage restores `(12% + 10% × treatment proficiency)` of effective maximum Health, multiplied by stim quality (0.75–1.25) and native battle-fatigue scaling. Proficiency is treatment skill / 100, capped at 1; quality derives from native stim power relative to 600. Tend restores 4–7% and Quick Heal 30–40%, before battle fatigue. These heals no longer replenish Action/Mind. Wound Medpack output is `(3% + 5% × proficiency) × quality` of base Health, with quality clamped to 0.75–1.25 and total base output capped at 10%; Doctor HAM enhancements cap at 15% and do not refill the patient. Explicit spice healing multipliers apply after treatment sizing.

First Aid also accepts a **bandage-wrapping gesture** around either forearm of a nearby bleeding player, or one's opposite forearm. With free hands, trace roughly four-fifths of a circle over at least 0.6 seconds; either direction works. Static contact, jitter and lengthwise Mask Scent rubbing do not qualify. Move the hand away to rearm. The server verifies learned First Aid, tracking, recipient proximity, LOS, native eligibility, resources and recovery; the gesture does not require drawing the medical focus or selecting First Aid. The existing focus/trigger path remains available.

The medical focus exposes three supply-free abilities: Tend Damage, First Aid and Quick Heal. Stims, ranged/area stims, Health Wound Medpacks, poison/disease antidotes, fire blankets, state packs, Doctor enhancement packs and resuscitation kits are held inventory items. Touch yourself or a nearby eligible patient and trigger; ranged stims can instead be aimed at a patient. The server derives the command and attribute from the exact item and enforces medicine skill, command training, ownership (including nested/worn backpacks), LOS, native consent/location/state rules, resource costs and shared recovery. Successful use consumes exactly one charge; retry receipts prevent duplicate consumption. Dead patients are selectable only for resuscitation. Diagnose and separate Heal/Tend Wound grants remain retired. Combat Medic Heal Mind retains native command balancing; a full VR interface for it and CU Bacta ability tiers is not added here.

### Health-only wound cleanup and dependency audit (2026-10-08)

SOE's [preserved CU overview](https://forums.mmorpg.com/discussion/184762/astromechs-friday-features-other-stuff-2003-2005/p5) explicitly specifies Health-only player wounds. Resource DoTs are distinct from persistent wounds. Our disease drain is local tuning, not a recovered SOE formula. Modern [Restoration Combat Medic](https://swgr.org/wiki/combat_medic/) documents Action-draining disease, but its rules do not prove original CU timings.

Patch `0082-cu-health-wounds-cleanup.patch` enforces the player wound invariant in the shared setters and additive path, covering combat, disease, cloning, radiation, Force of Will and scripted wounds. On restoration/session entry, old non-Health wounds are cleared before the existing baseline-migration early return; Health wounds and current Action/Mind are preserved. Dead/incapacitated or spice-pinned characters defer normalization. The subsequent companion pass extends this invariant to pets and droids (see below).

| Dependency | Disposition |
| --- | --- |
| Diagnose; separate Heal/Tend Wound grants | Removed; native player commands reject them. Internal Heal Wound requires an explicit pack ID. |
| Non-Health Wound Medpacks and recipes | Retired across all tiers. Health variants remain. |
| Action/Mind poison and non-Action disease packs | Retired as redundant under the new player DoT pool policy; Health poison and Action disease, including area/tier variants, remain. |
| Existing obsolete supplies/crates/blueprints | Removed from owned inventory, bank and datapad on normalization. Templates stay registered for safe database loading. Existing deployed factory jobs are stopped before producing obsolete supplies. |
| Schematics and supply production | Filtered before grant/delta serialization and tool selection; new obsolete supply creation and explicit use are rejected. |
| Heal Mind | Retained as 12–22% effective Mind restoration, proficiency-scaled, with 6% Action/10% Mind costs and 15-second base recovery. No self-wound or battle-fatigue price; still cannot target oneself. |
| Boost Morale | Redistributes Health wounds only. No longer divides wounds over nine attributes and silently loses eight shares. Health SAC becomes Action. |
| Entertainer wound healing | Treats Health wounds, capped at 1% base Health per performance tick before Neutron Pixie's 2× bonus. Battle-fatigue healing and inspiration remain. This preserves the explicit requested spice effect. |
| Resuscitation kits | Retained: revival and resource restoration still have a purpose. Removed Action/Mind wound fields from item display/crafting output; Health wound repair is capped at 10% base. |
| Meditation; Force wound healing | Retained for Health wounds and relevant cures. Shared invariant prevents obsolete wounds from returning. |
| Force of Will; cloning; radiation | Only their Health wound penalties survive; obsolete attribute wound writes have no effect or wound feedback. |
| Cure poison/disease/fire; resistance packs | Retained because their corresponding harmful states remain. |
| Stim/ranged/area stim, enhancements, chemical components | Retained: Health treatment, bounded buffs, and medicine crafting still use them. |
| Pet food, pet tricks, droid reconstruction | Retained and converted to bounded Health treatment / resource restoration by patch 0084 below. |
| Secondary-stat food, spices, enhancements and Image Designer migration | Still interact with retained local compatibility attributes. Their bounded SAC/regeneration effects remain; they are not claimed to reproduce original CU's removal of drain stats. |

Profession skill boxes, prerequisites, XP and certifications remain intact; retirement concerns obsolete actions/supplies, not a forced character respec. The remaining native Doctor/Combat Medic abilities still need their VR activation design. This audit does not claim all profession abilities now match shipped CU.

Validation for the cleanup: final native linked build and receipt verified; 416 Python suite tests plus 10 focused profession checks; 263 standalone C++ policy checks; 178 headless client checks; 99 native checks across wound migration/item treatment, crafting recipe filtering, resource/healing regression, Crash/Grey and Neutron entertainer behaviour. Native tests use disposable local characters and real original hospital/cantina environments. Final wound checks run against the final linked binary. Factory job rejection and resuscitation changes are build-validated, not end-to-end workflow validated. Evidence: `runtime/evidence/cu-cleanup-validation.json`, `cu-wounds-native.json`, `cu-recipes-native.json`, and `cu-cleanup-spice-*-native.json`. No VPS deployment, GPU validation or live headset launch was performed.

### Last Ditch and spices

The user authorized adjusting these for the new balance. Last Ditch remains a prepared ranged attack that drains Action/Mind to 1 and needs more than 1 available in both pools. It now uses `2 + 2 × missing Health fraction + 0.5 × missing Action fraction + 0.5 × missing Mind fraction`, based on effective maxima after wounds. Its range remains 2–5×; empty resources alone no longer make it as strong as low Health. At 30% Health, 10% Action and 3% Mind it deals 4.335× base damage. The multiplier is captured before the drain.

New spice consumptions convert each legacy HAM modifier to `base attribute × clamp(legacy modifier / 4000, -0.25, 0.25)`, rounded to an integer. This retains each spice's signs and relative strengths while limiting each modifier to 25% of base. Downers reverse positive bonuses, also capped at 25%; existing active buffs finish on their original timer rather than being restarted. Crash and Burn now multiplies healing by **1.5**, with withdrawal converting treatment into **Health** damage for player patients, including wound/resource treatment. Its deceptive owner-local feedback remains. All other requested active effects, withdrawal durations, crafting effects and local visuals remain, including the explicit Sweetblossom and Sedative incapacitation rules. Scramjet multiplies natural Health regeneration, which is zero in combat.

Patch `0080-cu-medical-resources.patch` and the installed medical/resource policy headers implement this pass. Validation on 2026-10-08 passed: a full linked native build and build receipt, 398 Python tests, 193 standalone medical/spice arithmetic checks, Smuggler formula/bounds checks, 157 headless client checks, 27 native medical integration checks on dedicated local characters, and a native Sweetblossom damage-versus-cost regression. Native checks cover migration at gameplay start, resource exhaustion without incapacitation, Health-only healing, exact Action/Mind charges, shared recovery, real stim consumption, bandaging, scaled spice HAM, and Crash and Burn healing/withdrawal. Evidence: `runtime/evidence/medical-resources-native.json` and `medical-*.log`. Doctor enhancement/cure/revive paths compile and use tested policy arithmetic; their full live workflows have not been exercised in this pass. Numerical values remain tunable and require encounter/headset playtesting; no VPS deployment or live VR validation is claimed.

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

Periodic secondary wounds are capped to the smaller of 10% of the budgeted tick and 1% of the relevant base pool. Disease wound ticks additionally respect remaining wound capacity and the 1% attribute cap. For player victims, disease is now a temporary Action drain, capped at 5% of base Action per tick and stopping at 1; it never creates wounds or incapacitates. Poison, bleeding, fire and Force Choke target Health even when a saved legacy effect specified another pool. NPC/pet disease retains its native wound behaviour. Independent scripted DoT producers outside command/weapon combat retain their own strength rules but pass through common resistance handling.

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

Historical blocker from 2026-10-07 (the linked build was completed locally on 2026-10-08 above): Podman could not start in that session: `Failed to obtain podman configuration: set sticky bit on: chmod /run/user/1000/libpod: read-only file system`. Syntax and arithmetic checks do not establish runtime encounter balance or successful linking. VR testing was skipped as requested. No updated server deployment is claimed.

## Crafted medical supplies and food pass (2026-10-08)

Patch `0083-cu-medical-items-food.patch` connects the existing medical supply families above to VR item use. Working Health wound, enhancement, antidote, state, stim, resuscitation, and ingredient recipes remain. In addition to obsolete wound/DoT variants, 13 empty legacy medical schematic definitions are filtered from grants and crafting lists: the four State Stim B placeholders, three `*_sm_s1` placeholders, `medic_damage`, the two medikit placeholders, `medpack_damage`, `medpack_wound`, and the untiered `medpack_wound_health`. These definitions have no target template; working tiered Health wound recipes and actual Health packs are retained. Pet vitality/stims and droid repair/reconstruction remain useful supplies; patch 0084 aligns their effects with the shared resource model. Existing retired-item/factory guards continue to apply.

Resuscitation packs no longer assign crafted Health restoration to obsolete wound portions. Each resource restoration is bounded to 10–25% of that patient's effective maximum, preserving pack power where present; original recipes without a power experimentation field receive a defined baseline. Health wound repair remains capped at 10% of base Health. Native consent, death-time window, training and 60-second base recovery still apply.

Food/drink tuning is local CU-inspired balance, not a recovered shipped SOE formula:

| Effect | New treatment |
| --- | --- |
| Attribute capacity / retained secondary stats | Legacy nutrition / 10,000 × base attribute, capped at 10% per serving; combined active food/drink bonuses cannot exceed 20% per attribute. Repeated servings count toward the same budget. Capacity changes do not heal. |
| Skill and delayed/duration modifiers | Existing units, capped at +20 per item and +20 combined for the same modifier. Crafting, performance and resistance effects retain their original role. |
| Instant percentage effects | 0–20%, retaining species and native action restrictions. |
| Restorative food/drink | Legacy nutrition / 4,000 × effective maximum, capped at 15%, with a shared 30-second recovery. Mind drinks restore a resource rather than a survival pool. |
| Healing-recovery food | Up to 20% shorter native medical recovery, including the new shared timers. |

Native recipe quality, quantity, duration, fullness, species restrictions and event consumption remain. Over-budget consumption is rejected before charge/fullness changes. Inspection shows bounded values. Native state treatment also clears script-applied states without requiring a timed state-buff object. On first entry after this balance revision, old active food buffs are removed once (with a message); inventory food remains usable. Spices retain their separate policy. Secondary-stat foods and Doctor buffs remain useful through this prototype's explicitly retained SAC/regeneration compatibility stats.

Local validation: linked native build, 418 Python tests, 313 C++ policy checks, 186 headless checks and 103 real native checks passed. The 42 medical-item/food checks were repeated on the final binary after the extra prototype-ownership guard. Evidence is recorded in `runtime/evidence/cu-items-validation.json`. Headless checks use the dummy renderer; they do not validate a headset. No live VPS update or VR launch is part of this pass.

### Companion Health/resource alignment (2026-10-08)

Patch `0084-cu-companions.patch` extends the current local CU-inspired balance to owned creatures, faction pets and companion droids. Existing species stats, growth, bioengineered traits, crafted droid quality, batteries, vitality and control-level restrictions remain authoritative; companions are not assigned the player's fixed 3000/1000/1000 baseline. Wild encounters retain their separately tuned NPC policy.

- Health is the only damage/incapacitation pool. Ordinary combat involving companions targets Health; Action/Mind depletion cannot incapacitate, and restoring a resource cannot revive one. Health SAC is paid as Action, Mind SAC is halved, and secondary-stat discounts cannot exceed 25%.
- Only Health wounds persist. Calling a saved companion or completing taming clears obsolete wounds without refilling its primary resources. Old food/medical attribute buffs are capped without extending expiry. Poison, bleed and fire affect Health; disease applies the same bounded Action drain, never permanent resource wounds. Native droid immunities remain.
- Regeneration uses the player's percentage rules against the companion's own base stats: Health 2% outside combat, none in combat; Action/Mind 4% outside combat and 1%/0.8% in combat. Secondary modifiers remain bounded to ±25%.
- Creature stims and droid damage kits heal only Health, scaled to effective maximum Health with the current 12–22% proficiency band and 0.75–1.25 quality range. Treatment consumes 2% Action/3% Mind from the operator and shares the six-second injury recovery with ordinary stims. Nested/worn backpack ownership, exact supply type, charges, range, faction eligibility and LOS are checked natively.
- Droid reconstruction kits retain Droid Engineer training and native hospital/camp restrictions. They treat only Health wounds, with the same 3–8% proficiency/quality formula (10% ceiling), 2% Action/4% Mind cost and five-second recovery. Ordinary organic wound packs and Doctor enhancements use the existing bounded values on creature pets. Food and medical attribute increases do not incidentally heal either players or companions.
- Droid stim modules apply bounded Health-only healing and retain their battery/charge use, with at least six seconds between uses. Auto-repair treats Health damage only, capped at 10% per native ten-second tick. The repair command treats at most 10% base Health wounds per five seconds, retains battery use and requires eligible recipients outside combat. Dead droids cannot be revived by these modules.
- Pet food keeps its native duration, feeding restrictions and single-food-buff rule. HAM bonuses use the shared food conversion, capped at 10%; feeding repairs only Health wounds, capped at 10%. Tricks retain morale recovery and restore 7.5%/15% Mind with a shared 30-second recovery, replacing obsolete Mind/Focus/Willpower wound treatment.

Held pet stims, droid damage kits and reconstruction kits reuse the medical-item trigger interaction. Companion targets use the existing world models, not duplicate player avatars. Organic supplies reject droids; companion-specific supplies reject players. Resuscitation packs remain player-only, while native pet recovery/vitality systems remain available. Working pet stim/vitality and droid damage/wound repair recipes remain. Seven empty legacy `droid_stimpack_a–d` / `droid_vitapack_a–c` schematic placeholders and their unused tangible stubs are retired through the existing grant, crafting, factory and inventory guards; these have no configured recipe output or functional medicine implementation.

Validation and exact native evidence are recorded in `runtime/evidence/cu-companions-native.json`, alongside the Python suite, C++ policy and headless medical client checks. Headless tests use the dummy renderer and do not validate headset interaction.

Companion validation result: final native build and full patch stack pass; 39 real Core3 companion checks, 42 player-medical regression checks, 418 Python tests, 327 C++ policy checks, and 67 headless client checks passed. Seven retired placeholders and eight preserved repair recipes were checked against the native Lua definitions. Droid module effects and paid companion attack routing are build-validated; the native harness does not fabricate a crafted module or claim an instrumented SAC attack test. Detailed scope/timing: `runtime/evidence/cu-companions-validation.json`. No VPS update or VR launch.

### Droid component retirement audit

The follow-up audit covers all 83 native recipes under `object/draft_schematic/droid/component`. No additional component is identified for retirement solely because of the adopted Health/resource split, Health-only wounds, bounded treatment or removal of Diagnose. All 83 have configured output templates. The seven empty droid medicine recipes listed above remain retired by the existing grant, crafting, factory and inventory procedure; they are distinct from installed medical/repair modules.

| Components | Decision and reason |
| --- | --- |
| Medical modules I–VI | Keep. `DroidMedicalModuleDataComponent` supplies `private_medical_rating`, still used for field Health wound treatment and Doctor enhancements. Removing Diagnose does not remove this environment requirement. |
| Stim dispenser, repair and auto-repair modules | Keep. Patch 0084 converts treatment to bounded Health healing/repair, retaining battery and charge costs. |
| Armor, combat, detonation and trap modules | Keep. Damage, resistance and control effects have compatible roles; native combat resolves damage through the shared combat rules. Source armor labels do not justify removing a component. |
| Diagnostic circuits, capacitors, casings, cartridges and redundant power supplies | Keep. These are crafting ingredients for retained damage/reconstruction kits, including advanced variants; diagnostic circuits do not invoke the removed Diagnose ability. |
| Chassis, brains, frames, motive systems, manipulators, sensors, compartments and socket banks | Keep. These construct droids and hold modules; none relies on resource wounds or three-pool incapacitation. |
| Item/data storage, crafting, maintenance, harvesting, playback, performer effects, personalities and merchant modules | Keep. Their storage, station, utility and performance roles remain compatible. Playback's Action expenditure remains a resource cost. |
| Space crafting and space memory | Preserve as deferred space content. Lack of ground-client space support is separate from CU balance incompatibility; this audit neither enables space nor validates these features in VR. |

Reproduce the catalog and retirement-policy check with `python3 tools/server/audit_droid_components.py`. It verifies output definitions, directly declared module implementation files and 360 compiled policy decisions (normal/shared recipe and item names), preserving all 83 component recipes and rejecting the seven legacy medicine placeholders. The report includes source hashes at `runtime/evidence/cu-droid-components-audit.json`. This is a source/policy audit, not an end-to-end crafting test of every component. No additional templates, installed modules or stored contents are deleted, and no native rebuild or deployment is needed for this audit.

### Combat loadouts (2026-10-08)

A character equips at most four combat abilities plus one ultimate for each
weapon family. Core3 persists the selection and validates the actual equipped
item, current family, learned grants and revision on every edit. Ranged launch
rejects unequipped specials before SAC is spent; cooldowns continue through
unequipping and re-equipping. The equipment hologram's right-stick editor provides
the four slots, drag/drop inventory, body connectors and separate click-selected
ultimate row. Initially empty loadouts require the player to equip abilities.
The existing anatomical-target and two-hand ultimate gestures consume this
selection. Melee-family slots are represented, but no new melee abilities are
introduced by the loadout implementation.
