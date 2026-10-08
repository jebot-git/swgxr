# CU armour statistics compared with Core3

Research baseline: 7 October 2026. CU means the 2005 Combat Upgrade period before
the NGE. The implementation baseline is this project's patched Core3 checkout,
whose upstream revision is `403893d9b9f8e6fa712fbb3cb1fcd8f0fe45bb79`
([pin](../server/upstream.json)). This records the original design study.
The subsequently authorized source implementation and its validation limits are
described in [Armour and weapon conversion v1](ARMOUR_IMPLEMENTATION.md).

CU changed the structure of armour balance. It replaced the emphasis on very
high percentage resistance with protection scores, differentiated armour
classes, and profession training that compensated for equipment penalties.
For SWGXR, changing protection alone would leave important pre-CU interactions
in place: armour piercing, body-region coverage, secondary-stat encumbrance,
shield stacking, crafting and slicing.

## Established CU design

Developer Thomas Blair's retrospective describes three armour classes
(Reconnaissance, Battle and Assault), three protection tiers (Basic, Standard
and Advanced), and penalties to movement, accuracy and firing rate. Profession
skill boxes mitigated those penalties, with mastery intended to accommodate
Advanced armour. These are distinct concepts: an Assault class is not the
same thing as an Advanced tier, or Core3's Heavy armour rating.
([Developer portfolio, armour reclassification slide](https://www.slideshare.net/slideshow/thomas-blair-implementation-portfolio-2001-2024/274261732))

The reproduced SOE CU overview gives Recon an energy advantage and kinetic
disadvantage, Battle balanced protection, and Assault the opposite bias to
Recon. It describes kinetic/energy weapon base damage with additional heat,
cold, acid or electrical damage. Layers could trade protection between opposing
elements. Certifications controlled equipment access. This is a wider combat
model than converting nine independent Core3 resistance percentages into larger
numbers. ([SOE Combat Upgrade Overview 2, preserved transcript](https://forums.mmorpg.com/discussion/184762/astromechs-friday-features-other-stuff-2003-2005/p5))

CU also made faction armour part of the crafting economy: faction schematics
gave armorsmiths access to useful appearances across the three classes.
([SOE faction armour feature, preserved transcript](https://forums.mmorpg.com/discussion/184762/astromechs-friday-features-other-stuff-2003-2005/p3))

The early design document describes making the core determine statistics and
the final assembly determine appearance. It also proposes applying the largest
relevant hindrance rather than adding a penalty for every piece. This document
is explicitly a draft and includes rules that differ from later accounts;
its exact penalty table and certification list must not be treated as the
shipped specification. Its useful design principle is that wearing fewer pieces
should not produce the old armour-coverage advantage.
([Early CU design transcript](https://forums.mmorpg.com/discussion/73458/the-first-draft-of-the-cu-for-posterity-and-giggles))

## Reported CU protection values

A surviving period player guide reports unlayered base ceilings of 2,000, 4,000
and 6,000 for Basic, Standard and Advanced, with a 1,000-point kinetic/energy
class bias. Its Advanced examples are:

| Class | Kinetic | Energy | Elemental baseline |
| --- | ---: | ---: | ---: |
| Recon | 5,000 | 7,000 | 6,000 |
| Battle | 6,000 | 6,000 | 6,000 |
| Assault | 7,000 | 5,000 | 6,000 |

These are historical reference values, not guaranteed values for every crafted
item. Layers and crafting quality matter. The same guide reports 2,000 → 20%,
4,000 → 36%, 6,000 → 48%, 8,000 → 56% and 10,000 → 60% damage reduction.
This table and its claimed cap are provisional: no original CU server formula
was verified. In particular, **6,000 protection is not 60% resistance**.
([Period CU guide](https://blades.dk/cu/))

Do not substitute modern NGE mathematics. The current general armour wiki
explicitly attributes its different conversion table to NGE code; that is a
reason to exclude it as CU formula evidence.
([Wiki's stated formula provenance](https://swg.fandom.com/wiki/Armor))

Likewise, the removal of certifications and hindrances belongs to Publish 28
on 26 April 2006. It does not describe 2005 CU armour.
([SOE Publish 28 notes, preserved copy](https://swglegends.com/wiki/index.php?title=Publish_28_Notes_for_April_26,_2006))

CU itself changed during its lifetime. Publish 19 on 29 June 2005 replaced
wire-cutting slices with ordered upgrades using a 100-point item budget. Its
armour categories were resilience, deflections, critical-save hardening and
armour-break defence. A CU reproduction therefore needs a specific patch target;
the present project's slicing rewards are not that historical system.
([SOE 2005 publish archive, Publish 19](https://swgreckoning.org/archive/data/20070126114830/content_001.html))

## What this Core3 checkout actually calculates

For one eligible, unbroken armour layer and a non-vulnerable damage type, the
armour stage is approximately:

```text
remaining damage = incoming damage × piercing multiplier × (1 − resistance/100)

AP > AR:  piercing multiplier = 1.25^(AP − AR)
AP ≤ AR:  piercing multiplier = 0.50^(AR − AP)
```

Here AR is the small None/Light/Medium/Heavy category, not a CU protection score.
Resistance is selected by damage type and returned as an integer. This formula
isolates armour; it is not the complete hit calculation with abilities, food,
defences, PvP modifiers and rounding.

For 1,000 damage entering this stage against 80% resistance:

| Piercing relative to armour | Remaining damage |
| --- | ---: |
| AP one grade below AR | 100 |
| Equal grades | 200 |
| AP one grade above AR | 250 |

A vulnerable type bypasses that armour layer, including its piercing adjustment.
Broken armour is vulnerable. An absent player armour piece does not itself
apply the AP multiplier. These details prevent a universal multiplier from
being applied indiscriminately to naked targets.

Source: `CombatManager.cpp`, `getArmorObjectReduction` (line 2343),
`getArmorReduction` (2453), and `getArmorPiercing` (2658);
`ArmorObjectImplementation.cpp`, `isVulnerable` (286).

Protection calculation normally caps non-vulnerable channels at 80%; the legacy
effectiveness slice permits 90% on its applicable branch. The project's newer
`protection_pct` slice is another multiplier on eligible positive channels,
rounded and capped at 90%. It preserves vulnerability. For example, 75%
protection multiplied by 1.20 becomes 90%, reducing remaining damage from 25%
to 10%: a 60% reduction in damage taken for that slice. At equal AP/AR,
80% and 90% resistance give armour-only effective-health multipliers of 5 and
10. Small percentage increases near the cap have very large survival effects.

Sources: `ArmorObjectImplementation.cpp`, `getTypeValue` (290);
[project slicing patch](../server/patches/0064-smuggler-slicing-stats.patch);
[reward generation](../server/slicing/SwgxrSlicing.h).

### Coverage and condition

Core3 selects a body region according to the damaged HAM pool. Health hits select
chest half the time and either arm a quarter each; Action selects a leg; Mind
selects the head. It then selects one eligible equipped piece at that location.
Arm slots have left/right filtering with a fallback to the available arm list;
legs share a regional list. Protection is not the sum or average of the entire
suit. Consequently, a full suit need not increase protection over a smaller set
that already covers the relevant regions, while each piece still adds
encumbrance. Exact CU slot weights and hit distribution remain unverified here.

A PSG is processed before worn armour, so eligible layers reduce the remaining
damage sequentially. Each applies its own piercing/resistance rules. Condition
damage is then inflicted at 20% of the damage surviving that layer. Reducing
resistance from 90% to 50%, with other inputs fixed, therefore increases both
that layer's surviving damage and its condition-damage input fivefold. Durability
must be considered with mitigation, rather than retuned independently.

Sources: `CombatManager.cpp`, `applyDamage` (1428), PSG and armour sections
(2554–2605); `WearablesDeltaVector.h`, `getArmorAtHitLocation` (164).

### Encumbrance and other defences

Health encumbrance reduces Strength and Constitution; Action reduces Quickness
and Stamina; Mind reduces Focus and Willpower. It does not directly subtract
those amounts from the three primary HAM maxima. Equipment checks reject armour
that would exhaust one of those secondary stats. Each piece contributes.

Core3's separately named melee/ranged damage mitigation is also not CU armour
penalty mitigation: it narrows the attack's damage roll, leaving the minimum
unchanged and reducing the min-to-max spread by 20% per mitigation rank.
Conflating these two meanings would change combat twice.

Sources: `PlayerManagerImplementation.cpp`, `checkEncumbrancies` (2346) and
`applyEncumbrancies` (2420); `ArmorObject.idl`, encumbrance getters (211 onward);
`CombatManager.cpp`, damage-range mitigation (1286–1313).

### Crafting and presentation

Core3's crafting update derives protection, special channels, encumbrance and
condition from experimental properties and components. The template default
numbers are not representative crafted results: the composite chest template
explicitly labels its defaults as Blue Frog stats. A comparison based only on
that template's 75% resistance would misdescribe crafted armour.

Sources: `ArmorObjectImplementation.cpp`, `updateCraftingValues` and
`calculateSpecialProtection` (346 and 417); `armor_composite_chest_plate.lua`
(97 onward). The inventory adapter forwards native attribute text, while
`fillAttributeList` currently labels protection as percentages. A future score
system must update those attributes alongside combat and crafting.

The Core3 files above are under `vendor/Core3/MMOCoreORB/src/server/zone/`:
combat in `managers/combat/`, player management in `managers/player/`, armour
in `objects/tangible/wearables/`, and coverage in `objects/creature/variables/`.
The composite template is under
`vendor/Core3/MMOCoreORB/bin/scripts/object/tangible/wearables/armor/composite/`.
The [pinned upstream tree](https://github.com/swgemu/Core3/tree/403893d9b9f8e6fa712fbb3cb1fcd8f0fe45bb79)
documents the baseline; project patches must also be included in the comparison.

## SWGXR adaptation and base-value conversion

The user's direction on 7 October is to adapt CU armour to existing SWGXR
combat: movement hindrance affects locomotion, firing-rate hindrance maps to
ranged RoF and melee Power, and accuracy hindrance maps to Capacity recharge
rate and Stance recovery. Damage profiles can become kinetic/energy with
elemental components, with weapon streamlining taking over the balancing role
of the old penetration distinctions. The immediate priority is converting base
values. These mappings establish the design direction; numerical penalties
have not yet been selected or implemented.

### Primary balance requirement: optional survivability investment

The user's further direction is that armour should multiply survivability
without becoming a requirement for competitive play. Ordinary encounters must
be balanced around an unarmoured, unbuffed player of the appropriate progression
and skill. Armour buys additional tolerance for incoming hits, with the agreed
movement and combat penalties providing a meaningful reason to choose lighter
equipment or no armour. Sliced armour and doctor buffs must not become the
assumed baseline for encounter damage or player effectiveness.

Follow-up scope: doctor and buff changes belong to the subsequent balance pass.
Their interactions below are recorded for that pass, not prerequisites for
exploring armour. The [penetration alternatives study](ARMOUR_PENETRATION_OPTIONS.md)
compares elemental conversion, armour-dependent multipliers, critical hits and
wound chance/potency against the proposed survival envelope.

For a fixed health pool, one damage channel and no healing or other defences:

```text
armour survivability multiplier M = 1 / (1 − damage_reduction)
damage_reduction = 1 − 1/M
```

This is effective health against incoming damage, not a guarantee of encounter
survival time. Current 80% and 90% resistance correspond to 5× and 10× effective
health respectively. Moving between them doubles survivability. A health buff
that multiplies the usable health pool by B compounds this to B × M; healing
and shields can widen the advantage further. Lowering armour's ceiling alone
does not establish an unbuffed baseline if enemy damage remains tuned for the
old combination.

For the first balance model, **propose**, rather than treat as approved values:

| Equipment reference | Armour-only effective health | Damage reduction |
| --- | ---: | ---: |
| Unarmoured | 1.00× | 0% |
| Basic reference | 1.25× | 20% |
| Standard reference | 1.50× | 33.33% |
| Advanced reference | 1.75× | 42.86% |
| Upper envelope including armour layers and slices | 2.00× | 50% |

These are SWGXR tuning proposals, not historical CU values. The upper envelope
applies to the resulting armour profile per damage channel, including class
bias, so favoured channels cannot evade it. Quality and specialization should
distribute gains below that envelope; tune upgrade sizes to avoid making a hard
cap erase their value. Shield and buff stacking require a separate combined
survival budget, not an assumption that the armour-only ceiling bounds them.

Choose this survival budget first, then fit the score curve and quality ranges
to it. CU's familiar score units and class profiles can be retained without
adopting its reported mitigation curve unchanged. In particular, the earlier
6,000-score historical anchor and illustrative 3,000–6,000 quality band below
are comparison inputs, not requirements that override this balance goal.

Validate unarmoured/unbuffed, ordinary crafted, and best sliced/buffed loadouts
at matched progression against the same encounters and player opponents.
Measure damage tolerance, effective outgoing damage, recovery and healing
sustain. An unarmoured player should retain a viable way to compete through
mobility and combat output, rather than merely surviving a trivial encounter.
Test healer support as well: mitigation can push incoming damage below healing
output and create indefinite sustain even when the armour-only multiplier is
bounded. Reference encounter damage must not be raised to cancel the benefit
of the strongest loadout for everyone else.

There are already useful integration points: `WeaponCraftingProfile.h` derives
RoF, Capacity, Power and Stance recovery from native crafted weapon statistics.
`server/profession_protocol.py` emits `capacity_recovery_scale` and
`stance_recovery_scale`; `client/combat/weapon_state.gd` uses the former to
divide reload duration and the latter to increase effective recovery, reducing
the required recovery travel. An armour multiplier below one therefore slows
recharge/recovery through these paths. Actual tracked aim remains unaffected.

### Convert quality, then build the new resistance profile

Recommended conversion order:

```text
raw unsliced crafting base → normalized recipe quality → tier base score
    → class bias and converted layers → score-based slice → mitigation curve
```

Do not multiply displayed resistance by a universal constant. For example,
mapping 80% to 6,000 using ×75 would retain the old advantage of recipes with
higher percentage ceilings. It would also confuse special protection, layers,
slices and condition loss with base crafting quality. Native `ArmorObject`
stores `baseProtection`, `specialProtection`, channel values and slice factors
separately; conversion should use those raw fields before getters apply caps,
slices or condition effects.

The inspected chest templates illustrate the different starting ranges:

| Recipe | Piece base effectiveness | Ordinary segment base effectiveness |
| --- | ---: | ---: |
| Bone | 5–20 | 1–5 |
| Chitin | 5–30 | 1–5 |
| Composite | 1–40 | 1–10 |

These are experimental template ranges, **not finished resistance ranges**.
`ResourceLabratory::applyComponentStats` adds each component slot's property
times its contribution to the piece's current value and experimental bounds.
It reads a representative component for the slot, rather than multiplying its
stats by the number of components consumed. Components can themselves contain
upgrades. A conversion table therefore needs the complete recipe contribution
tree, including special protection and exceptional loot components.

For an ordinary recipe with an audited attainable base interval:

```text
q = clamp((raw_base − source_min) / (source_max − source_min), 0, 1)
base_score = target_min[tier] + q × (target_max[tier] − target_min[tier])
```

Use a fixed, versioned source interval for the recipe, not the item's already
shifted experimental bounds. Normalizing against bounds shifted by that item's
own segment would cancel the segment's quality contribution. Handle fixed-stat
items separately when the source interval has zero width. Flag values outside
the interval before clamping so exceptional loot bonuses are preserved through
an explicit bonus rule instead of silently discarded.

The reported CU tier ceilings provide candidate `target_max` values. The
quality floors are a SWGXR tuning choice, not established by those historical
ceilings. For a concrete **illustrative** Advanced band of 3,000–6,000, qualities
0%, 50% and 100% map to 3,000, 4,500 and 6,000. That gives the same base score
to equally normalized recipes assigned to the same tier. Armour appearance
must not silently select the tier; assign class and tier separately in a
conversion profile. Existing Core3 Light/Medium/Heavy ratings cannot supply
that mapping automatically.

Build kinetic/energy class differences from this common base. Convert elemental
layers into bounded score adjustments, retaining their tradeoffs. Do not carry
Core3's special-channel and vulnerability masks into the new profile unchanged:
those encode the old armour identities and can defeat the new class balance.
Keep the raw special-channel data for migration of invested crafting value.

Apply protection slices to scores, rather than to the resulting damage-reduction
percentage. A proposed 20% score slice takes a 6,000 score to 7,200; it must not
be applied again after score-to-mitigation conversion. Preserve legacy slice
factors and the project's newer `protection_pct` reward as separate inputs to
one explicit conversion policy. Version the derived profile so reloads and
factory production cannot repeatedly convert an already converted item.

### Turn the scores into damage, without carrying old penetration twice

For a historical comparison curve in the offline balance model, use piecewise linear interpolation between
the period guide's reported protection anchors, starting at zero protection
for score zero and provisionally capping at its reported upper endpoint. This
is a reproducible SWGXR candidate curve, not a claim to have recovered the
original CU equation. Compare it with a curve fitted to the survivability
budget above; the latter takes priority for SWGXR balance.

At the reported 6,000 anchor, a 1,000-damage hit leaves 520 damage before other
defences. Core3's 80% resistance at equal AP/AR leaves 200. Thus this conversion
changes survival substantially; it is not a display-unit conversion. Preserving
old damage reduction is a different migration goal and would retain the
near-invulnerability this rebalance is intended to reduce.

Weapon streamlining can replace penetration's role in weapon balance, but
changing damage-type names alone does not remove Core3's AP/AR multipliers.
For attacks using the new player-armour model, explicitly neutralize that old
multiplier and tune weapon base damage, rate, recovery and elemental allocation
together. Split a hit into declared damage portions, mitigate each portion by
its matching profile channel, and sum them; do not apply two armour reductions
to the entire hit merely because a weapon has base and elemental damage.
NPCs, pets, vehicles, turrets and PSGs need explicit routing because they share
parts of the old combat implementation.

The next implementation input is a versioned armour conversion table: source
recipe bounds, class, independently assigned tier, target score interval,
layer rules and exceptional-item rules. Native owned-item samples should check
the table against real crafted, looted and sliced items. Keep original raw item
statistics available so adjustments to this table remain reversible. Finished
items do not necessarily retain enough component provenance to reconstruct
every contribution exactly; mark fallback conversions instead of inventing it.

## Remaining rebalance integration

The useful CU goals are more viable armour appearances, controlled survival
scaling, meaningful damage-type tradeoffs and less incentive to minimise the
number of equipped pieces. A CU-inspired rebalance can pursue those goals while
retaining the project's combat systems. A faithful CU conversion also requires
decisions about damage channels, profession restrictions, penalties and their
mitigation, crafting cores, coverage, shielding and the chosen historical patch.

For an initial rebalance, define the following together:

1. **Protection curve and target survival.** Use the unarmoured, unbuffed
   baseline and bounded armour multiplier requirement above. Tune the proposed
   reference multipliers with encounters and competitive loadouts. The period
   score table is a comparison reference, not a binding balance target.
2. **Piercing and damage types.** Decide whether player armour retains AP/AR.
   Keep any change to NPCs, pets, vehicles and turrets explicit; they use separate
   branches of the shared native combat code. Define handling of stun, blast and
   lightsabers before mapping the nine existing channels into CU-like categories.
3. **Coverage.** Choose regional protection, weighted suit protection or another
   specified rule. Include missing pieces, mixed qualities and species slot
   restrictions. Adding a full-suit bonus alone does not remove regional selection.
4. **Crafting and slices.** Preserve useful resource quality and experimentation.
   Reconsider the existing percentage-on-percentage slicing bonus at the same time
   as the base curve. Specify what happens to existing items, components, factory
   schematics and future production; changing template defaults cannot describe
   all those persistent states.
5. **Costs and VR controls.** Use the penalty mappings above. Specify their
   magnitudes, profession mitigation and mixed-suit aggregation, and explicitly
   replace the old secondary-stat deductions so armour is not charged twice.
   Locomotion penalties must never delay or offset tracked head/hand poses.
6. **Durability and layered defences.** Set shield/buff stacking and decay rules
   with the protection curve so the change does not unintentionally multiply
   repair costs or erase profession defence distinctions.

Before implementation, settle the exact target curve, slot rule, untrained/master
penalty policy, and existing-item conversion policy. Historical uncertainty
remains around the precise shipped CU curve/cap, slot weighting, mixed-armour
hindrance aggregation and exceptional shield/Jedi stacking. Modern Restoration
or NGE behaviour cannot resolve those questions by itself.

Validation should exercise real native damage and owned crafted items: all damage
channels and AP grades, covered/missing/broken pieces, mixed suits, PSGs, slices,
crafting extremes, equip/unequip with buffs, persistence and condition loss.
Compare expected damage and time to defeat representative PvE targets before
considering deployment. The existing Tatooine-only live-server scope still applies.
