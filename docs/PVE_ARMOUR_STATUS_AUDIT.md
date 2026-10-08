# PvE, armour and status audit

Research and source inspection: 2026-10-07. This is a recommendation, not a deployed balance change. It examines the current patched Core3 tree and the armour conversion described in [ARMOUR_IMPLEMENTATION.md](ARMOUR_IMPLEMENTATION.md). Doctor and buff redesign remains deferred; live scope remains Tatooine-only.

PvE needs an encounter rebalance, not one global damage multiplier. Direct damage, enemy effective health, control uptime and persistent wounds have changed by different amounts. First close the mitigation and DoT accounting gaps below; otherwise tuning enemy health and damage will compensate for rules that still need to change.

## What CU establishes

SOE's CU overview described Health as the damage/incapacitation pool, Action and Mind as ability resources, and health-only wounds. It proposed character health increasing from 1,000 to 3,000 with combat level. These are the published design targets, not a recovered table of shipped NPC stats. Core3 still damages all three HAM pools and wounds secondary attributes. CU enemy health numbers therefore cannot simply replace Core3 HAM values. [SOE CU overview, preserved copy](https://forums.mmorpg.com/discussion/184762/astromechs-friday-features-other-stuff-2003-2005/p5).

The following shipped changes are documented in SOE's 2005 notes:

- May 5: fixed NPCs failing to use their full special-attack lists; damage and DoTs break paralysis.
- Publish 17: widened creature damage ranges while keeping their average unchanged, explicitly to improve tank mitigation; corrected excessive mission NPC stats; reduced aggro against higher-level players, with faction exceptions.
- Publish 23: AI continues fighting surviving attackers after deathblowing one opponent; Elite/Boss pets revert to normal level statistics.
- Publish 24: NPCs gain more appropriate specials, including Force powers; ordinary baseline damage is adjusted to avoid increasing overall difficulty. Temporary snares cease stacking, with the stronger effect taking precedence; permanent movement modifiers remain separate.

