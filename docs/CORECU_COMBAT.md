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
| Held stim (native Heal Damage) | 6 / 8 | 6 s, injury group | Exact selected supply; ranged/area variants share these costs |
| Tend Damage | 4 / 6 | 8 s, injury group | Weaker supply-free fallback |
| Quick Heal | 10 / 15 | 30 s emergency + 6 s injury lock | Predictable emergency burst |
| Health Wound Medpack | 2 / 4 | 5 s, wound group | Exact held pack; no separate wound ability |
| Heal Mind | 6 / actual Mind restored | 15 s, resource group | Bounded Mind transfer to another patient; Mind payment is an amount, not a percentage |
| First Aid | 1 / 1 | 4 s, bleed group | Native bleeding treatment |
| Heal Enhance | 3 / 5 | 5 s, enhancement group | Bounded Doctor buffs; native wound-treatment lock also applies |
| Heal State / Cure Poison / Cure Disease / Extinguish Fire | 2 / 3 | 6 s, cure group | Native supplies and eligibility |
| Revive Player | 8 / 12 | 60 s | Native revive conditions and supplies |

Successful treatments pay once; failed checks do not pay. Costs round up and require more resources than the charge. Native supplies, range, LOS where applicable, environment restrictions, consent/PvP checks and skill requirements remain. Grey Gabaki scales recovery by 0.9. Alternating overlapping heals cannot bypass their shared recovery group. Tend and Quick Heal no longer wound the healer's Focus/Willpower.

Ordinary crafted stims now normalize quality within each tier's original power range. At full treatment proficiency, A–E restore 10–14%, 13–17%, 16–20%, 19–23% and 22–26% of effective maximum Health before Doctor, fatigue and spice modifiers. Their proficiency multiplier is `0.75 + 0.25 × clamp(skill / 100, 0, 1)`. Unclassified legacy supplies retain the earlier `(12% + 10% × proficiency) × quality` normalization. Recognized Combat Medic ranged/area tiers use the separate bands documented below. Tend restores 4–7% and Quick Heal 30–40%, before Doctor bonuses and battle fatigue. These heals do not replenish Action/Mind. Wound Medpack output is `(3% + 5% × proficiency) × quality` of base Health, with quality clamped to 0.75–1.25 and base output capped at 10%, rising to 15% through Doctor training. Explicit spice healing multipliers apply after treatment sizing.

First Aid also accepts a **bandage-wrapping gesture** around either forearm of a nearby bleeding player, or one's opposite forearm. With free hands, trace roughly four-fifths of a circle over at least 0.6 seconds; either direction works. Static contact, jitter and lengthwise Mask Scent rubbing do not qualify. Move the hand away to rearm. The server verifies learned First Aid, tracking, recipient proximity, LOS, native eligibility, resources and recovery; the gesture does not require drawing the medical focus or selecting First Aid. The existing focus/trigger path remains available.

The medical focus exposes Tend Damage, First Aid, Quick Heal and learned Combat Medic Heal Mind without consuming supplies. Stims, ranged/area stims, Health Wound Medpacks, poison/disease antidotes, fire blankets, state packs, Doctor enhancement packs and resuscitation kits are held inventory items. Touch yourself or a nearby eligible patient and trigger; ranged stims can instead be aimed at a patient. The server derives the command and attribute from the exact item and enforces medicine skill, command training, ownership (including nested/worn backpacks), LOS, native consent/location/state rules, resource costs and shared recovery. Successful use consumes exactly one charge; retry receipts prevent duplicate consumption. Dead patients are selectable only for resuscitation. Diagnose and separate Heal/Tend Wound grants remain retired. Combat Medic Heal Mind uses direct friendly targeting; hostile poison/disease delivery uses the held focus and an exact compatible pack. The Combat Medic section below describes the implemented balance and controls.

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
| Heal Mind | Retained, then rebalanced to conserved Mind transfer: 12–22% effective Mind capacity, 6% Action and payment of actual Mind restored, with 15-second base recovery. No self wounds; cannot target oneself. |
| Boost Morale | Reworked as +50% existing Action/Mind regeneration for nearby party members; wound redistribution is retired. See the Squad Leader policy below. |
| Entertainer wound healing | Treats Health wounds, capped at 1% base Health per performance tick before Neutron Pixie's 2× bonus. Battle-fatigue healing and inspiration remain. This preserves the explicit requested spice effect. |
| Resuscitation kits | Retained: revival and resource restoration still have a purpose. Removed Action/Mind wound fields from item display/crafting output; Health wound repair is capped at 10% base. |
| Meditation; Force wound healing | Retained for Health wounds and relevant cures. Shared invariant prevents obsolete wounds from returning. |
| Force of Will; cloning; radiation | Only their Health wound penalties survive; obsolete attribute wound writes have no effect or wound feedback. |
| Cure poison/disease/fire; resistance packs | Retained because their corresponding harmful states remain. |
| Stim/ranged/area stim, enhancements, chemical components | Retained: Health treatment, bounded buffs, and medicine crafting still use them. |
| Pet food, pet tricks, droid reconstruction | Retained and converted to bounded Health treatment / resource restoration by patch 0084 below. |
| Secondary-stat food, spices, enhancements and Image Designer migration | Still interact with retained local compatibility attributes. Their bounded SAC/regeneration effects remain; they are not claimed to reproduce original CU's removal of drain stats. |

Profession skill boxes, prerequisites, XP and certifications remain intact; retirement concerns obsolete actions/supplies, not a forced character respec. Doctor and Combat Medic's implemented controls and balance are documented below. This audit does not claim all profession abilities now match shipped CU.

Validation for the cleanup: final native linked build and receipt verified; 416 Python suite tests plus 10 focused profession checks; 263 standalone C++ policy checks; 178 headless client checks; 99 native checks across wound migration/item treatment, crafting recipe filtering, resource/healing regression, Crash/Grey and Neutron entertainer behaviour. Native tests use disposable local characters and real original hospital/cantina environments. Final wound checks run against the final linked binary. Factory job rejection and resuscitation changes are build-validated, not end-to-end workflow validated. Evidence: `runtime/evidence/cu-cleanup-validation.json`, `cu-wounds-native.json`, `cu-recipes-native.json`, and `cu-cleanup-spice-*-native.json`. No VPS deployment, GPU validation or live headset launch was performed.

### Automatic entertainer benefits (2026-10-09)

Patch `0113-entertainer-audience.patch` applies native performance benefits to
all eligible players within each entertainer's eight-metre radius. The existing
ten-second performance tick checks native cell, line of sight, venue, online,
living, noncombat, friendly-healing and deny-service eligibility. Manual
Watch/Listen and a selected buff recipient are not required. Each patient keeps
one source per dance/music kind; source cleanup and joining a replacement occur
on native ticks, so a handoff can take up to two ticks.

