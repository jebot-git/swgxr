# Smuggler

Smuggler uses the existing Core3 trainer, persistent skills, crafting, ranged
ability selector, wallet, medic drag, parcel and patrol interfaces. Native changes
are recorded in patches 0059–0064. No live VPS deployment or planet activation is
part of this change.

## Physical Feign Death

The original learned `feigndeath` ability is required. With tracking available,
lying low with the face upward or tilting the head backward at least roughly 70
degrees for 450 ms requests Feign Death. Standing at least 86% of calibrated eye
height with an upright head for 450 ms requests release. Tracking loss never
implicitly releases the ability. These thresholds are prototype gesture tuning.

Core3 owns eligibility and immobilization. The pending feign accepts one more
damaging blow, then enters the native feigned/incapacitated posture and ends
ordinary combat. A genuinely incapacitating or lethal hit remains real.
Deathblow-capable AI remains eligible to finish a feigning player. Upright release
returns to normal native aggression rules. Medics can use their existing two-hand
drag on a feigning patient. The incapacitated clip drives only untracked body
bones; tracked head/hands and the physics body retain their existing authorities.

## Ranged abilities

Use the existing select, arm, fire workflow. Core3 validates learned skills,
weapon restrictions, cooldowns and HAM at launch and records the ability with the
shot. A miss still consumes the launched ability; impact retries cannot consume
it twice. Original Low Blow retains its native command and weapon restrictions.

Last Ditch samples current/max health, action and mind **before** draining action
and mind to one point each. Its damage multiplier is:

`2 + (1 − health/max_health) + (1 − action/max_action) + (1 − mind/max_mind)`

Thus 30% health, 10% action and 3% mind yield `4.57×` base damage. This value stays
with the projectile even if HAM changes before impact.

Restraining Shot is granted at Novice Smuggler; Concussion Shot Improved at
Master. Initial tuning explicitly approved by the user on 2026-10-06 is a 25%
movement snare for 20 seconds and a 40-second concussion root/daze. Concussion
root, daze and attack delay break together on subsequent damage. These values
are prototype tuning, not a claim of exact NGE numerical parity. The CU behavior
is recorded in the archived [Publish 19 notes](https://swg.fandom.com/wiki/Publish_19_Notes_for_29_June_2005).

## Wallet

Novice Smugglers see separate Imperial and Rebel FP sliders alongside credits
after the normal wallet handshake. Underworld reputation is not transferable.
Payments may contain credits, either faction, or a combination. Core3 validates
the entire bundle before changing any balance, under both player locks.

The existing faction-rank delegation ratio applies to the sender's charge. A
200-point reserve remains; the recipient's native rank cap applies (1,000 for an
unaffiliated faction). The UI shows the ratio and sender's available amount;
recipient limits are checked at confirmation. The request receipt and handshake
bind all three amounts, so retrying a receipt cannot send again or change an
amount. Faction transfers use native persistent standings without earned-reward
bonuses.

## Underworld scope

The user selected ground PvE deliveries and patrol inspections; space, PvP and
corpse-search variants are deferred. Named brokers use original local NPC assets
and spawn only on already enabled planets. Ground routes reuse native Core3
delivery objectives, contacts, physical parcels and dialogue, within the current
planet. This is a ground adaptation of the live system, not an implementation of
cross-planet or space objectives.

The broker dialogue shows front money, reward and reputation eligibility before
acceptance. Native mission state controls deadlines, rewards, cancellation and
failure; genuine incap/death fails the delivery, while Feign Death alone does
not. Native patrol searches recognize the mission parcel as contraband. Existing
fine/refusal UI remains in use. Shuttle boarding is blocked while carrying out a
job. Higher-tier contacts remain local development content under the live
Tatooine-only hold.

