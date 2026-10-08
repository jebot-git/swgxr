# Penetration alternatives for the armour rebalance

Study date: 7 October 2026. This evaluates the user's proposed replacements for
Core3 penetration against the [armour design](ARMOUR_REBALANCE_RESEARCH.md).
Doctor and buff changes are deferred to the following balance pass. This study
preceded the authorized [source implementation](ARMOUR_IMPLEMENTATION.md).
All numbers below are illustrative tuning candidates and
analytical calculations, not measured live combat results.

The working armour proposal gives ordinary reference equipment 1.25×, 1.50×
and 1.75× effective health, with an armour-only upper envelope of 2×, equivalent
to 50% reduction. Unarmoured play must remain viable. Penetration should add
weapon specialization without making a penetration grade necessary to damage
an armour tier.

## What the current implementation provides

The native weapon model stores an AP grade, one damage type, and a crafted
wound-chance statistic separately. The public upstream definition confirms
these are distinct fields; local patched source is the implementation baseline.
([Core3 WeaponObject definition](https://github.com/swgemu/Core3/blob/unstable/MMOCoreORB/src/server/zone/objects/tangible/weapon/WeaponObject.idl))

In the local checkout:

- `CombatManager::getArmorPiercing` applies the old exponential AP/AR rule.
  Player armour, PSG, NPC, vehicle and turret paths use it separately.
- `getArmorReduction` selects one weapon damage type. Mixed base/elemental
  damage needs a new representation and native calculation, not just a renamed
  attribute. The adapter also exports a single `core3.damageType` today.
- `woundCreatureTarget` rolls against `getWoundsRatio()` and selects an eligible
  damaged HAM pool. It adds one wound to that pool and one to each of its two
  secondary stats. The function does not use penetrating damage to scale wound
  amount. Its caller excludes dead/incapacitated targets.
- No general weapon critical-hit chance or critical-damage multiplier was found
  in the inspected ground-combat damage and weapon paths. That alternative
  requires a new mechanic, not remapping an existing critical field.
- `SwgxrLiveCombat.h` ultimately invokes the native combat command on validated
  impact. Client `weapon_state.gd::damage_at` is a separate local calculation;
  changing it alone would not change authoritative damage.

Source locations: `vendor/Core3/MMOCoreORB/src/server/zone/managers/combat/CombatManager.cpp`
(`woundCreatureTarget`, `getArmorReduction`, `getArmorPiercing`), native
`objects/tangible/weapon/WeaponObjectImplementation.cpp` (`getWoundsRatio`),
`objects/creature/commands/SwgxrLiveCombat.h`, and
[weapon_protocol.py](../server/weapon_protocol.py).

The 29 currently supported weapon template defaults include AP grades across
energy, kinetic, blast and electricity. Examples are E11 carbine (Light/energy),
E11 rifle (Medium/energy), T21 (Heavy/energy), vibroblade (Light/kinetic), cleaver
(Medium/kinetic) and vibrolance (Light/electricity). These are template defaults,
not an audit of owned crafted items. AP alone cannot determine a sensible element.

## Option comparison

| Replacement | Viability | Main consequence |
| --- | --- | --- |
| Convert part of base damage to an element | Strong for weapon identity | Advantage depends on resistance profile; does not inherently increase total damage |
| Small armour-dependent mitigation bypass | Strong as the direct AP replacement | Predictable anti-armour value, zero unarmoured bonus, no grade cliff |
| Direct damage multiplier by armour class | Viable with restrictions | Can accidentally make armour amplify damage or exceed its survival budget |
| Critical chance or critical damage | Viable as a separate weapon feature | Adds burst variance and usually benefits attacks on unarmoured targets too |
| Wound chance | Technically straightforward, weak as the main replacement | Changes persistent attrition and rewards attack frequency |
| Wound potency | Requires new handling; poor first replacement | Changes persistent HAM loss, integer rounding and long-fight balance |

## Elemental conversion

Keep the raw damage budget fixed and allocate a fraction `f` to the selected
element, with the remainder retaining kinetic or energy base damage:

```text
D_after = D × [(1 − f) × (1 − R_base) + f × (1 − R_element)]
```

For a 1,000-damage hit, base resistance 50%, elemental resistance 30%, and
`f = 30%`, damage becomes 560 instead of 500: a 12% increase. Reverse the
resistances and the same split deals 640 instead of 700: an 8.6% decrease.
With equal resistances it changes nothing; with no armour it still deals 1,000.
The gain relative to an unsplit hit is `f × (R_base − R_element) / (1 − R_base)`.

Provided each channel stays within 0–50% resistance, any nonnegative split
whose fractions sum to one also remains within the proposed armour survival
envelope. Elemental damage must not automatically bypass armour or create a
DoT. A 30% conversion means 70% base plus 30% elemental, not 100% plus 30%.

An illustrative AP-to-fraction mapping is None/Light/Medium/Heavy →
0/10/20/30%. Choose the element per weapon family and retain explicit rules for
weapons already using elemental, blast, stun or lightsaber damage. This is a
design choice, not a recoverable historical mapping. Existing elemental weapons
must not have their identity accidentally removed because they have AP None.

This option works best when crafting layers create meaningful elemental
differences. If elemental resistance is always lower than both base channels,
more elemental allocation becomes a universal upgrade rather than a matchup
choice. Conversely, uniform resistance across all channels makes this conversion
unable to compensate for losing old AP strength.

## Armour-dependent multiplier

Prefer multiplying the amount of mitigation that remains effective:

```text
R_effective = R × (1 − p)
D_after = D × [1 − R × (1 − p)]
```

Here `p` is the fraction of mitigation ignored, not percentage points subtracted
from resistance. At `p = 20%`, 50% resistance becomes 40%, not 30%.

| Original armour reduction | Damage from 1,000, no penetration | With 20% bypass | Relative damage gain |
| --- | ---: | ---: | ---: |
| 0% | 1,000 | 1,000 | 0% |
| 20% | 800 | 840 | 5% |
| 33.33% | 666.7 | 733.3 | 10% |
| 42.86% | 571.4 | 657.1 | 15% |
| 50% | 500 | 600 | 20% |

At the last row, armour still gives 1.67× effective health. For `R ≤ 0.5`, the
relative damage gain `R × p / (1 − R)` is at most `p`. This provides a clear
budget for penetration while retaining value in every armour tier. A candidate
grade mapping is None/Light/Medium/Heavy → 0/5/10/20% mitigation ignored.
Weapon base damage, rate and recovery must pay for that extra value; high AP
must not simply be a free upgrade on an otherwise identical weapon.

Armour-class dependence is feasible through `p[weapon_profile, armour_class]`.
For example, a specialized weapon could ignore 10%, 15% and 20% against Recon,
Battle and Assault respectively. That is an optional matchup table, not a claim
that Assault is a higher protection tier. Start with class-neutral values and
add such differences only where kinetic/energy biases do not already provide
the intended distinction. Otherwise one class can be disadvantaged twice.

A direct damage multiplier `m` instead gives `D × (1 − R) × m`. It is less
robust: `m < 1` on 50% armour can exceed the proposed 2× survival envelope,
while a large `m > 1` on weak armour can deal more than the unarmoured hit.
Bound its result between the ordinary mitigated hit and the unarmoured hit if
used. Mitigation bypass enforces those bounds naturally for `0 ≤ p ≤ 1`.

## Critical chance and potency

For critical probability `c` and critical damage multiplier `k`, expected damage
relative to an ordinary hit is `1 + c × (k − 1)`, assuming the same resistance
and no additional critical-only effects. A 10% chance of 1.5× damage adds 5%
average damage; reaching 20% from zero chance at that potency requires 40%
critical chance. Equal average damage does not mean equal short-fight outcomes:
crits increase burst and overkill variance.

Unconditional crits benefit attacks on unarmoured targets as well. They can
replace AP as a weapon damage-budget feature, but lose its anti-armour role.
Making crit chance depend on armour restores that role with less predictable
outcomes than deterministic bypass. If penetration instead changes critical
potency, weapons with no critical chance receive no benefit unless a baseline
crit system is also introduced.

Keep critical damage armour-mitigated; do not make a critical hit an automatic
armour bypass. In VR, an eventual verified weak-point mechanic could tie critical
hits to aim, but neither random crits nor a headshot system currently follows
automatically from the armour conversion. The native server must own the roll
or weak-point validation and preserve it across retries and split damage.

## Wound chance and potency

Wounds are persistent loss of usable HAM, not ordinary hit damage. In the
current function a proc also wounds the two associated secondary stats.
Increasing this mechanic affects combat attrition and recovery needs beyond
the immediate armour interaction. This study leaves treatment and buffs alone.

For `h` connected eligible hits per minute, wound probability `c_w` and amount
`w` per affected pool, expected wound accumulation is approximately
`h × c_w × w` before clamping and native integer-roll details. At 10% and one
wound, 60 hits give six expected wounds per minute while 300 give thirty in
each affected stat, assuming the same pool is selected throughout. Thus simply
adding a chance bonus favours high-rate weapons and multi-hit abilities.

A multiplier also rewards already high crafted `woundsRatio`: ×1.2 changes
10% to 12% but 30% to 36%; zero stays zero. Preserve that existing crafting
stat as an independent input. For potency, native `addWounds` takes integers:
multiplying one wound by 1.2 cannot deliver a stable 20% gain through naive
rounding. An accumulator or probabilistic extra wound would be new persistent
or random behavior, and must preserve caps on usable HAM.

If explored later, budget wounds per damage delivered or over time, rather than
per projectile alone; trigger at most once per original attack/target after
positive delivered damage, not once for each damage channel. Distinguish wound
amount from DoT potency: the latter already means something else in Core3.
Wound penetration can differentiate an attrition weapon, but it cannot be
assumed equivalent to a direct-damage AP bonus across short PvE fights, long PvP
fights and targets with different persistence behavior.

## Recommendation and verification

Use bounded mitigation bypass as the first candidate for converting legacy AP.
Use elemental splits to preserve weapon identity and resistance matchups during
damage-type streamlining. Evaluate a pure elemental replacement alongside it
if removing penetration as a distinct stat is preferred. Do not grant full
elemental, bypass, critical and wound rewards together for the same old AP grade;
they must share the weapon's balance budget. Keep existing crafted wound chance
separate for this armour pass.

Implementation needs one server-authoritative damage breakdown, mirrored for
client presentation. Apply the old AP/AR rule zero times in converted paths.
Preserve one hit-location decision, one wound/state application and one set of
damage/condition/XP side effects for the original hit; splitting channels must
not multiply them. Existing projectiles need stable launch profiles, and all
unconverted NPC, vehicle, turret, PSG and exceptional weapon paths need explicit
routing. Do not temporarily mutate a shared weapon's damage type to calculate
its different portions.

The arithmetic above was checked locally, including 1,071 combinations of
0–50% resistance and 0–20% bypass. These stayed between half and all incoming
damage and within a 20% penetration damage gain. This is analytical verification,
not a native combat, balance, GPU or headset test. Native evaluation should
compare every AP grade across bare targets, each class/tier, mixed and broken
equipment, class-favoured channels, layered armour, rate extremes and repeated
impacts. Compare sustained damage including recharge/recovery, burst outcomes
and wounds per damage delivered. Doctor/buff balancing remains deferred.
