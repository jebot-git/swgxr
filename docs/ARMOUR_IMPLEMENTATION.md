# Armour and weapon conversion v1

Implemented in source on 7 October 2026, following the
[penetration recommendation](ARMOUR_PENETRATION_OPTIONS.md). This document
describes the implemented rules rather than historical CU behavior. The full
linked Core3 build, live item migration and encounter balance remain unverified:
Podman cannot access its runtime configuration in this execution environment.
The running local/VPS server has not been updated by this change. No VR test ran.

## Protection and crafting

`server/combat/ArmourModel.h` is the shared native arithmetic. The profile
installer audits 186 armour templates and writes an ignored generated reference
header and `runtime/evidence/armour-reference-audit.json`. Classes are explicitly
assigned in `server/combat/armour_balance.json`. Original Light/Medium/Heavy
ratings no longer multiply damage.

Ordinary crafted base quality is normalized against the piece's source range
plus required component-slot contributions. Component quantity consumed does
not multiply statistics. Override-combined experimental properties do not
inherit component values. Optional enhancements and channel layers do not
inflate the normalization denominator: they retain bounded excess or channel
credit. No original assets or player database files are added to source control.

Normalized quality maps to 1,000–6,000 base score, independently of appearance.
Exceptional base values above the ordinary maximum receive 40 points per source
unit, up to 7,000 base score. Special-protection quality can adjust its channel
by up to 1,000 points relative to base quality. Layer values contribute 40 points
per original unit, bounded to ±1,500 per channel. These are explicit initial
tuning choices, not recovered CU constants.

Battle is balanced. Recon adds 1,000 Energy and subtracts 1,000 Kinetic; Assault
does the reverse. Heat, Cold, Acid and Electricity start from the common base.
Legacy and new protection slices multiply the completed score once each, with
an 8,000-point final ceiling. Raw native statistics and slice records remain
unchanged, so existing items, crafting previews and factory output use the same
derived calculation without a destructive item migration.

Eighty-six templates have no explicit experimental ranges. They are reported
as template fallbacks, with an ordinary source interval of 0–80. For items with
no crafted base value, the larger raw Kinetic/Energy channel supplies fallback
quality and is not counted again as a layer. This preserves a bounded distinction
between such items but is not a reconstruction of missing crafting provenance.

```text
effective-health multiplier = 1 + clamp(score, 0, 8000) / 8000
damage reduction = 1 − 1 / effective-health multiplier
```

Thus 2,000/4,000/6,000 scores give 1.25×/1.50×/1.75× effective health, with a
2× maximum. Basic/Standard/Advanced labels describe quality bands; this pass
does not add new CU core schematics or make an appearance determine the tier.
Condition still reduces protection and broken pieces provide none. Examine
shows class, scores, condition-adjusted reduction and equipment penalties.

Existing regional coverage remains: one eligible piece is selected for each
hit location. Penalties use the largest equipped penalty in each category, so
additional pieces do not accumulate hindrance. Armour wear is now 2% of the
damage arriving at that layer when it mitigates a hit, rather than 20% of damage
that penetrated it. This avoids multiplying repair wear merely by lowering
resistance. Native integer wear rounding still applies.

## Penetration and damage profiles

Legacy AP grades None/Light/Medium/Heavy supply maximum favorable-matchup
budgets of 0/5/10/20%. Kinetic and Energy weapons with AP allocate half that
budget, up to 10% of damage, to Electricity or Heat respectively. Half the grade
budget also becomes mitigation bypass. This gives actual bypass values of
0/2.5/5/10% for those profiles; the grade budget is not itself the bypass value.

Existing Heat/Electricity weapons become 80% Energy plus 20% of their element;
Cold/Acid weapons become 80% Kinetic plus 20% of their element. Blast becomes
Kinetic/Heat, Stun becomes Energy/Electricity, and Lightsaber becomes Energy/Heat,
also at 80/20. Those families retain an elemental identity even at AP None.

An explicit damage-budget scale offsets any excess favorable-matchup benefit:

```text
budget_scale = min(1, (1 + grade_budget) /
                     (1 + elemental_fraction + bypass × (1 − elemental_fraction)))
effective resistance = resistance × (1 − bypass)
```