The five brokers are Barak (Tatooine), Ogden (Naboo), Baldwin (Lok), Harding
(Endor), and Russell (Dathomir). Reputation gates begin at −3,000, 1,000, 1,500,
2,000, and 2,500 respectively. Supplied-parcel rewards grant 50 reputation in
the first tier and 25 in later tiers, following the documented
[Underworld progression](https://swg.fandom.com/wiki/Smuggler).
The 30-minute deadline, credit rewards and bounded criminal interceptions are
explicit prototype balance choices. Criminals use original native AI and assets;
encounters occur outdoors away from cities after pickup and travel, are limited
to two per job, and are cleaned up when the job ends.

## Spatial slicing

Hold the original precision laser knife in either hand, touch an eligible owned
item or a mission terminal, and press its trigger. Equipment must have native
crafted provenance (crafter ID and serial number). The user explicitly confirmed
that locked loot containers and mission terminals remain exceptions to the
crafted-only restriction. Ordinary looted weapons, armour, PSGs and clothing are
ineligible.

The world-fixed puzzle has 3–5 cells on each axis, 2–4 colored endpoint pairs,
10 cm cells and editable preconnections. Touch an endpoint with the knife and
route its wire through adjacent cells to its matching endpoint. Touching a
connected endpoint cuts that wire. Cells cannot be shared, including corners
skipped by a fast hand movement. Every generated board retains a native hidden
solution; complete preconnections can take alternate routes that need cutting.

The cube appears at chest height with the original item suspended below it;
terminal puzzles appear in front of the terminal. The item remains owned in
Core3 inventory and is reserved against transfers, equipment changes, deletion
and sale during the attempt. The user selected timed failure with invalid moves
ignored. Initial tuning is 180 seconds and abandonment after moving 2.5 m from
the starting position. Cancellation, expiry, abandonment or interrupted attempts
return the presentation to inventory and permanently burn that item's attempt.
A failed terminal attempt is recorded for that character and terminal, without
disabling the public terminal for other players. Tracking loss pauses the cursor;
the native clock continues. One knife charge is reserved for the attempt.

Original skill gates apply: containers at Novice, terminals and clothing at
Slicing I, weapons at Slicing II, and armour/PSGs at Slicing III. Bounty terminals
remain excluded. Successful terminal slicing grants each current party member
one non-stacking credit for a 1.5× reward on their next accepted eligible
mission-terminal job. Refreshing a list does not consume it. Normal native group
payout sharing still applies; Underworld broker deliveries retain their own
reward schedule.

Weapons gain one suitable handling bonus (capacity or rate of fire for ranged
weapons; Power or Stance Recovery for melee), a range-modifier bonus, and minimum,
maximum or both damage bonuses. Armour and PSGs gain one combat skill bonus (two
at Master), one randomly chosen HAM attack-cost reduction and protection.
Clothing grants one distinct noncombat skill bonus at Slicing I, two at II,
three at III, four at IV and six at Master, as explicitly selected by the user.
Slice skill bonuses preserve original attachment/socket modifiers. Original
wearable skill limits still apply; total worn attack-cost reductions cap at 80%,
and protection caps at 90% without removing damage-type vulnerabilities.

The user approved the original weapon/protection percentage ranges and initial
new bonus ranges: skill magnitudes run from +1–5 at Novice to +20–25 at Master;
new percentage bonuses run from 5–10% to 20–35%. Range modifiers add points to the
existing range curve. Higher tier gates determine which categories can use those
ranges. Outcomes persist separately from base crafted statistics, so repeated
examine, equip and login operations do not multiply the bonuses again.

A direct Novice Smuggler killing blow on a normal native humanoid NPC receives
an independent 20% roll for an original locked container, in addition to ordinary
loot. Pet kills, pets, wild creatures and event mobs are excluded. Existing
corpse ownership rules remain in force. The bonus chance is configurable through
`Core3.Smuggler.LockedContainerBonusPercent`.

## Spices

Spices are crafted through the native schematics and consumed from the existing
inventory. Original templates retain their HAM modifiers and active durations.
Native persistent buffs own phase timing and the one-spice restriction. The new
withdrawal durations below replace the original generic downer duration; the
existing food modifier for reduced spice downtime still applies. Death
uses the existing native buff-clearing rules.

| Spice | Additional active effect | Withdrawal |
| --- | --- | --- |
| Grey Gabaki | Ability cooldowns ×0.9 | None, including no HAM downer |
| Sweetblossom | First incapacitation recovers immediately; second is lethal | Any damage incapacitates; slow pain pulse, 3 minutes |
| Giggledust | Local through-wall outlines of aggressive NPCs within 64 m | Shifting psychedelic colours, 2 minutes |
| Scramjet | Health regeneration ×1.2 | Health regeneration ×0.8, 2 minutes |
| Shadowpaw | Action regeneration ×1.2 | Action regeneration ×0.8, 2 minutes |
| Thruster Head | Mind regeneration ×1.2 | Mind regeneration ×0.8, 2 minutes |
| Yarrock | Two additional experimentation points | Experimentation fails and local hands shake, 15 minutes |
| Zypolene Droid Lubricant | Power and stance recovery ×1.2 | Both ×0.5, darkening in 30-second cycles, 3 minutes |
| Gunjack | Capacity and rate of fire ×1.2 | Both ×0.5, the same darkening, 3 minutes |
| Pyrepenol | Melee damage ×1.25; forward 180° melee area attacks within weapon range; crimson view | NPCs appear aggressive locally and on the radar, 5 minutes |
| Crash and Burn | Healing from items and abilities ×3 | Outgoing healing becomes equal damage while the healer still sees healing feedback, 5 minutes |
| Sedative H4b | Primary HAM cannot fall below 1 and ordinary damage cannot incapacitate; noisy view | Immediate incapacitation and primary HAM fixed at 1/1/1, 5 minutes |
| Neutron Pixie | Entertainer wound healing and inspiration strength ×2; slight pink tint | Dance or music attempts knock down the performer; slight blue tint, 10 minutes |
| Muon Gold | Experimentation always yields native Amazing Success; slight yellow tint | Experimentation always yields Critical Failure; local hands shake, 1 hour |
| Booster Blue | Ranged aim latches onto an eligible reticle target; monochrome view | Greyscale view and delayed, slowed virtual gunhand movement, 5 minutes |

Sweetblossom withdrawal reacts to actual damage, including native poison and
bleeding. Ability HAM costs, equipment encumbrance and buff/stat bookkeeping do
not count as damaging hits.

Sedative does not prevent an explicit deathblow. Its withdrawal starts ordinary
native incapacitation; after the normal recovery timer, HAM remains fixed at 1
for the remainder of withdrawal. Neutron's wound bonus means twice the normal
healing amount, not clearing all wounds. Muon keeps Core3's Amazing Success label.

Crash and Burn affects the healer's medical actions, not passive regeneration or
unrelated HAM adjustments. During withdrawal, the acting player receives no
withdrawal notification and continues to see healing feedback. Actual HAM,
including self-healing damage, remains authoritative. Other recipients see damage.

Spice weapon modifiers compose with crafted and sliced values without altering
the persistent item statistics. Capacity rounds once after composing modifiers.
Cooldown reductions apply to abilities, preserving unrelated travel, mission,
trade and interaction timers.

All screen effects, false hostility, outlines and hand distortion are local.
Booster Blue alters the virtual weapon and hand pose before existing arm
constraints; it does not alter HMD/controller tracking or the physics body.
Forcefully lowering the physical gun hand below the view releases the aim latch.
False hostility does not change server AI, eligibility or aggro.

## Validation

Headless Godot tests always use `--xr-mode off` and the dummy renderer. Their
tracking inputs are mocked; they do not validate a real headset or GPU rendering.
Native test receipts and build logs belong in ignored `runtime/evidence` and
`runtime/server`, with exact verification results recorded after execution.

Validated on 2026-10-06:

Spice validation adds 79 client checks covering authoritative phase presentation,
real gunhand/muzzle alignment, raw peer tracking, native cross-cell outline replay,
minimap restoration and profile refreshes. The 64-check native lifecycle suite
verifies real regeneration ticks, incapacitation/death behavior, Sedative HAM
pinning, Pyrepenol cone hits and Giggledust across original building cells.
The 39-check native weapon suite consumes actual items and shortens only fixture
buff timers to check active, withdrawal and restored statistics, including
unarmed Power/recovery and live weapon-profile reads. A separate 13-check native
Sweetblossom regression verifies actual special-attack/Tumble HAM costs and real
poison/bleeding ticks.

The 67-check native professions suite verifies actual medical abilities and
items, reversed healing feedback, Grey recovery timers, doubled entertainer
wound healing and inspiration (including the applied patron buff), withdrawal
knockdowns, and original crafting experimentation and production. Muon produces
Core3's Amazing Success while active and Critical Failure during withdrawal;
Yarrock adds two experimentation points and fails during withdrawal. These
fixtures use documented privileged setup and shortened buff timers, with all
tested actions executing native production paths. The receipt is
`runtime/evidence/spice-professions-native-smoke.json`.

Eight desktop Forward+ Vulkan captures exercise original meshes and the compiled
per-view compositor on Intel Arc A770. These use mocked spice phases and XR off;
they do not validate live headset rendering. Tracked weapon/avatar regressions,
local hand poses, multiplayer poses, dedicated collision and all 12 actual
starport traversal checks pass.

The general stage smoke's imported `shared_terminal_space.iff` wall check fails
identically on the changed client and an isolated full HEAD client: travel
4.834428 m, clearance −0.197149 m, `wall_stopped: false`. This is recorded separately
from the passing collision and portal traversal checks.

- The complete Python suite passes 336 tests.
- Core3 builds successfully and all 68 source patches replay from the pinned base.
- `smuggler_live_smoke.py`: 26 actual Core3 combat checks, including 4.57× Last
  Ditch launch/impact, HAM consumption, native snare, concussion damage break,
  Feign's extra hit, ordinary aggro loss, standing recovery, killer deathblow and
  explicit scene-readiness recovery after a native zone transfer.
- `smuggler_wallet_smoke.py`: 27 native checks covering combined payment,
  faction-rank charges, receipt replay, handshake amount binding and atomic cap
  rejection.
- `smuggler_drag_smoke.py`: 9 native two-player checks covering pending and
  completed feign, physical hand displacement, patient refusal and upright exit.
- `underworld_native_smoke.py`: 71 actual Core3 checks, including completed routes
  through all five brokers, native parcel inspection, exact rewards, timeout,
  true incap, Feign preservation, cancellation, replay, scheduled criminal
  interception, exact encounter cleanup and stale-ID protection for unrelated NPCs.
- `slicing_native_smoke.py`: 59 actual Core3 checks covering native puzzles,
  crafted-only equipment eligibility, gear outcomes, container unlocking,
  permanent failure, party mission credits/payout and actual locked-container
  bonus loot. Gear setup in this test uses privileged disposable provenance
  fixtures; it does not claim that those fixtures were crafted by a player.
- `slicing_crafting_native_smoke.py`: 33 checks using a fresh original Artisan
  with no granted skills, ingredients, items or provenance. Original mission
  components pass native assembly and timed production; the output receives
  genuine crafter/serial provenance and completes its original delivery.
- `slicing_stats_native_smoke.py`: 32 checks of actual ranged/melee getters and
  profiles, armour/PSG protection, six worn clothing modifiers, removal and
  re-equipping without stacking, and exact native Lethal Shot HAM charges.
- `slicing_last_charge_native_smoke.py`: 12 checks on the final rebuilt runtime,
  including using the knife's last charge, completion replay, active-attempt
  logout/re-entry, permanent failure and exactly one consumed charge.
- The native puzzle policy test verifies 9,000 boards across every supported
  size/pipe-count combination, including complete alternate preconnections and
  rejection of overlapping/nonadjacent paths.
- Client slicing tests pass 130 board checks, 30 controller checks and 21
  equipment-refresh/native-envelope checks. They verify same-ID stat refresh,
  ammunition/cooldown preservation and actual native challenge parsing.
- Client Smuggler, medical, life, ranged, services, multiplayer and original
  avatar pose regressions pass with mocked tracking and dummy rendering. The
  original-avatar pose test includes 10,366 assertions.
- Broker discovery uses the existing Mission map filter and NPC dialogue. The
  controller, map and broker appearance tests pass 63, 31 and 49 checks
  respectively, including all 24 original delivery NPC appearances.
- Desktop Vulkan Forward+ wallet/dialogue captures are stored as
  `runtime/evidence/smuggler-wallet-vulkan.png` and
  `runtime/evidence/smuggler-underworld-vulkan.png`; both were visually inspected.
  Slicing captures are `runtime/evidence/slicing-grid-vulkan.png` and
  `runtime/evidence/slicing-grid-small-vulkan.png`, using mocked challenges;
  these were also visually inspected.

The existing `gameplay_session_smoke.gd` assertion “Persistent lost connection is
visible” also fails against unchanged HEAD: its mocked recovery GET replaces the
expected error text. This is separate from the passing Smuggler transport checks.
Live headset rendering and physical posture comfort have not been validated.


## VPS deployment

Deployed on 2026-10-07 through graceful save, backup and restart. The test realm
remains Tatooine-only; existing accounts, characters and private configuration
were preserved. Authenticated HTTPS verifies the new native state and a saved
persistent test session. See `docs/VPS_DEPLOYMENT.md` for the binary hash and
backup/evidence paths. No live headset test was performed.
