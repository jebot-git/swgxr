# Ground PvE rewards

`0031-pve-rewards.patch` changes Core3's native NPC/animal and lair damage/death paths, including ordinary combat outside the XR adapter. Space combat and player-versus-player reward paths are unchanged.

## Experience

Only actual applied damage contributes: integer HAM loss across all damaged pools for creatures, condition loss for lairs. Overkill is clamped to the remaining pool/condition; rejected, invulnerable, postmortem and forecast damage contribute nothing. Native DoT ticks count when they occur, using the original `dotDMG` XP category. Merely applying a DoT pack does not pre-credit predicted ticks.

Each eligible player receives their original XP basis multiplied by their damage divided by **all** actual damage. NPC/environmental and explicitly non-XP damage remain in that denominator. Removing a dead or disconnected attacker from the native threat entries does not increase the remaining players' fractions. Native eligibility, range, species, faction, group and global multipliers remain; different modifiers can therefore produce different XP-per-damage rates. Native rounding and XP pool caps still apply.

The full-kill level cap is applied **before** splitting. This deliberately corrects the original cap-after-split behavior, which could award equal capped amounts to unequal contributors. The solo cap is unchanged. Group membership never transfers another player's damage or grants passive squad-leader kill XP. Pets retain the original qualifying creature-handler XP path, scaled by their actual damage fraction and credited to their owner.

## Corpse rights

The final blow owns corpse items, cash, manual organic harvesting and droid harvesting. A pet's final blow resolves to its player owner. Group membership does not share these rights. An NPC/environmental final blow assigns the corpse's own non-player object ID as owner, preventing owner-zero/group-zero fallback from opening public access. Existing quest/faction attribution is preserved independently of corpse ownership.

## Verification

`tests/pve_reward_policy.cpp` exercises 33 arithmetic cases, including exact 70/30 allocation, cap-before-split, excluded/removed contributors, pet shares/ownership, actual HAM clamps, nonlethal/secondary pools, overkill, repeated condition damage and overflow. It is a standalone C++ policy test, not native gameplay execution.

`tools/server/pve_rewards_smoke.py` runs two real Core3 player sessions using certified original FWG5 pistols against newly spawned original worrts. Fixture-only Lua gives those isolated accounts their skills/items, disables target regeneration and controls target HAM to produce a measurable ratio; it does not grant XP or set corpse ownership. The temporary exact Lua block is removed on completion. No diagnostic C++ endpoint is compiled into the server.

The production binary passed 16 native assertions and 44 live-session protocol checks. Actual applied damage was 145/62 (70.048%/29.952%); native pistol XP was exactly the expected 82/34 after original human species bonus and integer rounding. Checks verified overkill clamping, final-blower-only item/cash/organic rights, denied nonkiller looting, real original resource yield, independent-login XP persistence, environmental damage remaining in the denominator, zero bystander XP and no player rights to an environmental kill. Evidence: `runtime/evidence/pve-rewards-native.json`; build fingerprints: `runtime/evidence/pve-rewards-native-build.json`.

Pet, grouped-player, DoT, disconnected-player and lair behavior has arithmetic/source coverage in this milestone, but has not received a new multi-client native scenario test. No live VR test was run. Local test accounts and their objects must not be migrated into the fresh VPS world.