Health-wound and battle-fatigue treatment retain their existing native rules.
Inspiration retains its native strength, accrual and one-minute minimum, then
applies automatically on a performance tick. Flourishes improve accrual without
granting an extra application. Equal-strength buffs renew in place; replacement
preserves current HAM against the final effective maxima, including the
temporary lower maximum while removing an old buff. Initial application and
refresh do not refill resources. Leaving the radius stops accrual; already
earned buffs keep their remaining duration. Native audience observations are
separate from the presentation circle; see [audience protocol](../server/README.md#automatic-entertainer-audience).

### Doctor preparations and care (2026-10-09)

Doctor has no ultimate. Patches `0104-doctor-preparations.patch` and
`0105-doctor-care.patch` specialize the original profession in preparation,
stronger basic care, wound treatment and rescue. Training prerequisites, XP,
certifications and skill-point costs remain the original graph.

The enhancement recipe list now contains 18 useful recipes, down from 30:

| Preparation | Effect | Tiers |
| --- | --- | --- |
| Vitality | Increased maximum Health | A: 5–8%; B: 7–10%; C: 9–12%; D: 11–15% |
| Endurance | Increased maximum Action | Same A–D bands |
| Metabolic | Increased existing natural Health/Action/Mind regeneration | Same A–D bands; combat Health regeneration remains zero |
| Poison or disease prophylaxis | Resistance to the corresponding effect | A: 10–15; B: 15–20; C: 20–25 resistance points; C absorption at most 10% |

Each patient may have **one general preparation plus one prophylaxis**. A new
family replaces the previous member of that group. Application and legacy buff
normalization preserve current resources, bounded by the resulting maximum;
normalization also preserves remaining duration. Preparations do not heal or
refill pools. Clinical location, out-of-combat, supply and recovery rules remain.
Original charges, duration, ingredients and experimentation remain meaningful.
Raw pack power is normalized within its original tier range rather than clipped
directly to a small HAM cap. General potency uses 70% item quality, 20% treatment
skill and 10% clinical rating within the listed band; battle fatigue can reduce
the result. Prophylaxis uses item quality and battle fatigue.

Natural regeneration now carries fractional points between eligible recovery
ticks. At the neutral standing combat baseline, 15% Metabolic produces exactly
115 Action and 92 Mind over ten seconds, versus 100 and 80 without it. Rounding
each tick upward would exaggerate that benefit to 120/100. Regeneration reads
the active preparation's normalized strength directly, avoiding Core3's 125-point
aggregated buff-modifier cap on the stored 500–1500 basis points. Carry is transient, below one
point per pool, and cleared at full pools, incapacitation/death and relevant
combat Health transitions. Inactive time does not accrue a recovery reserve.

Health, Action and Constitution templates become Vitality, Endurance and
Metabolic. Existing Strength, Quickness and Stamina packs remain usable Metabolic
aliases; only their redundant recipes are retired. Source media is untouched.
Support I grants Vitality/Endurance A; Support II adds their B tiers and Metabolic
A; Support III grants their C tiers, Metabolic B and prophylaxis A; Support IV
grants their D tiers, Metabolic C and prophylaxis B; Master grants Metabolic D
and prophylaxis C. Recipes fill the original rewarded schematic groups without
changing the training graph or duplicating grants. Inventory/crafting displays
show the preparation's actual role and normalized potency.

After the balance review, Novice Doctor and each Wound Treatment box give
**+5% ordinary stim and Tend Damage potency**; Master Doctor adds a final 5%,
to **+30%**. Quick Heal receives half that bonus, up to **+15%**. Wound Medpacks
retain +10% at Novice and each Wound box, up to +50%; the wound cap scales from
10% to 15% of base Health. Ranged/area stims use Combat Medic proficiency and their separate tier bands.
They receive no Doctor direct-heal multiplier. Heal Damage costs **6% base Action / 8% base Mind**; pet/droid repair
commands retain their separate costs. Shared recovery, battle fatigue and spice
effects remain. Revival keeps native eligibility, restoration,
consent and supply rules; its 60-second grogginess penalty is now 5% of each base
attribute instead of a flat 100.

This retains Doctor's close-range care and wound-treatment advantage while
reducing the former +50% direct/emergency healing bonus. At 3,000 Health and
Master Medic's prerequisite proficiency, Master Doctor's best E stim restores
1,014 Health and Quick Heal restores 1,380 before fatigue, spices and overheal.
At 1,000 Action/Mind, stims now cost 60/80 instead of 20/30. A standing-combat
arithmetic model using ordinary recovery, no other actions and unlimited supplies
first delays continuous stim use for resources at about 112 seconds; maximum
Metabolic extends this to about 127 seconds. The old costs never exhaust resources
in that model. These are policy comparisons, not measured encounter endurance;
other actions, posture, consumables and damage pressure change the result.

Revival accepts a held resuscitation kit and a two-hand pad press/release; fire
treatment accepts a held fire blanket and a broad sweep, return and settled pat.
Existing held-item trigger treatment remains. Friendly VATS requires the
**Doctor tool actually held**, a learned Heal State command and a suitable state
pack in accessible inventory. A state pack alone cannot open it. Click the tool
hand's stick while aiming at an eligible friendly patient, aim the tool at a
condition marker, then squeeze and release its trigger. Stun, dizzy, blind and
intimidation use their corresponding native packs. Stowing/changing the tool or
losing valid tracking closes the markers and clears the patient. Active friendly
VATS captures combat input, preventing concurrent weapon specials or fire.

`/medic/doctor` forwards only the named supported action, exact supply, patient,
tracked pose and (for Heal State) exact focus ID. Core3 checks ownership,
training, friendly eligibility, consent, range, LOS, condition, supply, costs and
recovery. Its existing request receipts prevent duplicate consumption. Physical
holding and gesture recognition are client input; possession of a focus ID is
not server proof of the user's physical pose. No live headset or encounter
validation is implied by the automated fixtures.

Initial validation before the balance follow-up: 531 Python tests passed, including 100 production-native care checks
and 244 preparation policy/helper checks. Nine headless client suites passed
507 checks, including 49 Doctor gesture and 91 production routing checks. The
actual starport stair regression passed with tracked head pose preserved. The
full native binary linked and its build receipt verified. Headless rendering
uses the dummy renderer with mocked tracking/native transport. Evidence:
`runtime/evidence/doctor/validation.json`. No server deployment, live client
launch, GPU or headset validation was performed.

Balance follow-up (`0106`–`0108`): the 540-test Python suite passed. After the
final native buff-cap and inspection-format corrections, 20 focused tests passed,
including 741 Doctor care, preparation, resistance and regeneration checks, plus
the affected ranged-profession regressions. Nine headless client suites passed
508 checks and the actual starport stair regression preserved tracked head pose.
The final full native target linked and its source/binary receipt verified.
The arithmetic report records tier potency and resource-pressure assumptions.
Evidence: `runtime/evidence/doctor-balance/validation.json`. This pass did not
launch a live server or client, deploy, or validate GPU/headset rendering or
encounter balance.

### Combat Medic schematic and action audit (2026-10-09)

Combat Medic's intended role is ranged field healing, group triage and sustained
hostile medical effects. Doctor retains stronger close treatment, preparations,
wound care and revival. Combat Medic should not duplicate Carbineer's immediate
crowd control or Rifleman's single-target burst.

The original Combat Medic skill grants contain **86 schematics**. The existing
Health-only retirement policy already removes **60**, leaving **26 useful
schematics**; no further recipe retirement is justified by this audit. All 19
granted schematic groups retain at least one useful recipe. Missing VR controls
do not make a mechanically distinct supply obsolete.

| Family | Disposition | Recipe count |
| --- | --- | --- |
| Health poison, single and area A–C | Keep: sustained Health damage | 6 |
| Action and Mind poison, single and area A–C | Already retired: obsolete alternate damage pools | 12 |
| Action disease, single and area A–C | Keep: temporary resource pressure; action needs rebalancing | 6 |
| Health, Strength, Constitution, Quickness, Stamina, Mind, Focus and Willpower disease, single and area A–C | Already retired: redundant or obsolete wound/stat roles | 48 |
| Ranged stims A–E | Keep: remote single-patient Health healing | 5 |
| Area stims A–C | Keep: group Health healing | 3 |
| Six Combat Medic chemical components | Keep: real ingredient, quality, range, area or duration dependencies | 6 |

The six components are the basic and advanced Dispersal Mechanism, Infection
Amplifier and Resilience Compound. Original training remains intact: Novice
requires Master Medic and Marksman Support IV and grants Apply Poison; Ranged
Healing II grants Apply Disease, and Ranged Healing Speed IV grants Heal Mind.
Master's `place_hospital` is a city-hospital placement permission, not a combat
ability or an existing ultimate.

Poison/disease cures are Doctor schematic rewards, not another Combat Medic
recipe family. They remain useful through the appropriate additional training.
This audit adds no destructive inventory migration or template removal. The
earlier retirement policy still rejects obsolete production and use and cleans
up obsolete owned supplies under its existing normalization rules.

Patches `0109`–`0112` implement the offensive effects, specialist application
balance, ranged healing and shared medical-tool controls. The original skill
graph, XP, prerequisites and schematic grants remain intact.

| Action | Implemented interaction |
| --- | --- |
| Ranged stim | Hold the actual pack, aim at an injured friendly patient and trigger. |
| Area stim | Same held-pack action with patient-centered radius preview; at most five eligible injured patients including the primary patient. No ground targeting. |
| Poison / disease | Hold the Doctor tool and click its stick while aiming at a hostile target. Choose the single-target or area Poison/Disease marker and squeeze/release. The marker identifies the exact compatible pack, charges and area radius. |
| Heal Mind | Aim the held Doctor tool at another friendly player or organic pet and double-tap its trigger within 0.30 seconds. Single tap waits for that window before Tend Damage; a 0.65-second hold casts only Quick Heal. No action selection or anatomical VATS step. |
| Doctor Heal State | The same held tool acquires friendly condition markers with the appropriate learned Doctor command and state supply. |

Both friendly and hostile medical targeting require the held Doctor tool.
Changing target relation, tool, tracking or selected supply cancels an armed
application. Only packs that can reach the recipient participate in strongest-pack
selection, independently for poison/disease and single/area variants. Targeting
captures weapon input; both triggers must be released before weapon combat
resumes. These actions use no weapon ability slot. They require their original
training even when a combined profession also uses the tool. No Combat Medic
ultimate or extra gesture is enabled in this pass; Emergency Triage remains an
optional later design.

**Application potency:** learned bonuses now apply before resistance:
`clamp((base chance + learned bonus) × (1 − resistance reduction), 0, 95)`.
Combat Medic raw potency is `95 + 20 × proficiency + 10 × application quality`,
up to 125. Proficiency is bounded Combat Medic effectiveness/100; application
quality normalizes the pack's original potency 25–150. Fencer training now adds
5–10, Precision adds 5, and Flawless Assault replaces Precision with 10, for a
maximum raw potency of 115. Pikeman, Carbineer and Ranger retain their authored
bonus amounts, now subject to resistance. Other base chances, damage and
hard-control limits remain.

| Strongest authored application | At 100 resistance | At 125 resistance |
| --- | --- | --- |
| Combat Medic, raw potency 125 | 75.0% | 68.2% |
| Master Fencer with Flawless Assault, raw 115 | 69.0% | 62.7% |

These compare the same defender rating; per-effect immunity and resistance still
apply. A 65-rating target reduces the strongest Combat Medic chance to 87.2%;
25-point Doctor prophylaxis raises the rating to 90 and reduces that chance to
78.1%. Preparation therefore remains useful. Integer native RNG discretizes
these formula thresholds. Combat Medic also has up to 30% authored duration
bonus, above Fencer's 25% soft-debuff bonus, without gaining hard crowd control.

**Hostile supplies:** poison and disease each use one shared channel per target,
across tiers, single/area variants and attackers. Reapplication preserves the
pending tick; it cannot create parallel template stacks or repeatedly buy an
immediate first pulse. Costs are 6% base Action/8% base Mind, paid once with one
charge for a valid attempt, including resistance. Poison and disease share an
8-to-6-second base recovery scaled by ranged medical speed; existing bounded
food and spice recovery adjustments apply. Area effects use at most six eligible
targets including the primary target, an eight-metre radius cap and 75% strength.

Poison has a total Health damage budget, from 8% at novice to 12% at mastery,
of `min(target effective Health, 4 × healer base Health)`. Supply power and
crafted duration quality scale this budget downward, never above that bound.
Its pulses occur every four seconds after the initial 1.5-second delay, within
an authored duration of at most 21 seconds before resistance. At baseline,
the best master single-target pack has a 360-Health budget on a 3,000-Health
patient. Tick spending, absorption and partial cures cannot restore spent budget.
Longer crafted duration also raises the bounded budget, so weaker short-duration
packs cannot concentrate the entire best budget into fewer pulses.

Combat Medic disease drains 3–5% base Action per three-second pulse, scaled by
supply power and reduced for area delivery, for at most 24 seconds before
resistance. At baseline mastery that is 50 Action per pulse, or 45 with 10%
disease absorption. Its nominal 16.7 Action/second pressure exceeds baseline
standing combat recovery of 10/second; actual finite duration and tick scheduling
still matter. Players, pets and NPCs use temporary Action drain, with no permanent
wounds or shock. Other legacy weapon/script disease sources keep their separate
behavior. Duration quality is bounded to 75–100% of the authored base (16 seconds
for poison, 18 for disease), followed by the training bonus. Original duration
values up to 1,000 seconds are quality inputs, not active effect lifetimes.

The native command now validates exact pack type, pool, medicine-use level,
charges, nested accessible ownership, target eligibility, LOS, range and
immunity. Range progression uses floating-point arithmetic. The old three-second
movement lock is removed. Item inspection and snapshots report authored effects
instead of misleading legacy potency/duration values.

**Ranged care:** at full Combat Medic effectiveness, ranged A–E stims restore
10–14%, 13–17%, 16–20%, 19–23% and 22–26% effective Health. Area A–C restore
6–8%, 8–10% and 10–12% per patient, capped at five patients. Quality uses each
original tier's effectiveness interval. The proficiency multiplier is
`0.75 + 0.25 × clamp(combat_medic_effectiveness / 100, 0, 1)`; patient battle fatigue
applies once. Doctor's direct-care multiplier does not apply. Both retain
6% Action/8% Mind cost and shared injury recovery. At baseline the strongest
master ranged E stim heals 780 Health and area C heals 360 per patient, compared
with Master Doctor's ordinary E stim at 1,014. Supplies retain distinct range,
charges and experimentation. Ranged inspection reports the actual Health effect.

**Heal Mind:** capacity remains 12–22% of the patient's effective maximum Mind,
with patient battle fatigue applied once, at five metres and a 15-second base
recovery. It costs 6% base Action plus the actual Mind restored, limited by the
patient's deficit and leaving the healer at least one Mind. Spice amplification
cannot generate net Mind: input is bounded before native healing and payment is
measured from actual recipient Mind gain. Withdrawal cannot spoof that gain.
Snapshots label this variable payment as `transferred_amount`; zero fixed Mind
cost does not mean free restoration. Reciprocal use conserves group Mind.

The initial static audit is `runtime/evidence/combat-medic/actions.json` and
records the old mechanics. Current arithmetic and validation evidence are
recorded separately under that directory. No live encounter, headset or GPU
validation is implied by policy arithmetic or mocked input tests.

Final validation: 559 Python tests passed, including 621 native Combat Medic
bridge/effect/healing checks, 3,362 cross-profession potency checks and the
schematic audit's 344 compiled-policy checks. Ten headless client suites passed
630 checks; the additional authored starport stair scenario passed ascent,
descent and tracked-head preservation. The complete native target linked and its
source/binary receipt verified. All four patches replay against the pinned
predecessors. Evidence: `runtime/evidence/combat-medic/validation.json` and
`arithmetic.json`. No live server/client launch or deployment was performed.

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

For each status, combine the strongest profession contribution with 25% of all other contributions, capped at 100 rating. Compare against native resistance, also bounded to 100, without counting Doctor prophylaxis in this baseline. The active matching Doctor preparation then adds up to 25 rating exactly once. Wild NPCs receive rating `min(level × 0.5, 100)`; the shared creature helper also supplies this baseline to AI-controlled pets. Existing TKA Focus, trap debuffs and Fencer effects retain their roles in resolution.

```text
reduction = clamp(rating / (150 + rating), 0, 0.50)
application chance = clamp(original chance, 5, 95) × (1 - reduction)
duration = ceil(original duration × (1 - reduction)), at least 1 second
```

Rating 60 now reduces application chance and duration by about 28.6%; rating 100 gives 40%. A 25-rating Doctor preparation on that maximum baseline gives 125 rating and about 45.5% reduction. Master Doctor plus Master Medic's 65 poison/disease baseline becomes 90 with the strongest prophylaxis, rather than masking the preparation. Resistance remains valuable without automatically granting immunity. Explicit existing immunity rules remain separate. Disease absorption now applies after the player's bounded Action drain, so 10% absorption reduces a capped 50-point tick to 45.

Stun, blind, dizzy, intimidate, knockdown/posture changes, attack delay, bleeding, poison, disease and fire use the relevant ratings. NPC-applied command states have an eight-second duration ceiling before resistance. Knockdown/posture effects share an eight-second recovery window. Their recovery delay also scales with resistance. Existing direct Smuggler control effects use the policy; creature-trap debuffs receive a separate resistance roll and reduced duration after the original trap hit roll. Trap direct damage retains its existing template behaviour.

Scout Novice and each Scout trapping box add one percentage point to the second trap status roll (5 total). Each Ranger trapping box and Master Ranger add another point (10 combined). This bonus is applied before resistance, with final chance capped at 95%; the original trapping hit roll and resistance-based duration remain. Hard-control traps share the control recovery timer and leave at least two seconds after their duration before another hard-control trap can land, with an eight-second minimum timer. State-defense traps lower the derived resistance floor as well as native modifiers, preserving their usefulness against CoreCU enemies. Trap eligibility remains the existing non-pet creature scope.

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


## Merged Brawler Warcry (2026-10-09)

Patch 0088 merges Warcry and Intimidate into one live XR ability named Warcry. Original skill grants remain as progression inputs; neither legacy command has a separate XR action. Novice Brawler plus both original novice grants unlock the ability. Master Brawler upgrades its durations. Patch 0089 removes gesture abilities from targeting slots: Warcry is available whenever learned and a compatible certified weapon is equipped, with no loadout selection. Unarmed is excluded because this activation requires raising a weapon.

Raise the weapon hand above the head, lower it slightly while still overhead and pump upward, with triggers released. This is independent of target-marker shooting and ultimate activation. The client suppresses competing attack/guard input while recognizing it. The server selects eligible attackable AI in a 60-degree horizontal forward cone, within 24 m and line of sight, nearest first, capped at eight. Pets, dead/incapacitated enemies and targets in shared control recovery are excluded. This does not add PvP support.

Provisional tuning: 80 Action and 40 Mind, no Health cost, a 30-second creature-owned cooldown and one second of shared attack recovery. These are fixed gesture costs, not ordinary weapon SAC multipliers. With no eligible targets it spends nothing. An accepted attempt pays once even if targets resist. Each target rolls intimidation resistance for the combined attempt; a second warcry/snare resistance roll gates its attack delay. Success applies 20% outgoing damage reduction for six seconds (eight at Master), plus a two-second attack delay (three at Master), shortened by the respective resistance. Existing intimidation damage modifiers are not stacked or overwritten. Native attack-delay recovery and eight seconds of shared control recovery prevent repeated lockdown. Hostile attempts initiate native combat even when resisted. Confirmed affected targets produce hand haptics.

Validation: 91 gesture checks, 15 production routing/request checks, 30 existing Taunt checks, 86 target-marker checks, 27 equipment-loadout checks and 58 gameplay-combat checks passed with mocked tracking/transport and the dummy renderer. Sixteen Python protocol/loadout/session tests passed. Standalone C++ checks cover cone/range/pose validity and rank durations. The actual CommandConfigManager2.cpp translation unit, including the new native integration, passes Clang 19 syntax checking with the existing build headers; the full ordered patch stack applies. Podman access is blocked by the current sandbox's read-only `/run/user/1000/libpod`, so no linked build, service restart, live encounter or headset verification is claimed. Evidence: `runtime/evidence/warcry-client.json`, `warcry-routing.json` and `warcry-native-syntax.log`.


### Gesture row correction (2026-10-09)

Gesture support abilities use their own informational row in the ability inventory. They do not consume any of the four targeting slots or require loadout selection. Weapon restrictions, learned skills, native resource checks and cooldowns remain in force. The selected ultimate remains separate. The catalog marks support gestures with `category: gesture`, a trigger description and weapon requirements. Warcry, Taunt and Feign Death are exposed only when learned; Warcry remains unavailable unarmed. This pass does not implement Center of Being or Berserk.

Native loadout validation excludes gesture IDs from both regular and ultimate selections. Snapshot projection clears old gesture assignments, including Warcry, while preserving the other saved slots and ultimate. Gesture entries remain in `ability_catalog`, but not in the equipped target/ultimate `abilities` list. Warcry no longer requires an `equipped` flag or loadout check; native held-weapon identity and eligibility checks remain. The editor has a paginated gesture row; hovering shows the trigger and weapon requirements, and grip/click cannot equip or activate it.

Validation: 35 equipment-editor checks, 14 mocked production Warcry routing checks, native syntax and full ordered patch-stack checks. No live deployment or headset validation. Full linked build remains blocked by the Podman sandbox restriction recorded above.


## Brawler targeted strikes and self buffs (patch 0090)

Native melee catalogs now expose Knockdown Strike (original Master Brawler Lunge II
for each of the four families), Stunning Attack (Unarmed II), Blinding Attack
(Unarmed III), and Polearm Stun (Polearms III). Original native command grants,
weapon certification, damage multipliers and SAC are retained under CoreCU's
Health/Action/Mind conversion, including cost modifiers. Knockdown uses native
posture/recovery rules; stun and blind durations are bounded to four seconds
before native resistance. Cooldowns are 20 seconds for Knockdown Strike and
15 seconds for the others. All four require a targeting slot. Attacks remain
single-target PvE: AI eligibility, current target identity, 2 m unarmed / up to
4 m weapon reach, LOS, a forward-facing gate and shared control recovery are
validated before spending. A paid hit establishes eight seconds of shared
control recovery, including when the target resists its effect. Invalid or
out-of-range selected targets are rejected without spending; accepted misses
retain normal native attack costs and cooldowns.

The local overlay accepts a tracked punch segment or an asset-bounds-derived
weapon-tip segment crossing the marker. A qualified forward punch can also
select a marker along its physical travel direction, within native melee range,
without requiring arm contact at the target's distance. It uses up to 140 ms of
head-relative hand translation, at least 10 cm of coherent travel, and the
existing native client swing speed/travel qualification. Direction comes from
hand motion, not controller aim. Selection tolerates small directional jitter
up to an 18 cm marker radius and checks both marker and body-anchor LOS. Walking,
stationary pointing, retraction, tracking jumps and frame gaps cannot supply a
directional punch. The weapon hand uses the held melee family; either fist works
when unarmed. A qualified swing can wait up to 0.3 seconds for selection, after which
it resolves as an ordinary swing if still permitted. Input/tracking cancellation,
weapon/target changes and overlay closure discard pending specials. Environmental
occlusion, range, SAC, native control availability and cooldowns hide ineligible
markers. Basic melee retains its existing native head-cone target selection.

CoB and Berserk are gesture support abilities, never targeting-slot choices or
ultimates. CoB invokes the original Center of Being command, using the current
weapon family's trained efficacy and duration, with a fixed 40 Action / 40 Mind
cost and 60-second cooldown. Berserk uses the original native Berserk state:
+20 melee accuracy, +75 additive melee damage, -60 melee and ranged defence;
20 seconds at Novice and 40 seconds at Master. It costs 80 Action / 40 Mind and
has a 60-second cooldown. Both share one second of attack recovery, reject active
buff refreshes, and remove their own buff when the native equipped weapon family
changes. Cooldowns survive live-session reconnection on the creature. Their
weapon compatibility is unarmed, 1H melee, 2H melee or polearm; ranged and Jedi
families are not granted these Brawler self buffs. The controller gestures and
finger approximation are documented in `ABILITY_ACTIVATION.md`.

Validation uses mocked tracking/transport and the dummy renderer, including
production swing-to-marker dispatch, unarmed markers, trigger/cooldown/SAC/LOS
filtering, gesture holds/rearming and production self-buff routing. Native syntax
checking and ordered patch-stack validation cover the new integration. Full
linked server build and actual encounter/headset tests remain unverified under
the existing Podman sandbox restriction. Evidence: `runtime/evidence/brawler-gestures.json`,
`brawler-targeting.json`, `warcry-routing.json`, and `brawler-native-syntax.log`.

## Teras Kasi tank implementation (patch 0092)

TKA uses area damage and extra AI threat, the existing trained CoB progression,
and existing profession status resistance. It gains no passive invulnerability,
forced camera movement or area hard-control loop. All three area gestures require
the unarmed family and native skill grants; none consumes a targeting slot.

| Ability | Unlock | Shape / cap | Damage per target | Action / Mind | Cooldown |
| --- | --- | --- | --- | --- | --- |
| Sweeping Punch | Novice TKA | 3 m, 120° cone, 6 targets | 0.65× | 60 / 20 | 6 s |
| Two-Handed Half-Spin | Expert Power Techniques (`unarmedSpinAttack2`) | 4 m, 180° sector, 8 targets | 0.55× | 90 / 30 | 10 s |
| Rapid Punch Volley | Advanced Power Techniques (`unarmedCombo1`) | 3 m, 60° cone, 4 targets | Three 0.4× blows | 80 / 25 | 8 s |
| Challenging Strike | Novice TKA; targeting slot | Single chest marker, normal unarmed reach | 0.75× | 40 / 20 | 15 s |
| Indomitable Focus | Master TKA; ultimate slot | Self, 12 s duration | No damage | 120 / 100 | 120 s |

Costs are fixed and paid once per accepted gesture, with shared attack recovery
of 1.25/1.75/1.5 seconds for sweep/half-spin/volley. The completed volley gesture
resolves three bounded native blows per target in one action; it does not stream
unrestricted per-punch damage. The server chooses nearest eligible non-pet AI,
checks range/cone and LOS again before each blow, and caps target count. Empty
areas reject without spending. Accepted misses retain costs and cooldowns.
Player attacks use validated physical accuracy; damage mitigation and armour apply, and damage uses Health.

Area hits add `min(5000, 40 + 2 × landed damage)` extra threat per damaged target.
Challenging Strike adds `min(5000, 200 + 4 × landed damage)` extra threat. Both use
native aggro bookkeeping, not fake damage or extra XP credit. Challenging Strike
has no control effect and remains usable during shared control recovery. Stun,
blind and Unbalancing Strike retain their existing slot and resistance/recovery
rules; TKA's stronger learned knockdown rank replaces the source of the existing
knockdown slot rather than granting a second control cooldown.

Indomitable Focus provides 1.5× the stronger of trained unarmed CoB efficacy and
currently active CoB, capped at 100 without reducing an already stronger active
value. This temporary defensive value works even if ordinary CoB is inactive;
it neither creates nor refreshes that buff. Focus adds up to 20 status resistance
rating within the shared 100-point baseline; matching Doctor prophylaxis adds
its separate bonus afterward. Focus also adds 50% of damage as extra AI threat.
It grants neither healing nor guaranteed immunity.
Weapon/skill loss disables its benefits; refresh removes the invalid buff. Its
native cooldown survives session reconnection. Ultimate selection is mandatory,
and Brawler mastery or another advanced profession cannot unlock it.

Validation: mocked gesture and production-routing tests, targeting/loadout and
normal melee regressions, Python protocol validation, standalone C++ policy
checks, native translation-unit syntax checks, and ordered patch-stack replay.
Evidence is under `runtime/evidence/tka-*`. Dummy-renderer tests do not validate
GPU or headset rendering. The full linked server build and actual native encounter
remain unverified because the existing Podman sandbox cannot write its runtime
lock directory. No live server deployment or VR launch was performed.

## Swordsman heavy single-target damage (patch 0093)

The implemented role is heavy single-target damage with a shared armour opening.
TKA keeps sustained area threat and defensive focus. Swordsman uses original
profession boxes, certifications and two-handed melee weapons; no Jedi or other
weapon family qualifies. Native training retains its translated physical-accuracy modifiers and attack
speed. Abilities have single stable IDs rather than duplicate rank cooldowns.

| Ability | Unlock | Damage multiplier | Action / Mind | Cooldown |
| --- | --- | --- | --- | --- |
| Rending Cut | Novice Swordsman | 1.15× plus bounded bleed | 70 / 25 | 12 s |
| Disrupting Blow | Advanced Sword Defense | 0.9× | 65 / 30 | 18 s |
| Hamstring | Advanced Sword Techniques | 0.9× | 60 / 25 | 16 s |
| Decisive Strike | Master Sword Offense | 3× to 1.25× by target level | 100 / 40 | 20 s |
| Overhead Cleave | Novice Swordsman | 2× | 100 / 35 | 10 s |
| Ground Slam | Expert Sword Finesse | 1.25× primary; 0.35× collateral | 100 / 40 | 18 s |
| Armour Break | Master Swordsman | 1.75× plus armour opening | 140 / 80 | 120 s |

Fixed SAC is paid once per accepted action. Recovery is the slower of native
weapon attack speed and a per-ability floor: 1.5 s for Rending/Disrupting/Hamstring,
2 s for Decisive/Cleave/Armour Break, and 2.25 s for Slam. Invalid target, boss,
Health threshold, duplicate fracture and empty-cone rejections spend nothing;
accepted misses retain costs and cooldowns. Native hit, armour, weapon DoT,
condition, death and XP paths remain authoritative. Swordsman adds no bonus aggro.

Rending Cut seeds a Health bleed at up to 40% of the landed hit, under the shared
50% command-DoT budget and native bleed resistance. Its duration is at most 20 s.
A fixed effect key prevents stacking between Swordsmen; reapplication replaces
strength from the new hit and refreshes duration while retaining the pending tick.
Disrupting Blow applies up to 3 s of attack delay; Hamstring applies a 30% slow
for up to 5 s. Both use status resistance and eight-second shared control recovery.
The native attack-delay recovery still applies. Hamstring and Restraining Shot
use the stronger slow, not additive slows. Neither ability adds a knockdown.

Decisive Strike requires current Health strictly below 30% of maximum Health
minus wounds. It uses `3 - 1.75 * clamp((target_level - 30) / 120, 0, 1)` damage:
3× at level 30 and below, 2.125× at 90, and 1.25× at 150. Bosses are rejected,
not merely assigned ordinary damage. Boss classification includes the existing
level-above-150 encounter band, explicit native `swgxr_boss` role modifiers,
boss mobiles spawned by lairs, and the explicit named-encounter registry in
`SwordsmanPolicy.h` (including Tusken King, Lord Nyax and the Warren droid boss).
The registry uses exact source template IDs, not localized display-name matching.
New encounter bosses must supply the role modifier or extend the registry.

Cleave chooses one nearest eligible AI in a 60-degree forward cone. Slam chooses
one primary and at most two collateral targets in that cone, within 2.5 m.
Both remain bounded by native weapon reach (at most 4 m), with range and LOS
rechecked before damage. No pets, players or lairs are special-attack recipients.
Targeted abilities retain their bound entity and cannot transfer to another actor.

Armour Break applies Fractured Armour only after damage lands, for eight seconds.
It halves effective Kinetic/Energy body armour scores for all attackers. The
inverse score curve is used for resistance inputs: `r' = r / (2 - r)`, equivalent
to halving score before recalculating `score / (8000 + score)`. At score 8000,
mitigation becomes 33.3% instead of 50%, before integer rounding, AP and other
modifiers. Elemental resistance, PSG protection, AP budgets, raw item statistics,
condition, crafting and normal armour wear rules are unchanged. The triggering
hit uses original armour; subsequent hits exploit the opening. Multiple casts
cannot stack or refresh the active buff. Master Swordsman and ultimate equipment
are required; an unrelated advanced profession does not qualify.

Evidence: `runtime/evidence/swordsman-*`. Validation covers gesture recognition,
production input/transport routing, anatomical markers and boss/Health filtering,
loadout UI, armour/AP arithmetic, protocol authority and native syntax. Headless
runs use `--xr-mode off` and the dummy renderer. Full linked server build, actual
native encounters and live headset use remain unverified under the existing
Podman sandbox restriction. No deployment or live client launch was performed.

## Fencer bleed and debuff support (patch 0094)

Fencer's implemented identity is sustained single-target bleed pressure and
status support. It uses the original one-handed sword profession tree, intact
certified one-handed melee equipment, and native hit/armour/weapon-condition
resolution. Jedi weapons and other melee families do not qualify. TKA retains
area threat and defensive focus; Swordsman retains heavy hits and armour break.

| Ability | Original skill box | Hit multiplier | Action / Mind | Cooldown |
| --- | --- | --- | --- | --- |
| Arterial Cut | combat_1hsword_novice | 1.0× | 65 / 25 | 12 s |
| Nerve Strike | combat_1hsword_ability_02 | 0.65× | 55 / 25 | 15 s |
| Disorienting Thrust | combat_1hsword_ability_03 | 0.6× | 60 / 30 | 18 s |
| Exposing Thrust | combat_1hsword_support_04 | 0.6× | 65 / 35 | 16 s |
| Probing Jabs | combat_1hsword_novice | 2 × 0.35× | 45 / 15 | 8 s |
| Raking Slash | combat_1hsword_support_02 | 0.7× | 55 / 20 | 10 s |
| Guard Bash | combat_1hsword_speed_02 | 0.4× | 50 / 25 | 14 s |
| Flawless Assault | combat_1hsword_master | Self buff | 120 / 80 | 120 s |

All attacks pay fixed SAC once and share native weapon cadence with a 1.2-second
minimum (1 second for Flawless Assault). Gesture attacks choose the nearest
eligible non-pet AI within a 60-degree forward cone and native reach, capped at
4 m. Probing Jabs keeps both hits on that actor; it does not retarget a kill.
VATS retains the bound actor. Native LOS, range, ownership, training, state,
cooldown, resources and loadout checks remain authoritative. Invalid targeting
spends nothing; an accepted miss consumes its action's costs and cooldown.

Training normalizes the original novice-to-master progression to 0–1.
Arterial Cut and Raking Slash budget bleed at 50% of landed damage at novice,
rising to 80% at master. This is an explicit exception to the ordinary 50%
command-DoT cap. A shared native effect key gives all Fencers one bleed channel
per target. Ticks are three seconds apart, with the first due after 1.5 seconds
(or sooner for a very short resisted duration), over at most 12 seconds before
resistance and dissipation. The nominal per-tick strength is a quarter of the
budget, rounded upward; the final tick is bounded by remaining budget.

Reapplication refreshes duration, preserves the pending tick, and keeps
max(old remaining budget, new landed-hit budget). It never restores the old
original budget or adds parallel stacks. A retained larger budget retains its
attacker attribution. Ticks deduct their allocated amount before absorption;
blocked/absorbed damage cannot replenish the budget. Partial cures reduce both
tick strength and remaining budget proportionally. Serialized remaining budget
and interval survive object persistence; absent fields retain legacy behavior.
Ordinary bleed channels keep their previous interval and rules.

Fencer effect chance uses base 95 potency plus a training bonus of +5 to +10
before resistance, with final chance capped at 95%. Nerve Strike and Exposing
Thrust gain up to 25% duration before resistance (native whole-second rounding).
Nerve Strike suppresses outgoing damage by 15%, filling only the gap beneath
stronger existing Intimidate/Stun suppression. Its base duration is 6 seconds.
Exposing Thrust reduces only bleed, blind, intimidate and snare resistance by
20 rating, floored at zero, for all attackers. Its base duration is 8 seconds.
It applies after existing resistance/debuff aggregation and leaves other
resistance channels and explicit immunities intact.

Disorienting Thrust applies native Blind for at most 4 seconds before resistance.
Guard Bash applies up to 2 seconds of resisted native attack delay. Both use the
existing 8-second shared control recovery and gain no training duration bonus.
Native immunity checks remain in force, including droid/bleed immunity.

A landed Probing Jabs hit grants Precision for 6 seconds, including a killing
hit. The next landed Fencer effect attempt consumes it even if immune or
resisted; misses do not consume it. Precision adds 5 potency before
resistance. Master-only Flawless Assault lasts 12 seconds, raises newly applied
Fencer bleed budgets to 100% of landed damage, and replaces Precision's +5
application bonus with +10. The training bonus still applies, under the 95% cap.
It neither raises existing budgets retroactively nor supplies free refreshes.
Precision and Flawless Assault are cleared on incompatible equipment, loss of
required training, death or incapacitation. Neither bypasses boss immunities.

Evidence: `runtime/evidence/fencer-*`. Headless mocked input and production
client routing, loadout UI, protocol validation, C++ budget/resistance policy,
full patch-stack replay and native translation-unit syntax are checked.
These checks use `--xr-mode off` and the dummy renderer. A linked native build,
actual native encounters and live headset rendering remain unverified under the
existing Podman runtime permission restriction. No deployment or live launch
was performed for this implementation.

## Pikeman crowd control (patch 0095)

Pikeman completes the four ordinary advanced melee profession kits. Its role
is moderate AoE damage with group disruption, without TKA's bonus threat or
Focus survivability, Swordsman's execution/armour break, or Fencer's bleed budget.
It requires original Pikeman training and an intact certified non-Jedi polearm.

| Ability | Original skill box | Damage | Action / Mind | Cooldown |
| --- | --- | --- | --- | --- |
| Unbalancing Thrust | combat_polearm_novice | 0.9× | 70 / 30 | 20 s |
| Concussive Strike | combat_polearm_accuracy_01 | 0.9× | 65 / 30 | 18 s |
| Pinning Strike | combat_polearm_speed_01 | 0.6× | 60 / 25 | 16 s |
| Disrupting Jab | combat_polearm_support_01 | 0.6× | 60 / 30 | 15 s |
| Overhead Whirl | combat_polearm_novice | 0.75× per enemy, max 4 | 90 / 35 | 16 s |
| Sweeping Trip | combat_polearm_ability_01 | 0.5× per enemy, max 3 | 95 / 40 | 22 s |
| Driving Jabs | combat_polearm_novice | 2 × 0.35× per enemy, max 2 | 65 / 25 | 10 s |
| Whirlwind | combat_polearm_master | 1× per enemy, max 6 | 150 / 80 | 120 s |

Unbalancing Thrust applies up to 2 seconds of knockdown. Concussive Strike applies
up to 4 seconds of native Stun (combat penalties, not complete immobilisation).
Pinning Strike applies a 40% slow for up to 5 seconds. Disrupting Jab applies up
to 2 seconds of native attack delay. Overhead Whirl is circular damage plus up to
2 seconds of Stun. Sweeping Trip covers the forward 180-degree arc and attempts
up to 2 seconds of knockdown. Driving Jabs uses a 40-degree cone and attempts a
30% slow lasting up to 3 seconds once per enemy after the two-hit sequence.
Whirlwind is circular damage plus up to 3 seconds of knockdown, once per enemy.

Every duration is reduced by native status resistance. Application uses 90%
base potency plus +5 to +10 from novice to master, then resistance, with final
chance capped at 95%. Training never extends hard-control duration. Explicit
native immunity checks remain authoritative, including boss encounter immunities.
Stun, knockdown and attack-delay attempts share the eight-second target control
recovery across players/abilities. AoE target selection ignores that recovery so
protected enemies still take damage, while the effect is skipped. Individual
hard-control VATS actions require an available control window before spending.
Already active native knockdown recovery is respected; Pikeman-applied knockdown
sets an eight-second knockdown recovery and a resisted posture-change delay.
A native scheduled task restores an eligible AI to standing after that delay;
it never revives dead/incapacitated actors or overrides a later posture delay.

Slows occupy distinct native buffs; AI movement takes the strongest of Pinning
Strike, Driving Jabs, Hamstring and Restraining Shot rather than adding them.
The weaker slow can remain underneath and resume if the stronger one expires.

All actions pay SAC once and share native weapon cadence. Minimum recovery is
1.5 seconds for VATS/jabs, 1.75 for whirl/trip, and 2 for Whirlwind. Every recipient
must be an attackable, living non-pet AI in the same zone, within native polearm
reach (at most 4 m) and line of sight. Targets are selected nearest-first with
object-ID tie breaking, and rechecked under lock. Jabs keep a fixed capped target
set and never transfer a remaining thrust after killing its recipient. Empty or
invalid selection costs nothing; an accepted miss retains costs and cooldown.

Advanced knockdown/stun replace the original catalog entries using the existing
IDs and `corecu_brawler_*` cooldown keys. Saved polearm slots continue to work.
The legacy `/melee` route delegates learned upgrades to the same native Pikeman
resolver, preventing old clients from bypassing advanced costs/effects/cooldowns.
Other weapon families retain their original Brawler/TKA behavior.

Validation evidence: `runtime/evidence/pikeman-*`. Mocked gesture and production
client routing, loadout UI, protocol checks, native syntax, policy geometry,
strongest-slow combinations and full patch replay are covered. Headless runs use
`--xr-mode off` and dummy rendering. Linked native server build, actual NPC
encounters and headset rendering remain unverified; the previous full build
was blocked by Podman's `/run/user/1000/libpod` runtime permissions. No live
client launch or deployment was performed in this implementation.

### Melee coverage and remaining work

The ordinary melee kit coverage is Brawler foundation plus TKA, Swordsman,
Fencer and Pikeman. This excludes Jedi and hybrid/multiprofession balancing.
Original skill boxes, certifications, native combat progression and passive
resistance contributions remain the progression source. This is curated CU-based
coverage rather than one executable XR action for every original command grant.

- Force of Will is implemented as TKA support recovery (see below). Meditate and
  Power Boost are retired, with native command entry points disabled and grants
  suppressed. There is no replacement Second Wind ability.
- Dizzy/posture-chain attacks, separate Action/Mind-targeting attacks, redundant
  basic-hit ranks and duplicate spin attacks are intentionally omitted or folded
  into the approved kits. Physical attacks cover basic strikes; shared Health
  damage and profession abilities replace obsolete pool-specific specials.
- The special-ability resolvers currently target non-pet AI. PvP, hostile player
  pets and destructible/lair recipients need explicit eligibility and balance
  work; ordinary physical combat has its own broader target handling.
- Complete a linked native build and run actual encounters covering multi-player
  control recovery, immunity, timed stand-up, AoE caps, resource costs, persistent
  loadouts, Fencer bleed refresh/cures and Swordsman armour openings. Syntax and
  isolated policy tests do not establish end-to-end native runtime correctness.
- Validate controller gestures in a headset, especially overhead loops, low
  sweeps, dominant-hand changes, support grips and rapid ordinary/special attack
  transitions. Mock tracking does not establish real tracking tolerance.
- Tune profession DPS, threat, SAC sustain and control uptime against identical
  encounters, and review legacy skill-description text/passive modifiers against
  the final CU role balance. Native progression is retained, not freshly proven
  balanced by these local tests. Dedicated audiovisual feedback can be refined
  after that gameplay validation; current attacks reuse the native hit feedback.

### Force of Will and retired TKA utilities

Force of Will unlocks at Master Meditative Techniques
(`combat_unarmed_accuracy_04`) with Novice TKA retained.
It is an unarmed-family support ability in the gesture row, outside the four
positional slots and the one ultimate slot. Indomitable Focus remains the TKA
ultimate. A certified unarmed weapon, actual incapacitation and an existing
incapacitation-recovery task are required. Death, feign death, cloning/loading,
pending transport and Sedative H4b's pinned-HAM withdrawal reject activation.

Release then hold the offhand stick while incapacitated. Normal recovery begins
after one second. Continue holding for three seconds total to request Force of
Will; releasing earlier leaves ordinary recovery running. Tracking loss, inactive
controls, invalid frame timing and native rejection require a fresh release.
The client never predicts revival. If ordinary recovery finishes first, the
long hold is discarded without consuming Force of Will.

The server raises Health to at least `ceil(0.15 * max(1, maxHealth - wounds))`,
preserving higher Health within its effective cap. Action and Mind, Health
wounds, battle fatigue, incapacitation count, enemy threat and other cooldowns
are not reset. Recovery grants no invulnerability or resurrection. The fixed
600-second cooldown uses persistent player screenplay data, plus the existing
native cooldown, and is shared by the original command and the life endpoint.
There are no legacy success rolls, failure wounds or post-recovery stat penalties.

Patch `0096-force-of-will.patch` supplies the shared native implementation and
retired command/grant handling. Resource normalization removes old Meditate
work and Power Boost buffs through their native cleanup, without refilling HAM;
Jedi Force Meditate remains separate. Dead, incapacitated and spice-pinned
characters defer resource normalization as before. TKA profession descriptions
now describe the curated kit rather than advertising retired actions.

Validation covers policy boundaries, owned life requests, client hold/release
and rejection handling, existing life/transport regressions, native syntax and
full patch-stack replay. These checks use mocked replies and the dummy renderer;
a linked native build, actual recovery encounter and headset test remain pending.

### Physical aim, enemy accuracy and secondary defenses

User decision: player aim/contact determines whether a weapon attack connects;
accuracy rolls govern enemy attacks. Player hits still undergo normal dodge,
block, counter and applicable saber-deflection resolution. Physical blocking and
moving clear of a shot or attack range provide additional protection; they do
not replace RPG defenses in networked play.

Patch `0098-player-secondary-defense.patch` corrects the overbroad secondary-
defense bypass in `0097`. Validated player contacts start as HIT and continue
through the ordinary secondary defense stage. Player accuracy contributes zero
to its opposed roll; defender rating, posture, CoB and native RNG remain. NPC
and companion attacks retain innate accuracy. Armour, damage variation and
status application/resistance are separate from contact and secondary defense.
Client projectile contact supplies spatial hit evidence; native shot receipts,
skill, costs, cooldowns and target eligibility precede resolution. Existing melee
and area abilities retain their bounded native target selection.

Player accuracy does not increase ranged damage or melee contact radius.
Patch `0099` preserves the original Marksman one/two-handed range scaling and
crouch/prone mitigation of negative distance damage. These authored weapon/pose
bonuses are separate from player skill accuracy. The client determines projectile
contact, including movement spread; Core3 resolves damage and secondary defenses.
Movement spread: pistols exempt, carbines 1.2-degree cap, rifles 4-degree cap,
heavy/repeater classes 6-degree cap, reached at 5 m/s horizontal movement.

Aim stays off the Marksman shortlist as a player accuracy buff. Point Blank Shot
has no role solely compensating an innate player accuracy penalty. Suppression
can meaningfully reduce ENEMY accuracy while normal resistance rules apply;
that penalty must not turn an accepted player projectile into a primary miss.

Validation runs the actual native hit-resolver body with deterministic fixtures:
60 cases cover normal secondary defenses, player accuracy invariance, no innate
player miss, NPC fallback, and Force/state exclusions. This is an isolated
resolver test, not a live encounter. Native syntax, ordered patch replay,
profession translation and headless client regressions are checked separately.
Linked native build, actual encounters and headset validation remain pending.


### Marksman positional abilities (patch 0100)

These are CU-inspired local tuning values, not historical CU stat claims. They
use the existing four regular slots per weapon family, with no Marksman ultimate.
Original grants map to the following attacks; native `attack` supplies their
clean damage command so old pool attacks and bundled pre-CU states cannot leak in.

| Ability / original grant | Damage | Action / Mind | Cooldown | Extra effect |
| --- | --- | --- | --- | --- |
| Suppression Fire / suppressionFire1 | 0.5x | 45 / 15 | 18 s | -20 enemy accuracy, at most 6 s; resisted as Blind. |
| Warning Shot / threatenShot + warningShot | 0.25x | 35 / 15 | 20 s | Attack delay 2 s, improved to 3 s at Support III; bosses immune; preserves threat. |
| Controlled Burst / fullAutoSingle1 | 3 × 0.65x | 75 / 20 | 12 s | Carbine only; no extra statuses. |
| Bleeding Shot / healthShot1 | 0.8x | 50 / 20 | 16 s | Pistol only; 30% landed Health damage bleed budget, at most 12 s. |

Base costs are fixed; active Pistoleer Run and Gun discounts compatible regular
pistol specials by 25%. Health is never spent, and Action/Mind must remain above zero.
Spice cooldown scaling remains. Cadence is the normal native weapon interval.
Effects use 85 base application chance before normal CU resistance; immunity and
native duration reduction remain. A valid control attempt after landed damage
starts the existing 8-second shared control recovery, including a resisted
attempt. Warning also honors Core3's longer `nextAttackDelayRecovery` and cannot
refresh a pending delay. Suppression cannot stack or refresh while active.

Bleeding Shot reuses Fencer's single bounded bleed channel per target: incoming
budget replaces remaining budget only when greater, preserves the next tick,
and retains cures, absorption and duration resistance. Ticks are 3 seconds apart
with the existing initial tick timing. It cannot add a parallel stack to a
Fencer bleed. Fencer's 50–80% budget and effect bonuses remain stronger.
Droids and bleed-immune targets are ineligible.

Controlled Burst uses one registered launch/contact and the existing single-round
client firing transaction. Its three damage resolutions occur together against
the bound entity, each retaining dodge/block/counter/deflection and native armour.
Costs and cooldown are charged once, even if the projectile misses. Resolution
stops on death, incapacitation, loss of attackability or native rejection. This
is not three independently simulated projectiles or a cone attack.

Physical contact is client-authoritative; damage, effect chance, resistance,
secondary defenses, threat and rewards remain native. The captured grip/range
curve, posture damage bonus and sampled movement spread are preserved. No
innate player accuracy roll, Aim buff or pool-specific Action/Mind damage returns.

Validation: eight headless client suites (1,028 checks), 312 policy cases,
38 executions of the actual effect/eligibility methods with isolated native
dependencies, 60 existing hit-resolver cases, protocol tests, two native
translation-unit syntax checks and full ordered patch replay. Profession catalog
regenerated from supplied assets with updated descriptions. At this stage the
full linked build was blocked by Podman failing to set the sticky bit on
`/run/user/1000/libpod` (read-only filesystem). The subsequent Pistoleer build
below resolved that environment blocker and verified the complete linked native
build. No live server, GPU or headset validation is claimed.

### Pistoleer mobile pressure and gestures

Pistols retain zero movement-added spread. This weapon property makes Pistoleer
effective while repositioning; neither the new abilities nor Run and Gun replace
physical aiming, range checks, armour or secondary defenses. Tuning below is
local CU-inspired design, not a claim about historical CU values.

| Ability / original grant | Delivery | Damage | Action / Mind | Cooldown | Extra effect |
| --- | --- | --- | --- | --- | --- |
| Double Tap / `doubleTap` | Chest marker; one contact, two resolutions | 2 × 0.8x | 60 / 20 | 12 s | One bound target; each hit retains normal defenses. |
| Disarming Shot / `disarmingShot1` or `disarmingShot2` | Weapon-arm marker | 0.5x | 45 / 20 | 18 s | Resisted 20% enemy outgoing-damage suppression, up to 6 s. |
| Improved Bleeding Shot / `healthShot2` | Existing abdomen marker | 1.0x | 50 / 20 | 16 s | 40% landed-damage bleed budget, at most 12 s; upgrades existing Marksman slot/channel. |
| Fan Shot / `fanShot` | Two offhand cock-fanning strokes | 1.0x per recipient | 80 / 25 | 16 s | 60-degree muzzle cone; up to five enemies; no additional statuses. |
| Run and Gun / Pistol Stances II | Either deliberate stance held 0.8 s | None | 80 / 40 | 60 s | 8 s: 25% faster ordinary pistol fire, 25% cheaper regular single-target pistol specials. |
| Showdown / Master Pistoleer | Selected ultimate; three physical projectiles | 3 × 0.9x | 150 / 75 once | 120 s | Once per volley, first damaging contact attempts resisted 30% enemy outgoing-damage suppression, up to 5 s. |

Warning Shot remains the fourth recommended VATS ability, using its existing
Marksman grant, effect and shared recovery. These are choices within the common
four slots, not a forced loadout. Fan Shot and Run and Gun use the gesture row
without taking a slot. A Pistoleer/Smuggler or Pistoleer/Bounty Hunter can use
them with other learned compatible pistol attacks and a different selected
ultimate. Showdown requires Master Pistoleer and the equipped ultimate slot.

Fan Shot is Pistoleer's only damaging area attack. Its targets require native
eligibility and line of sight, within the shorter of 12 m and current one-handed
pistol range. The client supplies only muzzle origin/direction; the server
chooses the bounded cone recipients. It never receives an arbitrary target list
or client damage. Trigger-free offhand fanning above the rear/top of the pistol
is separate from support grip and ultimate input, measured relative to the
weapon rather than world movement.

Run and Gun uses either a low hip-fire hold with the offhand extended sideways
(Bond) or a high sideways-canted hold with the offhand clear (gangster). Both
triggers must be released for the 0.8 s hold. Recognition mirrors left-handed
use and uses head-relative height for seated play. Both variants share one
8 s buff and 60 s cooldown, require leaving the pose before rearming, and cannot
stack or refresh. Fan Shot and ultimates receive no discount or tempo bonus;
ordinary pistol cadence and current special costs come from the native snapshot.
Run and Gun activation uses 0.25 s recovery so the buff window remains available
for firing. Fan Shot uses the normal weapon recovery with a 1.5 s floor.

Showdown launches one shot at activation and two further shots at least 0.25 s apart,
using the current tracked muzzle for each. Continuations wait for the preceding
launch acknowledgment plus 0.25 s, so network latency can extend the interval or
expire a volley. All three remain bound to the same
opponent and weapon. A native volley token reserves one paid activation and
permits only the next unused sequence index within a short expiry. Independent
shots can miss or be defended. Target/weapon changes, loss of valid player state
or interruption can end the sequence; committed costs and cooldown remain.
There is no target hopping, splash, client-supplied damage or repeated resource
discount. The first damaging contact spends the single suppression attempt,
whether or not the target resists it. Existing stronger suppression wins instead
of stacking with Disarming Shot or other damage reduction.

Bleeding Shot continues to share the existing bounded Fencer bleed channel;
Pistoleer's 40% budget remains below Fencer's specialist 50–80% progression.
Original ranks do not create extra slots, bleed stacks or independent cooldowns.
All Action/Mind costs are native and Health is not spent.

Ammunition uses the existing client magazine/reload accounting: Double Tap
reserves two rounds, Fan Shot three, and Showdown requires three available before
activation then spends one for each physical projectile launched. Confirmed
failed launches restore their local reservation; misses and failed impacts do
not. This is not a new persistent Core3 ammunition model. SAC, cooldowns, target
selection for Fan Shot, damage and effects remain native authority.

Validation: all 482 Python tests pass, including ten Pistoleer protocol tests,
the authenticated TLS route and executions of the actual native grant/effect,
buff, cone-selection and launch-receipt methods with isolated dependencies.
Pistoleer gesture and production gameplay routing suites pass 25 and 67 checks
respectively, using synthetic/mocked tracking and the dummy renderer. The actual
imported starport stair regression ascends and descends while preserving tracked
head pose; 12 related client suites pass 603 checks in total. Logs and reports are under `runtime/evidence/pistoleer/`,
`runtime/evidence/pistoleer-gestures.json`,
`runtime/evidence/pistoleer-routing.json` and
`runtime/evidence/xr-authored-starport-stairs.json`.
The official `tools/server/build.sh` completes full configuration, ordered patch
application, linked native build, and build-receipt verification; see
`runtime/evidence/pistoleer/native-build-verified.log` and
`runtime/server/native-build.json`. This supersedes the earlier Podman blocker.
No live server launch, GPU or headset validation is implied.

### Carbineer ranged crowd control

Carbineer controls enemy approaches at medium range. Carbines retain their
1.2-degree movement-spread cap, supported range curve and physical player aim.
The following is SWGXR tuning derived from the source profession's control
concepts, not historical pre-CU or CU combat values. Source training,
prerequisites and certificates are preserved.

| Ability / original grant | Delivery | Damage | Action / Mind | Cooldown | Extra effect |
| --- | --- | --- | --- | --- | --- |
| Crippling Shot / `cripplingShot` | Knee marker | 0.6x | 55 / 20 | 16 s | Resisted 40% movement slow, up to 6 s. |
| Wild Shot / `wildShot1` or `wildShot2` | Head marker | 0.7x | 60 / 25 | 18 s | Resisted native Stun, up to 3 s; rank II improves base application chance from 85% to 90%. |
| Suppression Fire / `suppressionFire2` | Existing weapon-arm marker | 0.5x | 45 / 15 | 18 s | With a carbine, resisted -25 enemy accuracy, up to 6 s. |
| Charge Shot / `chargeShot1` or `chargeShot2` | Pelvis marker | 0.8x | 75 / 30 | 24 s | Resisted knockdown, up to 2 s. |
| Full Auto Sweep / `fullAutoArea1` or `fullAutoArea2` | Supported horizontal sweep, reverse and settle | 0.5x per recipient | 90 / 30 | 20 s | 75-degree muzzle cone, up to five enemies; resisted 35% slow, up to 4 s. |
| Tactical Brace / Counterinsurgency II | Level, cant at chest, hold 0.8 s, return level | None | 50 / 25 | 60 s | 8 s: +10 carbine control potency before resistance, capped at 95% final chance. |
| Charge Blast / Master Carbineer | Selected ultimate; supported both-trigger chord | 0.75x per recipient | 150 / 80 | 120 s | 90-degree muzzle cone, up to six enemies; resisted knockdown, up to 3 s. |

The recommended VATS loadout is Crippling Shot, Wild Shot, Suppression Fire and
Charge Shot. Existing Controlled Burst is a single-target damage alternative.
Suppression Fire is one ability with one slot and cooldown: Counterinsurgency IV
unlocks it independently of Marksman Support, and the stronger accuracy debuff
requires both Carbineer training and a carbine. Its ordinary Marksman behavior
remains available to compatible weapons when the Marksman grant is learned. Source attack ranks do not create
duplicate abilities, pool-specific damage or Blind/Dizzy/Stun bundles.

Full Auto Sweep and Tactical Brace require learned training and a held,
certified, usable carbine. They occupy neither the four targeting slots nor the
selected ultimate slot. Combined professions retain both gestures when they
train Carbineer, alongside other learned compatible carbine abilities and a
different selected ultimate. Charge Blast requires Master Carbineer and the
selected carbine ultimate slot. Forward Check is excluded.

Both gestures require supported two-handed grip and released triggers. Full
Auto Sweep recognizes a deliberate horizontal sweep, reversal, return toward
the initial forward direction and brief settlement. Tactical Brace recognizes
a level start, a chest-height canted hold of approximately 0.8 seconds, then a
return level. Ordinary steady aiming does not activate the buff. Both recognize
mirrored handedness and head-relative seated positions, require neutral rearming,
and cancel on tracking loss, equipment changes, menus or competing input. No
animation drives the tracked head, hands or physics body.

Area attacks use the actual final muzzle origin and direction, not the swept
path. Full Auto Sweep reaches the shorter of 18 m and supported weapon range;
Charge Blast reaches the shorter of 20 m and supported weapon range. The native
server selects eligible living non-pet AI recipients with line of sight, ordered
nearest first with deterministic ties, and enforces each target cap. Each
recipient keeps normal armour, secondary defenses and effect resistance.
An accepted empty-cone attack still spends its costs and cooldown.

Charge Blast adapts the source Charge Shot II cone-knockdown concept into a
Master ultimate. It needs no bound VATS target and causes no physical knockback.
Charge Shot remains a separate single-target option. Stun weakens native combat
effectiveness; it is not a complete movement freeze. Hard-control attempts and Suppression Fire retain the
existing eight-second shared recovery, including resisted attempts. Immunities,
native duration resistance and existing longer recovery limits remain. Movement
slows use the strongest active value instead of multiplying together.
Crippling Shot, Wild Shot and Charge Shot remain available against otherwise
eligible targets while a control effect is immune or recovering: the landed
attack can still deal damage and only its control effect is withheld. Existing
Suppression Fire retains its control-availability filtering.

Tactical Brace only raises carbine control application potency, before resistance,
under the 95% cap. It does not extend durations, bypass immunity or recovery,
improve spread, raise damage, accelerate fire, reduce costs, or stack with itself.
The bonus applies to the new Carbineer effects and existing Marksman Suppression
Fire and Warning Shot while holding a carbine. Legacy Smuggler effect formulas
remain unchanged; mixed-profession reuse means the learned Carbineer controls
and gestures remain available alongside those compatible abilities.
Leaving the pose does not end the buff. Losing the required training or usable
carbine invalidates it. Its activation recovery is 0.25 s; Full Auto Sweep uses
normal native weapon recovery with a 1.5 s floor and Charge Blast a 2 s floor.

Full Auto Sweep and Charge Blast each spend three rounds in the existing client
magazine/reload transaction; Tactical Brace spends none. Confirmed rejected
activations restore their local ammunition reservation. Accepted misses do not.
This does not introduce a persistent native ammunition account. Action/Mind,
cooldowns, area recipients, damage and control effects remain native authority;
player tracking, physical single-target contacts and magazine feedback retain
their existing client authority.

Validation: all 498 Python tests pass, including 11 Carbineer protocol tests,
authenticated TLS forwarding and both HTTP adapter execution paths. Ten client
suites pass 550 checks, including 22 gesture and 73 production routing checks,
with synthetic/mocked tracking and the dummy renderer. The actual imported
starport stair regression also passes while preserving tracked head pose.
Native fixtures cover 64 Carbineer policy checks, 42 executions of actual
Carbineer behavior groups, 45 Marksman effect/grant groups and existing Pistoleer
receipt behavior. Ordered patch replay verifies patch 0102 across seven paths.
Catalog regeneration preserves all 49 professions, 858 nodes and three original
source hashes; only descriptions change. Evidence is under
`runtime/evidence/carbineer/`, with gesture/routing reports at
`runtime/evidence/carbineer-gestures.json` and
`runtime/evidence/carbineer-routing.json`. The official `tools/server/build.sh`
completes configuration, ordered patch application and the linked Core3 build;
its recorded build receipt passes verification. See
`runtime/evidence/carbineer/native-build-verified.log` and
`runtime/server/native-build.json`. All five source/native header pairs match.
No live server launch, deployment, GPU or headset validation is claimed.

### Rifleman dedicated single-target damage

Rifleman specializes in heavy individual hits, concentrated physical volleys
and per-hit armour penetration. Rifles retain their existing movement spread,
supported-grip range curve and physical posture benefits. The following is
SWGXR tuning; original profession prerequisites, certificates and grant data
remain intact. Source Mind-pool damage, area Flurry and incapacitated-target
deathblows are represented by single-target Health attacks.

| Ability / original grant | Delivery | Damage | Action / Mind | Cooldown | Extra behavior |
| --- | --- | --- | --- | --- | --- |
| Head Shot / `headShot2`, improved by `headShot3` | Head marker | 4.0x / 4.25x | 110 / 40 | 30 s | Same `lethal_shot` ID, slot and cooldown; qualified rifles unlock independently of Master Marksman. |
| Piercing Shot / `mindShot2` | Chest marker | 2.0x | 75 / 30 | 18 s | Halves current Kinetic/Energy body resistance for this hit only. |
| Flurry Shot / `flurryShot1` or `flurryShot2` | Abdomen marker; three physical projectiles | 3 x 0.8x / 3 x 0.9x | 100 / 35 once | 18 s | Same bound opponent; minimum 0.25 s launch spacing. |
| Surprise Shot / `surpriseShot` | Shoulder marker | 2.0x / 3.0x | 80 / 35 | 24 s | Higher multiplier when native target Health is at least 80% of effective maximum at impact. |
| Rifleman's Focus / Concealment II | Offhand receiver bolting motion, then fore-end regrip | +20% for 8 s | 50 / 25 | 60 s | Ordinary rifle fire and compatible regular rifle specials; no ultimate bonus. |
| Sniper Shot / Master Rifleman plus `sniperShot` | Selected ultimate; supported both-trigger chord | 6.0x | 150 / 90 | 120 s | One physical projectile; minimum 2.5 s recovery. |

The recommended four VATS slots are Head Shot, Piercing Shot, Flurry Shot and
Surprise Shot. These share the usual family loadout with other learned
compatible rifle abilities. Head Shot upgrades the existing Lethal Shot row only
with Rifleman training and a qualified rifle; other families retain their
existing Lethal Shot behavior and heart marker. The upgrade moves that marker
to the head. The head marker selects an ability, without
adding a separate anatomical critical-hit system. Piercing Shot leaves no
persistent armour debuff for allies; it halves current impact-time resistance
after any existing Fractured Armour effect. Surprise Shot needs no stealth state.

Flurry creates three separately aimed physical projectiles, not one contact
with three automatic hits. Each retains physical aim, target binding, range,
armour and secondary defenses. It reuses the native volley receipt mechanism
with an ability-specific identity, a fixed weapon/loadout and a two-second
continuation window. The client launches each continuation only after the
preceding accepted receipt and the 0.25-second spacing. Network delays can
lengthen or expire the volley. Native costs and cooldown are paid once;
duplicates, reordering, changed targets, invalid player state and expired
continuations cannot provide free shots. A missed or interrupted volley does not
refund accepted launches and never retargets or applies area damage.

Rifleman's Focus requires Novice Rifleman plus Concealment II
(`combat_rifleman_speed_02`), a held certified usable rifle and the completed
bolting gesture. This is an explicit new SWGXR node gate; no source skill graph
or grant is rewritten. Begin supported with both triggers released, release the
offhand from the fore-end, grasp at the side of the receiver, pull rearward,
push forward, release and regrip the fore-end. The weapon hand keeps its grip;
activation occurs only after support is restored. The recognizer is mirrored
for handedness and uses rifle-relative motion suitable for seated play.
Ordinary aiming, a static cant or a held posture does not activate it. Tracking
loss, invalid jumps, equipment changes, menus and competing combat input cancel
recognition; movement is tracking-driven throughout.

Focus takes neither a targeting slot nor the selected ultimate slot. Combined
professions retain it alongside their other learned compatible rifle abilities
and a different selected ultimate. The buff improves direct ordinary and
regular-special rifle damage; it does not amplify ultimate damage or alter
movement spread, range, accuracy, cadence, resource costs or cooldowns. It does
not stack with itself. Each projectile captures its Focus multiplier at launch;
the buff does not rewrite shots already in flight. Losing the required rifle,
training or valid life state invalidates the buff. Activation recovery is
0.25 seconds. The gesture has no ammunition cost and is not a reload.

Sniper Shot requires Master Rifleman, the native `sniperShot` grant and the
selected rifle ultimate. Aim at one eligible enemy, support the rifle and press
both triggers together. It preserves the physical projectile and normal
defenses, works against eligible bosses and uses native weapon recovery with a
2.5-second minimum. There is no source deathblow requirement, area damage or
additional crowd-control effect.

The existing local magazine system requires three rounds before Flurry starts
and spends one per launched projectile; the other attacks spend one. A confirmed
failed launch restores its local reservation. Accepted shots remain spent even
if their impacts miss. Native Action/Mind, cooldowns, training, selected loadout,
damage and penetration remain authoritative; no persistent native ammunition
account is introduced. Automated checks cannot establish live headset rendering
or bolting-gesture comfort.

Validation: all 517 Python tests pass, including 13 Rifleman protocol tests and
authenticated HTTP/TLS routing. Twelve client suites pass 660 checks: 30 bolting
gesture, 77 production routing and 553 shared regression checks. The actual
imported starport stair regression passes with tracked head pose preserved.
Native fixtures cover 102 behavior, 52 Rifleman policy and 49 production armour
cases. Ordered patch replay verifies patch 0103 across eight paths; all five
source/native header pairs match. The official build links Core3 successfully
and its recorded receipt passes verification. Catalog regeneration preserves
49 professions, 858 nodes, every original graph value and three source hashes;
only the 18 Rifleman descriptions change. Consolidated evidence is in
`runtime/evidence/rifleman/validation.json`; build and receipt logs are
`native-build-final.log` and `native-build-verification.log` in that directory.
Client checks use headless dummy rendering and synthetic/mocked tracking. No
deployment, live server/client launch, GPU or headset validation is claimed.

## Commando: equipment-driven elemental area damage (2026-10-09)

Commando retains the original prerequisites, skill boxes, certifications and
Weaponsmith/loot supply chain. No Commando schematic grants are added. Its role
is bounded elemental area damage paid through equipment, charges and Action.
Rifleman remains the single-target damage specialist, Carbineer the ranged
control specialist, and Combat Medic retains the highest debuff potency.

| Equipment | Primary delivery | Native range | Supply |
| --- | --- | --- | --- |
| Flamethrower | 40-degree cone and one bounded fire channel | 12 m | Reusable, local magazine |
| Acid rifle | Narrow directed beam; optional 30-degree weaker Acid Spray | 24 m; spray 14 m | Reusable, local magazine |
| Heavy particle beam | Narrow directed area beam | 32 m | Native charges |
| Heavy acid beam | Wider directed area beam | 24 m | Native charges |
| Heavy lightning beam | Widest directed area beam | 24 m | Native charges |
| Rocket launcher | Physical rocket and 5 m blast | 48 m | Native charges |
| Pistol launcher | One-handed physical burst and 4 m blast | 36 m | Reusable, local magazine |

The four consumable heavy templates receive an explicit original `hold_both`
equipment arrangement, so native inventory/equip rules can hold them; their
source meshes and original empty media arrangements remain recorded faithfully.
All seven weapons use the heavy-family ability loadout, and the reusable weapons'
original pistol/rifle folders cannot import Pistoleer or Rifleman damage bonuses.
The pistol launcher retains the pistol movement-spread exemption.

Area attacks select at most six legal enemies, use range/angle falloff and share
an aggregate 2.5-packet budget. Legacy heavy damage multipliers, weapon damage
mods and weapon DoTs cannot multiply the normalized packet. The one Commando
fire channel preserves its next tick and remaining budget on refresh. It does
not stack per weapon or caster. Existing 80% primary / 20% elemental conversion,
armor-piercing budget, condition and elemental PSG rules still apply; Acid does
not implicitly weaken armor.

Focused Discharge trades all coverage for +15% direct damage on one enemy,
with 12-second recovery. Acid Spray uses 70% direct damage and six-second
recovery after the original acid cone unlock. Master Overdrive lasts six
seconds, adds 25% direct damage, raises Action cost 50%, uses normal charges
and retains a persistent 120-second recovery. Burn strength and area caps do
not increase under Overdrive. Special-weapon recovery is shared across swaps;
resource and charge reservation occurs once on native acceptance.

Grenades share the trap physical throw interaction. Fragmentation supplies
baseline blast damage; Imperial/Thermal/Proton increase coverage with longer
family recovery. Thermal retains its original Blast mapping; Proton retains
Heat. Cryoban/Glop trade direct damage for brief resisted control. Light
fragmentation remains baseline species-certified equipment. Generic poison
and incomplete fallback grenade templates are not exposed as Commando abilities.
Shared recovery is 12 to 9 seconds, individual radii 4 to 8 m, and direct output
is capped at 360 before armor per best-quality trained single-target throw.
Cryoban/Glop potency is at most 105 before resistance, below Combat Medic's 125.

The calibration report is generated by `tools/server/audit_commando_balance.py`
from production policies. It records its reference rotation, training, crafting,
resource and armor assumptions; it is arithmetic evidence rather than a live
encounter or headset measurement. Repeat it after changing weapon cadence,
quality mapping, damage conversion, grenade contribution or resource costs.

The calibrated Master whole-kit output is **81.5–84.3% of Rifleman over 120
seconds**, within the intended 75–85% single-target reference. Sampled
intermediate builds reach 75.4–84.5%; eligible novice equipment reaches
approximately 75.0–78.4%. At best crafting quality, Master output remains
83.1–84.9% over 300 seconds and 83.2–84.0% over 600 seconds when the rotation
preserves Action for weapon fire. Progression is monotone and capped at the
mastered damage envelope; legacy weapon bonuses cannot multiply it again.

These comparisons use an unarmored stationary target, matched source crafting
quality, 1,000 starting Action/Mind and 10/8 regeneration, actual magazines and
reloads, consumable heavy replacement, learned Rifleman abilities, and Commando
grenades/Focused Discharge/Overdrive. Rifleman range/posture scaling is neutral;
Commando uses peak shape damage. Grenade throws have no additional hand-motion
downtime in this optimistic reference. Physical range, aim, armor and elemental
resistance deliberately change the matchup; the percentage is not a promise
for every distance or defender. The report includes those assumptions and
separate armor cases rather than hiding them in the headline.

Validation: 585 Python tests pass, including isolated production fixtures with
76 Commando native-method checks, 84 grenade lifecycle/control checks and
22,772 policy cases. Dedicated client checks pass 99 routing/charge cases,
54 original-skeleton/equipment cases and 20 grenade interaction/effect cases;
shared weapon, particle, movement and prior-profession regressions also pass.
The 34 source-locomotion checks include voluntary Cryoban/Glop movement limits
while preserving physical room-scale and HMD tracking. Actual imported-stage
collision and all 12 starport portal movement profiles pass. Asset validation
passes 1,004 checks across 36 weapons and 432 source dependencies; all seven
grenade families use converted original effects with no conversion failures.
Core3 links successfully and the final source/binary receipt verifies.
Consolidated evidence is `runtime/evidence/commando/validation.json`.
Client validation uses the dummy renderer and OpenXR off; no deployment,
live encounter, GPU or headset validation is claimed.

## Squad Leader: group support (2026-10-09)

Squad Leader multiplies a real party's effectiveness and supplies no new solo
attack or ungrouped damage bonus. Original prerequisites, skill points and
grants remain. Any current online, living Squad Leader can supply the strongest
contribution in each category to eligible party members on the same planet;
it need not be the elected leader. Passives have no distance or building limit.
Another eligible player must be present in the party on that planet; pets and
offline members cannot activate solo benefits. Membership, skills, life state
and planet are evaluated natively whenever effects are used.

Master passive caps are **+10% direct attack damage, +10% existing Action/Mind
regeneration, +15 melee defense and +15 ranged defense**. Defense affects native
accuracy contests; it does not change player physical aim. Each Offense box
contributes 2% damage, each Movement box 2% regeneration, and Master contributes
another 2% to each. Original group defense contributions are halved, capped at
15 and rounded up once after summation. Multiple leaders contribute the
strongest value, never a sum. The profession UI shows these CU values while
retaining the original modifiers separately as source metadata.

All five learned support abilities are available through friendly VATS with
any weapon, including unarmed, independently of offensive targeting slots.
Aim at a visible eligible party member within 48 metres and select a shout;
it affects eligible nearby party members, including the caster when another
recipient qualifies. These active effects require nearby range, native cell
context and line of sight; only the passives are planet-wide.

| Ability | CU effect | Duration | Recovery | Action / Mind |
| --- | --- | --- | --- | --- |
| Steady Aim | +15% direct damage; additive with SL passive to +25% | 12 s | 45 s | 60 / 30 |
| Rally | 15% less incoming direct attack damage | 12 s | 60 s | 70 / 40 |
| Form Up | Clear Stun/Dizzy; +20 status rating within the existing 100 baseline cap | 6 s | 45 s | 60 / 40 |
| Boost Morale | +50% existing Action/Mind regeneration; additive with SL passive to +60% | 15 s | 90 s | 40 / 60 |
| Retreat | +20% voluntary movement speed; no forced movement or threat reset | 8 s | 60 s | 80 / 30 |

Shouts share two seconds of command recovery. Each recipient also retains the
ability's recovery, preventing different leaders from chaining the same buff.
Source membership epochs invalidate active orders after departure/rejoin.
Doctor preparation resistance still adds after Form Up's capped baseline.
Boost Morale does not heal Health, refill pools, increase maximum resources or
redistribute wounds. Retreat changes joystick/desktop speed and the native
movement budget; tracking still drives physical room movement, head and hands.

Master Squad Leader with the original Volley Fire grant can select **Volley
Fire** in any weapon family's existing ultimate slot. It costs 80 Action /
40 Mind, uses no ammunition itself and has persistent 120-second recovery.
Cast at one eligible visible enemy within 64 metres to grant each captured
eligible party member a separate 12-second mark. Every member sees their own
large local reticle, including through geometry while the mark remains valid.
The current target set follows native live combat's hostile AI/lair scope.

A direct attack explicitly aimed at that reticle or bound to the marked enemy
spends the attacking member's mark if the target is within that attack's native
range. The native server guarantees its first damage packet despite physical
aim/contact, line of sight or avoidance failure. Other packets in a multi-hit
attack retain normal defenses. Normal damage, armor, costs, charges, cadence,
attack eligibility and separate status resistance remain. There is no free
extra attack. Ranged guarantees settle from the accepted native attack receipt;
cosmetic projectiles cannot submit a second impact. Traps and grenades retain
their native delayed execution after an accepted in-range throw, with one
guaranteed primary hit. Self-buffs, taunts, pure status applications and ongoing
DoT ticks do not spend a mark.

A grenade's marked primary can move after the accepted throw and still receive
that hit; collateral targets and effects remain at the original landing point.
The guarantee does not move or duplicate the explosion or increase its damage
budget and target cap.

Joining after a cast grants no mark. Departure/rejoin invalidates captured
membership; spent grants cannot be recovered by changing weapons or sessions.
Only one mark is active for a group, and recipients have persistent 120-second
grant recovery against repeated casts by other leaders. Out-of-range or
rejected attacks leave the mark unspent; a valid hit fully absorbed by armor or
shields still consumes it. The old automatic Volley attacks, accuracy buffs,
terrain/Burst Run passives, forced posture and wound-sharing implementations
are retired from the native command paths.

`tools/server/audit_squad_leader_balance.py` compiles the current production
policies and records the envelope in `runtime/evidence/squad-leader/balance.json`.
With ideal uninterrupted uptime, mastered damage support is 1.25x at peak and
1.14x on average; Rally averages 3% direct mitigation. Action/Mind regeneration
is 1.60x at peak and 1.1833x on average, or 1.84x / 1.3608x with the strongest
Doctor Metabolic preparation. These multiply existing regeneration and provide
no immediate resources. Using all five shouts plus Volley on cooldown costs
6.28 Action and 3.72 Mind per second, before any offensive spending, against the
10/8 reference regeneration. Volley has no universal DPS multiplier: its value
depends on which otherwise missed attack a member commits. These are arithmetic
policy bounds, not measured live encounter or headset results.

Validation: all 600 Python tests pass, including 6,649 production support checks,
47 Volley Fire checks and the shared physical-accuracy, grenade, profession,
Doctor resistance and fractional-regeneration fixtures. The dedicated client
passes 84 checks; source locomotion passes 38, shared profession XR input passes
20, and all 12 actual starport portal movement profiles pass. Core3 links and
its final source/binary receipt verifies. The catalog comparison preserves all
49 professions, 858 nodes and three original source hashes; only Squad Leader's
presentation changes. Consolidated evidence is
`runtime/evidence/squad-leader/validation.json`. Client checks use mocked native
transport/tracking, the dummy renderer and OpenXR off. No live encounter,
deployment, GPU or headset validation was performed.

## Bounty Hunter single-target combat (2026-10-09)

**Status: implemented in source; current native build and live acceptance are
pending.** The separate PvE mission, informant and consumable-droid foundation
is also implemented. The user explicitly sets single-target combat as Bounty
Hunter's focus. The implementation keeps the original pre-CU
skill graph, prerequisites, XP and certifications; completing BH plus its
prerequisites should permit ordinary bounties, while a second combat profession
supplies the output or wider toolkit needed for demanding marks. Player bounties
and player Force-sensitive professions remain outside this release.

### Historical comparison

The [preserved early CU proposal](https://www.tradealliance.nl/community/dshs-lounge/test-center-update-combat-upgrade-info/)
describes BH as a one-opponent specialist with strong offense and defense,
secondary medium-range mitigation and little crowd control. It lists Fast
Blast, Underhand Shot, Confusion Shot, Eye Shot, Torso Shot, a cone Spray Shot,
the scatter pistol and Light Lightning Cannon. This is a January 2005 community
transcription attributed to the CU proposals, not an authenticated surviving
SOE-hosted specification or proof that every entry shipped.

The [archived SOE publish notes](https://swgreckoning.org/archive/data/20070126114830/content_001.html)
provide stronger evidence of shipped behavior: Publish 19 (June 29, 2005)
increased Duelist Stance defense and changed lightning-rifle movement modifiers
to the rifle category. Publish 21 (August 4) describes consumable seeker
identification and continuing waypoint tracking, alongside harder NPC marks.
The [May 2005 interview with producer Julio Torres](https://www.mmorpg.com/interviews/combat-upgrade-qanda-2000113886)
supports distinct profession roles, ordinary solo content and harder group
content. None supplies the numerical policy used here.

Our deliberate adaptations are Health-only damage; a reduced standalone damage
budget that rewards a second combat tree; physical aiming; and no BH area
attacks. Retiring Spray Shot therefore departs from that early proposal in
accordance with the user's single-target direction. Duelist preserves a
documented defensive role through bounded protection rather than an accuracy
evasion stack. The current mission implementation retains pre-CU investigation
gates and permits eligible group assistance; it does not copy CU combat-level
gates or Publish 21's owner-only target attack restriction.

### Actions and balance values

`D` means one ordinary hit from the held weapon after its CoreCU equipment
normalization, before the same normal target mitigation. Costs are Action /
Mind. Every damaging action still needs normal range, physical contact or the
existing targeted-attack delivery, defenses and ammunition. A VATS marker
selects an ability; it does not itself guarantee a hit. Values below are local
starting parameters, not recovered CU formulas or measured encounter results.

| Action | Activation / original progression | Effect | Recovery; cost |
| --- | --- | --- | --- |
| Eye Shot | Pistol VATS, head marker; Pistol II | 0.6D Health hit; -25 NPC accuracy for up to 6 s, resisted as Blind through the existing suppression channel | 18 s; 50 / 20 |
| Bleeding Shot → Torso Shot | One pistol VATS abdomen entry; Pistol I → IV | 0.8D hit; shared Health bleed budget rises from 40% to 45% of landed damage, over up to 12 s | 16 s; 55 / 20 |
| Confusion Shot | Carbine VATS, torso marker; Carbine IV | 0.6D hit; one resisted native Stun, up to 3 s; no additional Dizzy | 20 s; 60 / 25 |
| Underhand Shot | Carbine gesture; Carbine I, improved by original Knockdown Fire grant at III | 0.65D hit; resisted knockdown up to 2 s; rank improves application, not duration | 24 s; 70 / 30 |
| Duelist Stance | Self-buff gesture; Investigation IV | 15% less incoming direct damage from one bound opponent for 8 s | 60 s; 60 / 30 |
| Fast Blast | Master ultimate; pistol, carbine or BH lightning rifle | One 3D Health hit against one enemy; no multi-pool damage or accuracy guarantee | 120 s; 140 / 70 |

Eye Shot shares Suppression Fire's accuracy-reduction channel: the strongest
effect wins, without adding a second native Blind penalty. It never blacks out
an HMD. Native Stun is combat impairment, not an invented full movement freeze.
Applicable control attacks retain the shared eight-second recovery and native
immunities, preventing independent BH/Marksman/Carbineer control chains. Bleed uses the
existing shared channel, native resistance and droid immunity. At the advanced
rank its total budget is 0.36D only if the 0.8D hit lands fully; this is not an
extra fixed 0.45D. It cannot stack separate Marksman, Pistoleer and BH bleeds.
The strongest learned compatible profile wins, including its costs. This stays
below Fencer's normal 50–80% bleed budget and its 100% Flawless Assault peak.

Underhand recognition is a low carbine hold followed by a short upward
muzzle arc and return to aim. With released triggers it arms one enhanced shot
for at most 1.5 s; a deliberate trigger commits the shot. Misses still pay and
consume the opportunity. Do not force a controller, camera or character pose.
It shares the existing eight-second hard-control recovery and boss immunity.

Duelist recognition is two deliberate open-offhand taps at the upper
sternum while a compatible weapon remains held forward, both triggers released
and the offhand grip released. Brawler Taunt requires a clenched offhand grip,
so the two gestures have distinct input gates.
Require a clear separation between taps, a short recognition window, departure
before rearming, and a visible eligible enemy in weapon range and aim at completion. Bind that
enemy for the buff's full duration; changing target cannot transfer protection.
This is a seated-compatible, mirrored candidate requiring overlap/ergonomic
validation against existing inventory and medical gestures. Protection takes
the strongest applicable value with Rally and similar direct-damage buffs;
it adds no healing, DoT protection or extra defense against other attackers.

Fast Blast uses the existing two-trigger ultimate chord and one equipped
ultimate choice. The same recovery survives weapon swaps and reconnects;
training another profession does not create a second simultaneous ultimate
slot. Its 3D burst is below Rifleman's 6D Sniper Shot and retains normal defenses.

Recommended pistol VATS choices are Eye Shot, the shared Torso/Bleeding Shot,
Marksman Warning Shot and Marksman Suppression Fire. Carbine choices are
Confusion Shot, Controlled Burst, Warning Shot and Suppression Fire; Underhand
is outside these four slots. BH lightning uses only compatible generic ranged
options and its own normal discharge. Mixed builds may replace slots with
other learned attacks. Pistoleer Fan Shot remains available through additional
Pistoleer training and its original fanning gesture.

### Equipment, retired commands and passive budget

The scatter pistol retains pistol mobility and fires eight physical pellets:
one central ray and seven rays on a four-degree half-angle ring, at 160 m/s.
The spread can catch a moving target that the centre ray misses. One shot has
one receipt and one primary victim; each contacting pellet contributes one
eighth of the ordinary shot's damage budget. Eight contacts do not produce
eight full hits. Original weapon damage remains unchanged; misses lower the
damage rather than being compensated with inflated pellet damage. Trained
Pistoleer Fan Shot remains the separate, explicitly learned area attack.

`rifle_lightning` is BH's Electricity/AP1 weapon, separate from Commando's
`heavy_lightning_beam`. It launches a 160 m/s bolt with limited tracking:
five-degree acquisition, at most 20 degrees of turn per second and eight
degrees of total turn. The accepted target is fixed for that shot. Physical
world collision, range and native line of sight still apply; fast targets can
escape. Its original 64 m equipment ceiling and rifle movement/support rules
remain. Historical command-specific 16 m lightning attacks do not define the
weapon's normal range. Its damage is normalized separately from Commando.

| Original grant or behavior | Disposition |
| --- | --- |
| Spray Shot, including stacked Blind/Stun/Dizzy | Retire completely from BH combat; no replacement area action. |
| Lightning Cone I / II | Retire; no chain, splash or cone damage. |
| Lightning Single I / II | Fold into proficiency for the normalized single-target lightning discharge; no duplicate VATS buttons. |
| Bleeding Shot / Torso Shot | One shared ranked bleed entry; retire the legacy Torso fire DoT and separate pool targeting. |
| Underhand Shot / Knockdown Fire | One ranked gesture attack; no independently alternating knockdowns. |
| Fast Blast multi-pool attack and +95 accuracy | Replace with the single Health ultimate above. |
| Raw pistol/carbine accuracy and lightning accuracy | No physical aim widening or auto-hit; replace with bounded learned BH status application where relevant. |
| Ranged mitigation I / II / III | Retire the BH-specific grant contribution when Duelist is introduced; preserve grants from other trained professions. Native tiers narrow random damage spread, not flat 20/40/60% damage reduction. |
| Droid Find / Track and equipment certifications | Keep as functional investigation/equipment progression. |

Original mastered BH adds +50 pistol and carbine speed and +60 lightning speed.
Master Marksman already supplies +30 pistol/carbine speed. Those sums would make
BH alone faster than the dedicated trees and multiply the value of a combined
build. BH advanced speed is capped at +25, with the strongest compatible
advanced-profession contribution selected instead of summed; the Marksman
baseline remains separate. Apply the same no-stacking rule to lightning
proficiency. Do not change another profession's weapon cadence globally.

For the source scatter pistol's 3 s base period, BH's total 55 speed
gives 1.35 s, versus the current Master Pistoleer one-second floor. For the
source DH17 carbine's 3.5 s base, it gives 1.575 s versus Master Carbineer's
1.225 s. These are 74.1% and 77.8% of their respective basic-fire rates before
abilities, quality, reloads and movement. They are not whole-kit DPS results.

Cap learned BH status application at 85 base plus 10 training, or 95 before
resistance. At 100 resistance that is 57% application versus Combat Medic's
75% at its 125 raw maximum; at 125 resistance they become about 51.8% and 68.2%.
Durations also retain existing resistance rules, including integer rounding:
a two-second knockdown remains two seconds at 100/125 resistance, although its
application chance falls. Keep current bounded derived
BH status resistance; add no blanket immunity or resistance multiplier.
Duelist's ideal sustained protection against its one opponent averages only
2% (15% × 8/60); protection against other opponents is zero. The compiled
production-policy calculation and original source hashes are recorded by
`tools/server/audit_bounty_proposal.py` in
`runtime/evidence/bounty/proposal-balance.json`.

The compiled 120/300-second benchmark uses quality 0/0.5/1, actual magazine and
reload values, 1000 Action/Mind and 10/8 regeneration. Lightning normalization
uses `q = clamp((mean damage - 434) / 136, 0, 1)` and
`(416 + 184q) × (0.8 + 0.2 × support progression)`, with progression bounded
to 0–1. Crafted lightning reaches 65.3–75.0% of matched Rifleman output without
armor, 65.1–74.8% against 50% body resistance, and 59.0–67.9% when 50%
electricity resistance is added. Original stock defaults are separate from
crafted endpoints: stock lightning reaches 62.1–68.7% of stock T21 Rifleman.

Pistoleer/BH and Carbineer/BH builds on the same legally usable DL44/DH17 reach
99.5–102.9% of their pure specialist references. That is within the intended
10–15% maximum increase. The scatter pistol retains its much weaker original
damage budget: even all eight stock pellets yield only about 26–28% of stock
Rifleman's modeled damage, falling with partial contacts. Its moving-target
assistance and short-range utility do not establish standalone bounty viability.

Evidence is `runtime/evidence/bounty-combat/balance.json`, produced by
`tools/server/audit_bounty_combat_balance.py`. These are authored loadouts with
neutral range scaling and ideal contacts, not optimal rotations or encounters.
One existing inconsistency remains: generic Marksman Lethal Shot uses normal
weapon recovery despite the original command's 2x speed multiplier; Rifleman
Head Shot explicitly uses 2x recovery. The benchmark models that actual behavior.
Ordinary mark encounters must
also verify solo completion with supplies; difficult marks should reward a
second combat tree or party. Existing bounty target selection has not yet been
retuned to establish that outcome.

Native policy/grant routing, cooldown and stacking rules, compatible VATS,
gestures and weapon descriptors are implemented. Original scatter and lightning
meshes, textures, muzzle hardpoints, effects and sounds are prepared without
substitute proprietary assets. Policy arithmetic and dummy-renderer client
fixtures are separate from a linked server build or real bounty completion.
The latest full build is blocked by the session's read-only Podman runtime;
network restrictions also prevent native HTTP checks and VPS provisioning.
The earlier linked binary does not validate these new native changes.