These are useful precedents for damage-range tuning, enemy ranks, counterplay and control limits. They do not establish the exact scheduler, threat weights or per-level health/DPS formula. [SOE publish archive, CU sections before Publish 25](https://swgreckoning.org/archive/data/20070126114830/content_001.html).

In a post-launch interview, producer Julio Torres explicitly retained substantial solo content while emphasizing groups at the high end and acknowledging outstanding balance problems. Ordinary encounters should therefore remain soloable; group bosses need their own budgets. [May 2005 developer interview](https://www.mmorpg.com/interviews/combat-upgrade-qanda-2000113886).

I did not recover an authenticated shipped CU NPC stat table or exact level-difference damage formula. Pre-CU creature databases, later NGE charts and modern Restoration's custom rules cannot supply those missing values. Do not copy a purported CU level multiplier or label the current Core3 level 336 ancient krayt as a CU combat level. Use explicit SWGXR encounter bands instead.

## What the current server actually does

`AiAgentImplementation::setupCombatStats` loads template damage. Primary/secondary weapon setup still multiplies it by `1 - 0.1 × legacyAP`: AP3 weapons retain a 30% discount before the new weapon conversion. That is a leftover balance dependency; remove or replace it only alongside NPC damage tuning, not as an isolated damage increase.

The configured global NPC weapon delay is **2 seconds** in `bin/scripts/managers/creature_manager.lua`, overriding the fallback `3.5 - level/100`. Command speed multipliers, skills, haste and the native floor still modify actual cadence. Template `chanceHit` becomes an accuracy input multiplied by 100; it is not final hit probability.

Rescaled spawns are another distinct path: `setLevel` uses damage floors of `20 + 5 × templateLevel` and twice the resulting minimum for maximum damage, then multiplies by newLevel/templateLevel. HAM scales by the same ratio. This can widen a narrow damage range abruptly. Balance actual spawned statistics as well as Lua defaults.

The default behaviour tree checks queue availability, range and attack validity. Its random selector has two default-attack branches and one special branch; special selection draws uniformly from the equipped weapon's attack list. Other trees, Force weapons and pets can differ. Weapon selection considers range; targeting uses threat/defender lists. A special list is not a tactical rotation with guaranteed gaps between control attacks.

These native queued attacks resolve through `CombatManager`. The inspected player projectile bridge supplies contact evidence before native resolution; that does not demonstrate equivalent swept collision or dodge timing for incoming NPC attacks. Do not budget survival around dodging rendered NPC bolts without verifying that authority path.

### Representative Tatooine encounters

These are current **Core3 template inputs**, not CU statistics or measured runtime DPS. HAM ranges apply to primary pools, not a single combined health bar. Resistances below decode the special-protection marker: 195 means 95%, not 195% mitigation.

| Template | Level | Damage min–max | Primary HAM range | Relevant protection and attacks |
| --- | ---: | ---: | ---: | --- |
| Womp rat | 10 | 90–110 | 810–990 | No K/E protection; intimidation |
| Dune lizard | 18 | 170–180 | 4,100–5,000 | K5/E15/Heat45%; ranged spit and melee, dizzy |
| Tusken raider | 19 | 180–190 | 4,500–5,500 | K/E5%, Heat/Electricity30%; marksman/brawler lists |
| Stormtrooper | 25 | 240–250 | 7,200–8,800 | K/E15%, Blast40%; master carbine specials, thrown weapon |
| Ancient krayt | 336 | 2,270–4,250 | 410,000–501,000 | AR3, most channels95%, Cold65%; 25m area combo/knockdown |

All come from `bin/scripts/mobile/tatooine`, except the stormtrooper in `mobile/faction/imperial`. The krayt adds 100 state accuracy to its specials. Its combo applies stun, blind and intimidate for 10 seconds; its knockdown special also applies dizzy. Reducing its direct damage alone will not address its control pressure.

A static scan found 21 of 304 direct resistance arrays in the Tatooine template directory with at least one of the first seven channels above 50%. This is not a census of enabled live spawns and does not evaluate Lua inheritance.

## Numerical consequences of the conversion

The old AP/AR factor was `1.25^(AP-AR)` above rating and `0.5^(AR-AP)` below it. The new factor depends on bounded resistance bypass and elemental allocation instead.

For 1,000 damage entering armour, isolated from other modifiers:

| Scenario | Before | Current conversion | Consequence |
| --- | ---: | ---: | --- |
| Equal AP/AR, 90% → 50% protection | 100 | 500 | Five times incoming damage; only valid with the tier factor held equal |
| AP0 kinetic vs fresh AR3 / K95 enemy | 6.25 | 500 | 80× initial damage through armour |
| AP3 kinetic vs fresh AR3 / K95 and Electricity95 enemy | 50 | 550 | 11× initial damage through armour |
| AP3 kinetic vs AR0 with K/Electricity0 | 1,953.125 | 1,000 | About half the old damage through armour |

The krayt satisfies the high-resistance examples initially. These are **not kill-time predictions**: miss/block, command modifiers, mitigation skills, HAM distribution, regeneration and resistance decay remain active. The old unarmoured AP advantage disappearing can lengthen ordinary fights while heavily armoured bosses become much easier to damage.

NPC resistance still decays in `getReducedResist`: after accumulated post-armour damage exceeds 25% of total maximum HAM, resistance declines, down to half its original value. The new 50% clamp follows this calculation. A 95% channel stays capped at 50% through most of that decay, reaching approximately 47.5% at its limit, while a 40% channel can fall to 20%. Merely clamping old values flattens both enemy identity and the old wear-down curve.

### Mitigation gaps to resolve first

1. **The cap is per layer.** A 50% shield and 50% body armour leave 25% damage: 4× survivability before other reductions. The body-armour curve alone is capped at 2×. Force, toughness and food mitigation also remain separate and must be visible in the future buff budget.
2. **The penetration advantage proof is for one layer.** With two layers each resisting Energy50/Heat0, AP3 Energy leaves 372.25 of 1,000 versus 250 for a pure Energy AP0 baseline: a 48.9% advantage, above the intended 20% budget. This is an arithmetic counterexample, not a claim that this exact equipped pair has been observed.
3. **NPC profiles need conversion, not just clipping.** Preserve species weaknesses and explicit rank health; replace obsolete AP discounts and choose whether resistance decay still belongs in the model. Do not restore old boss durability by multiplying every boss's health by 11 or 80.

Recommendation: resolve a single combined equipment resistance per channel, capped at 50%, then apply penetration once. Shields can contribute within that budget and later offer finite absorption/recharge utility. That makes the existing one-layer penetration bound applicable to combined equipment. Keep a separate, explicit accounting of non-equipment reductions for the later buff work.

## DoTs in the new system

`CombatManager::applyDots` snapshots strength when the effect is applied. A hit-derived bleed uses `applyDamage`'s result, after armour, block and food; this result excludes spill damage diverted to other pools. Other hit-derived DoTs use `unmitDamage`, captured before armour, the new weapon damage scale and block multiplication. It already includes earlier command/damage modifiers: the name does not mean original weapon base damage.

Ticks normally call `inflictDamage` directly. They do not pass back through `ArmourModel`, do not apply its AP bypass, and do not automatically become Heat/Acid damage because of their names. **An elemental weapon portion does not automatically inflict a status effect.**

| Effect | Current nominal interval | Armour interaction | Other consequences |
| --- | ---: | --- | --- |
| Bleeding | 20s | Hit-derived seed includes armour once; fixed weapon bleeds do not | Normally nonlethal; absorption skill reduces ticks |
| Poison | 10s | Hit-derived seed precedes armour; fixed medicine/weapon strength also bypasses it | Normally nonlethal; can target Action or Mind |
| Fire | 10s | Hit-derived seed precedes armour and converted weapon scale | Wounds plus shock wounds; damage path permits incapacitation |
| Disease | 40s | Bypasses armour | Wounds the selected primary or secondary attribute; shock amplifies wounds |
| Force choke | 5s | Separate Force Shield and saber-capable PSG handling | Does not use ordinary body-armour conversion |

These are scheduled intervals, not guaranteed exact tick counts. Expiration, recovery scheduling and curing affect delivery. Poison/bleed use nonlethal damage calls; current Sweetblossom withdrawal explicitly overrides ordinary nonlethality. Sedative H4B/avoid-incapacitation paths also affect outcomes. Those existing spice rules are not changed by this audit.

`flamesingle2` is a concrete mismatch: its fire tick uses 10% of pre-armour damage, with secondary wound strength 2%. Given 1,000 at that seed point, AP0 Heat converts to 416.67 direct damage against uniform 50% protection, but the fire seed remains 100 per tick rather than 41.67. This excludes HAM spill and other reductions. It escapes the weapon conversion's damage-budget accounting.

`creatureareadisease` is more severe: hit-derived strength, 300-second duration, 25m area, 50% initial application setting and default primary/secondary percentages of 100. The Lua `dotStrength=50` argument does **not** make this a 50-point tick when `dotDamageofHit=true`. Disease/fire shock feedback can push persistent injury toward the old dependency on treatment even with modest direct damage.

Application and stacking also matter:

- Ordinary effect potency uses a separate resistance roll, bounded approximately 5–95%; immunity and NPC `NODOT` flags are separate gates. Armour score is not status resistance.
- Weapon procs use potency per landed attack. In this path poison/disease/fire resistance lookups are commented out; only weapon bleed uses its listed defence. Increasing RoF increases proc opportunities.
- Keys combine type, pool and source. Command effects use command CRC, not attacker identity: multiple attackers using the same command/pool compete rather than automatically stacking. Weapon object IDs can produce separate stacks. Disease is reduced to one source key per attribute.
- A same-key equal/stronger effect replaces and refreshes duration while preserving the pending tick; a weaker one is ignored. Thus rapid attacks tend to maintain uptime rather than multiply same-source tick rate, but weapon swapping and distinct abilities need stack budgets.
- Existing ticks do not continuously resample the attacker's stun/intimidate/armour-output penalties. Those affect new attacks and some new seeds, not an already active DoT.

Recommended rule: every ability has one total damage budget, split into immediate and periodic damage. Derive hit-based DoTs from converted, mitigated damage once; do not mitigate those ticks again. Independently delivered poison/fire should use a declared resistance channel once at application, with any intentional bypass explicit and paid for in its budget. AP changes damage mitigation only, not application chance, critical chance or wound potency.

For routine PvE, replace disease's persistent secondary-HAM wounds with a bounded temporary Capacity-recharge/Stance-recovery debuff. Separate ordinary burning damage from rare wound attacks. Keep persistent wounds for clearly signalled specialist/boss mechanics with accessible counterplay; do not make a doctor prerequisite for normal hunting. This changes harmful-effect design, not doctor/buff values.

## Status effects and physical combat

Armour currently adds no blanket state resistance. Native states are not automatically converted into the proposed Capacity/Power/recovery vocabulary.

| State | Current native rule | Balance implication |
| --- | --- | --- |
| Stun | −20% outgoing damage, −50 melee/ranged defence | Damage debuff, not simply a hard action stun |
| Intimidate | −50% outgoing damage, −20 defence; secondary defence disabled | Strong offensive and defensive pressure together |
| Stun + intimidate | Both subtract from the same pre-state damage: 30% remains | With a 0.82 output factor, sustained output can approach 24.6% before other losses; not 32.8% |
| Blind | −60 attack accuracy and −60 private dodge-attack modifier | Physical contact still invokes native hit rolls; it can still miss without aim movement |
| Dizzy / knockdown | Posture commands can trigger dizzy falls; knocked-down defenders take 1.5× damage | Armour's slowed recovery can worsen exposure; check the tracked-posture path separately |
| Snare / root | Native movement states, independent of armour | Need verified owner replication and movement enforcement, plus a combined slow floor |
| Attack delay / concussion | Damage removes attack delay; custom concussion cleanup exists | DoT ticks can break control; ordering must be tested |

State application checks immunity, exclusion timers, state defence and player-level contribution. It occurs on native HIT results; armour reduction is not the success roll. Some statuses renew duration on reapplication, so a low-damage pack can still maintain oppressive uptime.

For SWGXR, favour a small number of explicit debuffs to output/recovery/movement, with strongest-of-category stacking, short durations and recovery immunity for hard control. Do not apply both an old accuracy penalty and its full recovery substitute. Apply movement penalties to virtual locomotion only; keep HMD/controller tracking authoritative. Do not turn dizzy into forced camera rotation or knockdown into animation-driven head movement.

## Proposed tuning pass

1. Fix combined equipment mitigation, NPC AP discounts/profile conversion and DoT budget accounting. Keep separate tests for pets, droids, vehicles, PSGs and Force attacks.
2. Define standard, veteran and boss encounter budgets. Use enemy roles—melee pressure, ranged fire, control, support—to distribute specials and damage. Add cooldowns and readable preparation to dangerous specials rather than relying solely on random lists.
3. Tune ordinary Tatooine enemies against an unbuffed, appropriately skilled character without armour. Use time-to-incapacitation and kill time as primary targets; armour should extend the former by the planned 1.25–2× rather than be needed to survive one ordinary hit. Add armour hindrance and state uptime to the kill-time calculation.
4. As initial experiment targets, try 12–20s solo kills and 20–30s survival under uninterrupted ordinary attacks, before healing or avoidance. These are proposed SWGXR targets, not CU facts. Reject repeated unavoidable burst kills and control chains even when average DPS looks acceptable. Define boss budgets separately.
5. Measure native logs for raw/converted damage, channel mitigation, hit outcomes, target HAM, DoT seeds/ticks/wounds, state uptime, incoming attack cadence and number of attackers. Test unarmoured/basic/standard/advanced, a three-enemy pack, ranged/melee, a DoT attacker, and an elite. Avoid calculating survivability from summed HAM: losing any primary pool can incapacitate.

The crude relation `incoming DPS = baseline health / desired survival time` is useful only for a health-only model. While current HAM remains, evaluate each pool's damage/regen distribution and use the first pool to fail. Do not silently adopt CU health-only combat as part of an armour rebalance.

## Evidence and limits

Source paths below are relative to `vendor/Core3/MMOCoreORB`:

- `src/server/zone/objects/creature/ai/AiAgentImplementation.cpp`: setupCombatStats, setWeaponStats, setLevel, selectSpecialAttack, getReducedResist.
- `src/server/zone/objects/creature/ai/CreatureTemplate.h`: special-protection decoding.
- `bin/scripts/ai/default.lua` and `src/server/zone/objects/creature/ai/bt/leaf/SimpleActions.h`: default attack and targeting flow.
- `src/server/zone/managers/combat/CombatManager.cpp`: calculateDamage, applyDamage, applyDots, applyWeaponDots, applyStates, getArmorReduction, calculateWeaponAttackSpeed.
- `src/server/zone/objects/creature/damageovertime/DamageOverTime{,List}.cpp`: tick, wound, resistance and stacking rules.
- `src/server/zone/objects/creature/CreatureObjectImplementation.cpp`: stun/blind/intimidate and actual damage handling.
- `bin/scripts/commands/{flameSingle2,creatureAreaDisease,creatureAreaCombo,creatureAreaKnockdown,commands}.lua`: effect inputs and defaults.
- `src/server/zone/objects/creature/commands/{SwgxrLiveCombat,SwgxrMovement,DotPackCommand}.h`: bridge and independently delivered DoTs.

Arithmetic examples were compiled with C++14 against the actual `server/combat/ArmourModel.h`; template scan and outputs are saved in `runtime/evidence/pve-armour-audit.json`. No combat implementation or tuning was changed in this audit. No native server encounter, deployment or VR test was performed. Earlier armour arithmetic/syntax checks do not establish these PvE outcomes in a running server.