The scale is applied before splitting damage and is exposed in examine and the
native weapon profile. It can reduce raw damage for formerly pure-element
weapons; this is deliberate compensation, not added damage. Across resistance
profiles bounded to 0–50%, the elemental split and bypass together cannot exceed
the grade's budget relative to the same raw hit using its base channel alone.
This bound does not claim equal overall DPS between different weapon families.

The native pipeline carries both portions through shielding and worn armour.
It rolls location once and retains the original wound/state/XP paths. No shared
weapon damage type is temporarily changed. Launch records verify damage type
and AP as well as damage range before accepting the impact. Critical mechanics
and crafted wound chance are unchanged.

NPCs, pets, vehicles and turrets retain native resistance inputs, bounded to
50% for this mitigation calculation, and use the same converted weapon profile.
Their original armour rating no longer creates an AP gate. Detonations use the
same conversion. PSG resistance is also bounded to 50%, applied as a separate
layer with its existing vulnerability and wear policy. The 2× ceiling is for
worn armour alone: shield and other defensive effects still stack separately.
Doctor, buff and shield-stacking balance remain for subsequent work.

## Equipment penalties and persistence

At 6,000 base score, before encumbrance-quality or mastery mitigation:

| Class | Movement | RoF / Power | Capacity recharge / Stance recovery |
| --- | ---: | ---: | ---: |
| Recon | −6% | −18% | −12% |
| Battle | −12% | −12% | −12% |
| Assault | −18% | −6% | −12% |

Penalties scale with base score up to that reference. Good encumbrance crafting
reduces them by up to 25%; an applicable elite mastery halves the remainder.
Existing equipment certifications remain. This initial mastery mapping is
explicit in `SwgxrArmour.h`, not an inferred historical certification table.
Broken pieces and pieces without a hit location add no hindrance.

Converted armour no longer applies secondary-HAM encumbrance. Equip/unequip
reconciles obsolete deductions against any remaining legacy equipment without
invoking general buff repair. The existing login HAM repair also rebuilds the
remaining encumbrance totals. No doctor/buff strength or duration is changed.

Native movement modifiers feed existing server speed validation and the client
locomotion profile. Tracked head/hand poses are unaffected. Native ranged cadence
includes the output penalty; melee cadence includes recovery. Native weapon
attributes expose reduced Power/recovery/RoF and the captured armour factors.
The client uses current owner snapshots to update equipment and unarmed
penalties without applying captured factors twice. Recharge preserves the
remaining fraction when penalties change. Capacity/reload and physical swing
qualification retain the existing client simulation boundaries; this does not
add new native ammunition accounting or remote hand-tracking validation.

## Validation and remaining runtime work

Verified locally:

- The complete source patch stack applies, including
  `server/patches/0069-armour-weapon-conversion.patch`.
- Engine3 IDL generation accepts the new derived armour methods.
- Actual edited Core3 translation units pass C++ syntax checks using the
  available local build headers, including the live command registration path.
- The compiled C++ model checks score endpoints, quality equivalence,
  special-component credit, class biases, slices and penalty mitigation.
- Godot agrees with C++ on 1,296 channel/grade/resistance cases. New equipment
  checks cover recharge, RoF and avoiding duplicate penalties.
- Adapter tests cover recipe bounds, override semantics, native profile
  decoding, old-server rejection and nonfinite input rejection.
- Headless ranged, melee, crafting, profession, gameplay bridge, spice
  integration and source locomotion regressions pass. The ranged fixture now
  supplies explicit controller nodes and uses activation anchors instead of
  the separate visual holster sockets. OpenXR remains off in every test.

Reproduce the model and client differential check:

```sh
python3 tools/combat/install_armour_profile.py
clang++ -std=c++14 -Wall -Wextra -Werror tests/armour_model.cpp -o /tmp/swgxr-armour-model
/tmp/swgxr-armour-model > runtime/evidence/armour-model-cases.json
godot --headless --xr-mode off --path client --script res://tests/armour_conversion_smoke.gd
python3 -m unittest tests.test_armour_conversion tests.test_weapon_protocol tests.test_unarmed_protocol
```

Before deployment, complete a linked native build and disposable real-item
checks for crafting, slicing, factory output, equip/unequip, relogging with old
encumbrance, mixed/broken equipment, shield layering and actual hit/condition
accounting. Measure unarmoured versus ordinary and exceptional equipment in
matched encounters. Arithmetic and syntax checks do not establish encounter
balance or native persistence behavior. The live realm remains Tatooine-only.
