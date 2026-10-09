# Ability activation audit

Audited against the working client and native command adapters on 2026-10-09.
This records implemented player-facing actions, not every command inherited
from Core3. A controller button or selecting a holographic option is not a
dedicated body/hand gesture. Physical tool contact is distinguished below.

## Remaining profession action scope

Bounty Hunter uses original mission terminals, informants and held droids,
plus the single-target combat controls below. Smuggler has its targeted attacks, Last Ditch and utility
interactions; mixed-profession balance remains part of the shared combat review.
Force-sensitive and Jedi professions are outside the initial release.

The [Bounty Hunter combat policy](CORECU_COMBAT.md#bounty-hunter-single-target-combat-2026-10-09)
evaluates the original grants against preserved CU proposals and published SOE
changes. Its controls are implemented in source and tested with mocked tracking;
the current native build and live encounter acceptance remain pending.

Politician has no separate active ability kit: its profession actions belong to
city and terminal interfaces. Any missing citizenship, election or municipal
management interfaces are terminal work, not missing gestures, VATS actions or
an ultimate. Entertainer benefits use automatic eligibility within the
performer's radius; no manual watch/listen or buff-recipient selection is part
of the intended player controls (user direction, 2026-10-09).

## PvE bounty hunting

Use an original bounty mission terminal through the existing terminal panel.
Novice Bounty Hunter is required. Accept a PvE offer, then contact an eligible
informant through the existing NPC interaction panel. The mission's Data entry
shows the current investigation and offers the normal cancellation action.
Native mission waypoints use the existing map and navigation controls.

Hold a bounty droid from inventory and squeeze its trigger:

- **Arakyd probe:** choose a planet in the popup list to launch a search there.
  Only loaded original ground planets are offered. The selected search planet
  is independent of the hunter's current planet. The biological signature is
  transmitted automatically; there is no separate deployed-probe interaction.
- **Seeker:** launch immediately. Advanced tracking is selected when the native
  mission and learned skills permit it; otherwise it performs a single search.
  Its search is local to the hunter's planet.

Original investigation skills, biological signature, consumable charges and
search delays still apply. A probe reports the searched planet's result;
a seeker supplies or updates the target waypoint. Hidden coordinates are not
drawn before discovery. Results, failures and remaining charges come from Core3.
Droids are consumed mission tools; the pet command system does not control them.
Player bounties are unavailable in this release.

## Bounty Hunter combat

Pistol VATS adds **Eye Shot** at the head and upgrades the shared **Bleeding
Shot / Torso Shot** abdomen entry. Carbine VATS adds **Confusion Shot** at the
torso. These use the four regular loadout slots alongside learned Marksman and
other profession options. Training BH does not grant Pistoleer Fan Shot; that
fanning gesture remains available when Pistoleer is also trained.

**Underhand Shot:** support the carbine with both hands, release the triggers,
hold it low, make a short upward muzzle arc, and return to aim. Native
acceptance arms one shot for 1.5 seconds. Pull the trigger to fire; a miss still
spends the shot and costs. Weapon/context changes cancel the opportunity.

**Duelist Stance:** hold a compatible pistol, carbine or BH lightning rifle
forward toward one eligible enemy. With triggers and offhand grip released,
tap the upper sternum twice with the free hand, separating the taps. Accepted
protection stays bound to that opponent for eight seconds. This open-hand
gesture is distinct from Brawler Taunt's clenched-fist chest beat.

**Fast Blast:** select it as the one equipped ultimate after Master Bounty
Hunter training, then use the existing two-trigger chord. It delivers one
heavy attack against one target with the compatible held weapon.

The scatter pistol uses eight physical pellets in a wider cone and one total
damage budget against one primary enemy. The lightning rifle has slight,
bounded tracking of one acquired enemy. Both still collide with world geometry;
neither adds a BH area attack. No pose or controller movement is forced.

## Squad Leader support

With any equipped weapon, including unarmed, aim at a nearby eligible party
member and click the weapon-hand stick. Friendly VATS exposes all five learned
support shouts: Steady Aim, Rally, Form Up, Boost Morale and Retreat. Aim at the
desired marker and squeeze/release the trigger. These options do not occupy
the four offensive targeting slots. The selected ally anchors the action;
eligible nearby group members within 48 metres receive the shout. Native costs,
availability and recipient recovery remain authoritative. Doctor's separate
friendly Heal State VATS still requires the held Doctor tool.

Master Squad Leader adds **Volley Fire** to the existing ultimate choice for
every weapon family. Aim at an eligible enemy within 64 metres, release both
triggers and press them together. It consumes no round by itself. Each eligible
party member receives a large local gold reticle on that enemy for 12 seconds.
Aim a normal attack at this reticle, or use a targeted attack against the marked
enemy, to spend that member's one guaranteed hit. The attack must be inside its
own native range; a rifle's mark does not extend a melee weapon's reach.
Physical contact and avoidance cannot cancel the guaranteed hit, but damage,
armor, resources, ammunition and separate status resistance still apply.
The first damaging packet receives the guarantee; other multi-hit packets keep
normal defenses. Attacking another enemy does not consume the mark.

Traps and grenades can spend the same guarantee through their existing throw
gesture. Their native delay and supply costs remain. Pure status applications,
ongoing DoT ticks, healing and self-buffs do not consume it. Newly joining
members cannot acquire an old mark; each recipient has 120-second recovery
against repeated grants by different leaders. Stale snapshots, lost membership
and expiry hide the local reticle. No attack or controller movement is forced.

## Commando equipment

Certified flamethrowers, acid rifles, heavy particle/acid/lightning weapons,
rocket launchers and the pistol launcher provide the primary attacks. Flame
uses a short cone; acid rifles and heavy beams use directed native shapes;
rockets use physical flight and an accepted impact. Support the long weapons
with both hands. The pistol launcher may fire one-handed. The Bounty Hunter
lightning rifle is a separate weapon and is not part of this kit.

Focused Discharge occupies one optional VATS slot: one target, 15% more direct
damage, no splash. Acid Spray is a second optional slot while holding the acid
rifle and knowing its original cone command: a wider, weaker attack with no
armor debuff. Ranks improve progression rather than duplicate the slots.
Master Commando can select Overdrive as the heavy-family ultimate. Release both
triggers, support the weapon and press both together: six seconds of +25%
direct damage and +50% Action cost, with normal charges and a 120-second cooldown.

Grenades use the same inventory/hip grip, throw motion and release at the reticle
as traps. They occupy no VATS slot. Native acceptance locks the landing point,
reserves a charge and starts a two-second fuse; the original grenade model and
detonation effect follow that receipt. Cryoban slows voluntary movement and
Glop briefly restrains it. These effects never reposition the tracked head.

## Merged Brawler Warcry

Warcry and Intimidate are one player-facing ability, **Warcry**, listed in the separate gesture row without occupying a targeting slot. With a certified weapon held and both triggers released, raise the weapon hand above the head, lower it slightly, then pump upward. Face the enemies to affect. No target marker or circle-menu selection is required. Novice Brawler unlocks it; Master Brawler improves its durations. Taunt remains a separate chest-beat gesture.

The gesture requires a tracked raise from below head level, an overhead downward movement of at least 16 cm and upward pump of at least 18 cm within 1.8 seconds. Static poses, a raise alone, large head motion, tracking loss, item changes, menu capture and trigger presses reset or reject it. No camera or controller animation is imposed. Validation is mocked tracking and native syntax/policy checking; full server build and live headset testing remain unverified.

## Primary actions without a dedicated gesture

| Profession/system | Abilities/actions | Current activation |
| --- | --- | --- |
| Medic | Tend Damage, Quick Heal | Aim the medical focus and tap/release for Tend Damage after the 0.30-second double-tap window; hold trigger 0.65 seconds for Quick Heal. The hold fires once without first casting Tend Damage. No circle selection needed. |
| Medic / Doctor / Combat Medic | Stims, Health Wound Medpacks, cures, state packs, enhancements, resuscitation | Hold the actual supply against an eligible patient and trigger. Ranged stims can be aimed; native skill, consent, recovery and location rules apply. |
| Doctor | Heal State | Hold the Doctor tool; click its stick while aiming at an eligible friendly patient. Aim at a condition marker, squeeze and release the tool trigger. Requires the matching state pack in inventory. Stow or tracking loss closes friendly VATS; active markers capture combat input. |
| Combat Medic | Poison / Disease | With the Doctor tool held, click its stick at a hostile target. Aim at the Poison, Area Poison, Disease or Area Disease marker and squeeze/release; the displayed exact compatible pack is consumed by native delivery. Target relation, tool or supply changes cancel the attempt. |
| Combat Medic | Heal Mind | Aim the held Doctor tool at another friendly player or organic pet and double-tap its trigger within 0.30 seconds. No action selection or VATS step is needed. The double tap transfers actual Mind from healer to patient, plus Action cost, without casting Tend Damage first. A 0.65-second hold still casts only Quick Heal. |
| Entertainer / Dancer / Musician | Performance healing and inspiration | Automatically reaches eligible players in the performer's eight-metre radius through native performance ticks. No Watch, Listen or buff-target action; earned inspiration keeps its native minimum time and duration. |
| Creature Handler and droid pets | Learned pet commands and command training | Intentionally remain in the circle menu (user direction, 2026-10-08): too numerous and varied for reliable gestures. Trigger over the pet opens its circle; select a command, then trigger, aiming at a target when required. Calling uses the datapad. |
| Marksman and Smuggler | Lethal Shot, Low Blow, Restraining Shot, Concussion Shot Improved | Click the weapon-hand stick while aiming at an eligible creature, then shoot its local body-part marker. No selection/priming step. |
| Smuggler | Last Ditch | Hold the weapon with both hands and press both triggers while aiming at an eligible creature. |

Sources: [Scout controller](../client/scout/controller.gd),
[medical controller](../client/medic/controller.gd),
[native medical ability list](../server/medic/SwgxrMedic.h),
[entertainer controls](../client/entertainment/controller.gd),
[pet commands](../client/pets/commands.gd),
[pet calling](../client/pets/controller.gd),
[combat selection](../client/combat/ranged_rig.gd),
[native ranged abilities](../server/smuggler/SwgxrSmuggler.h).

## Tool/contact actions and interfaces

These already involve spatial interaction, but do not have an independent
recognised gesture for each ability:

- **Sample DNA:** select/arm, put either hand against the creature, then trigger.
- **Conceal:** hold a camouflage kit and trigger; contact the other player to
  apply it to them.
- **Survey:** hold the survey tool, select a resource and trigger. Resource
  extraction uses the deployed-tool workflow.
- **Harvest:** trigger above a corpse, then grip the desired resource hologram.
- **Crafting/experimentation:** activate the held crafting tool, select a recipe,
  place ingredients and manipulate the crafting controls. This includes
  profession-specific crafting and Bio-Engineer products.
- **Camp deployment:** trigger the held camp kit. Management/disbanding uses
  the camp terminal panel.
- **Spice use:** trigger the held consumable. **Slicing** already uses knife
  contact and spatial wire routing.

Sources: [DNA sampling](../client/bioengineer/sampling.gd),
[Ranger controller](../client/scout/ranger.gd),
[inventory item activation](../client/scripts/xr_inventory.gd),
[gathering](../client/scripts/resource_gathering.gd),
[corpse interaction](../client/scripts/corpse_gathering.gd),
[crafting](../client/scripts/crafting_controller.gd),
[slicing](../client/slicing/controller.gd).

## Existing gestures and scope limits

Image Design starts with two opposing thumb/index L shapes forming a frame near
eye level, held for 0.8 seconds with free hands. Either diagonal is accepted.
Optical joints recognise the fingers; controllers approximate the pose with grip
held and index/thumb released from their controls. The gesture opens the existing
recipient selector, preserving native eligibility and the recipient consent flow.
Lower/open the frame before another activation; tracking or focus loss cancels
partial progress without rearming a completed hold. Circle access remains.
See [frame recognizer](../client/entertainment/image_frame_gesture.gd).

Gesture paths already exist for Mask Scent (repeated rubbing along either opposite
forearm with free hands), Brawler Taunt (chest beats), Feign Death
(posture), Burst Run (arm strokes), Forage (digging), creature inspection
(pondering pose and gaze), Rescue (two-finger pointing), Area Track (hand over
eyes and head sweep), taming (clap/beckon), Embolden and Enrage (fist poses),
mount training (head stroking), dancing/instrument performance, performance
location registration (raised-arm hold), band joining (thumbs-up), and
flourishes (one clap while performing; A remains available).
First Aid uses a wrapping bandage motion around a bleeding player's forearm or one's opposite forearm; focus/trigger activation also remains. Medical dragging and pet recovery use tracked hand contact.

Doctor revival uses the actual held resuscitation kit: approach the patient's
chest with two separated hands, squeeze the free hand's grip for 0.65 seconds,
then release it while keeping pad contact. Start with the supply clear of the
patient; both triggers stay released. Fire treatment uses the held fire blanket:
settle at the torso, sweep at least 30 cm, return at least 22 cm and settle for
0.2 seconds. Move clear before repeating either gesture. The patient-relative
motions support either hand and seated users. Native eligibility, consent,
resources, supply charges and recovery still apply. Doctor gains no ultimate.
After friendly VATS closes, both tracked triggers must be released before weapon
combat resumes, so a held treatment input cannot become a shot or ultimate.
See [Doctor gesture recognizer](../client/medic/doctor_gestures.gd),
[friendly VATS](../client/medic/doctor_vats.gd) and
[Doctor preparation and care policy](CORECU_COMBAT.md#doctor-preparations-and-care-2026-10-09).

Tend Damage and Quick Heal's tap/hold tool controls are accepted physical
activation mechanisms (user direction, 2026-10-08), not outstanding gesture work.
Explicitly selecting First Aid retains its short-trigger fallback; the long hold
still requests Quick Heal. Consumable medical supplies keep their contact/trigger
workflow. See [focus trigger](../client/medic/focus_trigger.gd).

See [client controls](../client/README.md), [Smuggler](SMUGGLER.md),
[creature gestures](../client/pets/creature_handler.gd),
[Scout gestures](../client/scout/gestures.gd),
[Mask Scent gesture](../client/scout/mask_scent_gesture.gd), and
[performance gestures](../client/entertainment/gestures.gd).

Start/Leave Band, Stop Performance, and Leave Party are management menu actions.
Fist-bump party formation is implemented separately from performance bands.

Melee Assault remains a local profession-lab translation; it is not a missing
gesture on an enabled native melee special. Likewise, inherited advanced
profession command definitions do not imply a supported client action. Their
remaining ability design is deferred; the first native medical/buff balance pass is documented in
[CoreCU scope](CORECU_COMBAT.md). The native medical interface above exposes three
focus abilities plus held medical supplies, including Doctor resuscitation, Combat Medic poison/disease deliveries and direct Heal Mind. Hospital placement remains a separate city permission; no Combat Medic ultimate is enabled.

Pet stims, droid damage kits and Droid Engineer reconstruction kits also use held-item contact/trigger treatment on the existing companion model. Their native recipient type, supply, resource and recovery checks remain authoritative.

## Combat ability equipment

Each weapon family has four targeted combat slots and one selected ultimate.
Gesture support abilities occupy a separate **Gestures — no slot** row. Learned,
weapon-compatible gestures are available automatically; pointing at one explains
the trigger and weapon requirements. They cannot be dragged into a slot or
activated by clicking their tile. Warcry, Taunt and learned Feign Death are
listed here, alongside Center of Being, Berserk, Fan Shot and Run and Gun. While the
equipment hologram is open, click the **physical right stick** (also when using
left-handed weapon controls) to expand the ability editor. The four slots appear
above the avatar, learned compatible abilities fill the left grid, and pointing
at one shows its description in the right pane. Grip-drag an ability into a slot;
dragging between slots swaps them. Drag an equipped slot back to the grid to
clear it. Confirmed occupied slots draw lines to their activation body parts.

Ultimates are exclusive to advanced professions; basic professions, including
Master Brawler and Master Marksman, grant none. Each ultimate must explicitly
name its owning advanced profession in the native policy. Last Ditch currently
belongs to Smuggler and still requires its native command grant; learning an
unrelated advanced profession does not unlock it. Losing the required profession
removes the usable selection and prevents activation. Center of Being and
Berserk remain Brawler gesture buffs, not ultimates.
Showdown belongs to Master Pistoleer. A mixed pistol build can keep Fan Shot and
Run and Gun available while choosing another learned pistol ultimate, such as
Smuggler's Last Ditch.

Ultimates occupy a separate row in the left grid. Click with the pointing-hand
trigger to select one; clicking it again clears the selection. The pointing hand
is the weapon hand. Stick up/down pages large catalogs. Right-stick click returns
to equipment. Tracking loss or dropping outside a destination cancels the drag.

Core3 confirms and persists these choices per character and weapon family. Only
equipped abilities can produce target markers or respond to the ultimate chord;
normal cooldown, resource, weapon, range and target checks still apply. New family
loadouts are empty. The native melee catalog offers learned Knockdown Strike, Stunning Attack,
Blinding Attack and Polearm Stun where the weapon family permits.


## Brawler targeting and self-buff gestures (2026-10-09)

The weapon-hand stick opens melee target markers as well as ranged markers. For
unarmed combat, use the dominant-hand stick while looking at the enemy. Hold the
trigger and physically punch toward the desired marker with the weapon hand, or
either fist when unarmed. A qualified forward punch selects along its actual
travel direction, so the fist need not reach the enemy's marker. Weapon range
still applies. A qualified weapon swing or punch contacting the marker also
works: knees for Knockdown Strike,
jaw/head for Unarmed Stun, eyes for Blinding Attack, upper chest for Polearm Stun.
Knockdown Strike uses the original Master Brawler Lunge II grants; Unarmed II/III
and Polearms III retain their respective stun/blind grants. These occupy regular
targeting slots. Ordinary swings and punches remain available without markers.
Stationary controller aiming, slow movement, pulling back and whole-body movement
do not qualify as directional punches. Tracking loss and frame gaps clear pending
input. The equipped weapon supplies the ability, cost and damage; a weapon-hand
punch does not switch the attack to the unarmed family.

Center of Being and Berserk appear in the gesture row and consume no targeting
or ultimate slot. CoB: hold the free offhand upright and open in front of the torso
for 0.8 seconds, with the weapon hand lowered. This is a controller approximation
of the requested meditation sign; it does not claim optical finger recognition.
Berserk: spread both arms outward near shoulder height and hold both fists for
0.8 seconds. Controllers use grip to represent closed fists; keep triggers
released. No microphone or actual yell is required. Both gestures require a
neutral pose before repeating and reset incomplete holds on tracking/focus loss
or equipped-weapon changes. Melee/unarmed equipment and original skill grants
remain required. No player camera or tracked hand animation is imposed.

## Teras Kasi tank controls (2026-10-09)

TKA's three area attacks appear in the gesture row and use no targeting slots.
Use the unarmed family, keep both hands free, clench both grips and release both
triggers. Sweeping Punch is one horizontal fist sweep with the other hand steady;
Two-Handed Half-Spin sweeps both fists together across the front from one side;
Rapid Punch Volley is three alternating forward punches. No full body spin is
required. Return to a still central guard or release grip before repeating.
Holding trigger retains ordinary punches and punch-to-marker attacks. Tracking
loss, frame gaps, occupied hands and equipment changes clear incomplete gestures.
The detector uses a fixed starting yaw and head-relative translation, so looking
around and virtual locomotion cannot supply a gesture.

Suggested four targeting slots are Challenging Strike (chest), Stunning Attack
(jaw), Blinding Attack (eyes), and Unbalancing Strike (knees). Challenging Strike
unlocks at Novice TKA. Unbalancing Strike uses the existing Knockdown Strike slot
and selects the strongest trained TKA knockdown rank, falling back to the Brawler
lunge. These remain equipped, single-target punch/swing-to-marker abilities.

Indomitable Focus is the Master TKA ultimate. Select it in the unarmed ultimate
row, bring clenched fists together in front of the chest, release both triggers,
then press them together. It needs no enemy target. During its 12 seconds,
trained/active CoB efficacy is amplified, status resistance increases, and damage
generates extra threat. It does not refresh the separate CoB buff. CoB's open
meditation hand and Berserk's spread-fist hold remain independent support gestures.

## Swordsman controls (2026-10-09)

Swordsman uses certified two-handed melee weapons. The suggested four targeting
slots are Rending Cut (side of torso), Disrupting Blow (weapon arm/shoulder),
Hamstring (knee), and Decisive Strike (heart). Use the existing weapon-hand stick
and punch/swing-to-marker controls. Knockdown Strike can replace one of these
four; the new abilities do not add slots. Decisive Strike appears only below 30%
of effective maximum Health and never on a boss. Native target combat level
reduces its damage; it does not use player level or level-gap gates.

Overhead Cleave and Ground Slam appear in the gesture row, with no targeting
slot required. Hold the weapon with both hands and release both triggers. Begin
in a lower ready position briefly. For Cleave, raise the weapon above your head
and make a committed downward stroke. For Slam, move directly down from the lower
ready position, aiming ahead at nearby enemies. The gesture completes above the
physical floor; no floor contact is needed. Return to a neutral guard before
repeating. A smaller upward pump still belongs to Warcry. Completed gestures
consume one attack and cannot also produce an ordinary swing or marker attack.

Armour Break belongs to Master Swordsman. Select it in the two-handed melee
ultimate row. Aim at an eligible enemy while holding the weapon with both hands,
release both triggers, then press both within 120 ms. Holding the inputs cannot
repeat the ultimate. A single weapon-hand trigger resumes ordinary attack input
after the short chord window. The ultimate refuses an already fractured target.
Tracking/hand-support loss, item changes and blocked combat UI reset pending input.

## Fencer controls (2026-10-09)

Fencer uses certified one-handed melee weapons. Four suggested targeting slots
are Arterial Cut (torso), Nerve Strike (weapon arm), Disorienting Thrust (eyes),
and Exposing Thrust (upper chest). The weapon-hand stick opens the existing
local target overlay; punch or swing at a marker to attack its bound entity.
Only Disorienting Thrust needs shared control recovery for its marker to appear.
The other attacks remain usable against bosses, subject to native immunities,
resistance, range, SAC and cooldown.

The three gesture attacks occupy their own row and use no targeting slots.
Hold the weapon grip and release triggers, briefly resting in a neutral guard.
Probing Jabs requires two quick forward weapon-hand jabs with retraction between.
Raking Slash travels diagonally from either upper corner across the body.
Guard Bash requires a brief blade guard followed by a short forward hilt thrust.
Return to neutral before repeating. Tracking loss, frame gaps, large pose jumps,
head translation, weapon changes and combat-blocking UI reset incomplete input.
Recognition uses fixed starting yaw, so turning the head cannot complete a
gesture. Holding the main trigger retains ordinary swings and marker attacks.

Flawless Assault is exclusive to Master Fencer. Select it with one click in
the one-handed melee ultimate row. Support the weapon with the offhand, release
both triggers and press both within 120 ms. It is a self buff and needs no enemy.
A held chord cannot repeat; a lone main trigger returns to ordinary attack input
after the chord window. An occupied or untracked offhand cannot activate it.

## Pikeman controls (2026-10-09)

Pikeman uses certified polearms and the existing four-slot polearm loadout.
Unbalancing Thrust retains `knockdown_strike` at the knees; Concussive Strike
retains `polearm_stun` at the head. Existing saved assignments remain valid.
Pinning Strike targets the foot and Disrupting Jab targets the weapon arm.
Use weapon-hand stick to open the local overlay, then punch/swing at the marker.
Hard-control markers hide during shared control recovery; Unbalancing Thrust
also hides during native knockdown recovery. Pinning Strike remains available.

All three gestures require both hands supporting the polearm, grips held and
triggers released. Rest briefly in a neutral guard before starting. Overhead
Whirl is a horizontal circle above the head, in either direction. Sweeping Trip
is a committed low horizontal sweep across the front, in either direction.
Driving Jabs is two quick forward thrusts with retraction between them. Return
to neutral before repeating. No physical full-body turn or floor contact is
required. The detector uses both hands' midpoint in a fixed initial yaw frame;
head translation, pose jumps, frame gaps, lost support/tracking, equipment
changes and combat-blocking UI cancel incomplete gestures. Ordinary trigger-held
attacks remain available. Completed gestures cannot also produce a normal hit.

Whirlwind is the Master Pikeman ultimate in the polearm ultimate row. Equip it
with one click, support the weapon with both hands, release both triggers, then
press both within 120 ms. It attacks a server-selected circular group and needs
no client-selected actor. An empty area is rejected without SAC/cooldown cost.
Holding both triggers cannot repeat it. A single main trigger returns to normal
attack input after the chord window. Overhead Whirl's circle is distinct from
Warcry's vertical pump and Swordsman's downward strike.

### TKA Force of Will

Force of Will is support in the gesture row, not a positional or ultimate slot.
It requires Master Meditative Techniques, Novice TKA and a certified unarmed
weapon. While incapacitated, release then hold the offhand stick: normal recovery
starts after one second; keep holding for three seconds total for Force of Will.
Release sooner to keep ordinary recovery. Tracking loss or rejection requires a
fresh release, and only a server-confirmed recovery restores movement.

Force of Will recovers at least 15% of wound-adjusted maximum Health and has a
persistent ten-minute cooldown. It cannot resurrect, treat wounds/fatigue, refill
Action/Mind or remove threat. Meditate and Power Boost are retired; there is no
Second Wind replacement. Indomitable Focus remains the equipped TKA ultimate.

### Physical accuracy and Marksman targeting

Player hit accuracy follows physical aim/contact, with no additional innate
hit/miss roll. Normal dodge, block, counter and deflection remain; active guarding
and moving out of range/trajectory provide additional protection. Armour and
status-effect resistance still resolve separately. Accuracy ratings affect enemy
attack rolls, not player damage or contact size.

Aim is removed from the proposed support row: steady physical aiming already
serves its purpose. Original grip/range and pose damage bonuses remain, and
movement adds class-dependent projectile spread. Point Blank Shot is not a candidate solely to overcome an
innate accuracy penalty. Suppression Fire, merged Warning/Threaten Shot, Controlled Burst and Bleeding
Shot are implemented by patch `0100-marksman-vats.patch`.


The equipment hologram lists the learned, compatible attacks in the normal
four-slot row. Weapon-stick click opens the local target markers; shoot one to
invoke its bound ability. Lethal Shot remains available at Master Marksman.
Marksman has no ultimate.

| Ability | Marker | Training / weapon | Effect |
| --- | --- | --- | --- |
| Suppression Fire | Weapon arm | Support IV / ranged | Light hit, resisted -20 enemy accuracy for up to 6 seconds. |
| Warning Shot | Feet | Support I / ranged | Merged Threaten/Warning: resisted 2-second attack hesitation, improved to 3 at Support III. Preserves threat; bosses immune. |
| Controlled Burst | Torso | Carbine II / carbine | One aimed contact resolves three 0.65x native hits. Each keeps normal defenses. |
| Bleeding Shot | Abdomen | Pistol IV / pistol | 0.8x hit plus a resisted bleed budget of 30% of landed Health damage. |

Control markers disappear during shared control recovery. Warning also observes
native attack-delay recovery. Native per-target eligibility hides immune targets,
including droids for Bleeding Shot. Costs, equipment, certification, cooldown and
current grip-adjusted range filter markers and launch requests. Target changes
during flight can prevent an effect; the committed launch still costs resources.

## Pistoleer: mobile pressure, fanning and stance buff

Pistols add no movement spread. Moving still requires physical aim and obeys
weapon range, armour and secondary defenses. Pistoleer supplies single-target
pressure and damage suppression, with Fan Shot as its only damaging area attack.
The recommended four-slot loadout is optional; other learned compatible pistol
attacks, including implemented Smuggler attacks, can replace individual entries.
Pistoleer training also supplies these gestures to Bounty Hunter pistol builds.

| Ability | Marker | Training | Purpose |
| --- | --- | --- | --- |
| Double Tap | Chest | Pistol Techniques II / `doubleTap` | One aimed contact resolves two 0.8x hits; 60 Action / 20 Mind, 12 s cooldown. |
| Disarming Shot | Weapon arm | Pistol Techniques I / `disarmingShot1` or higher | Light 0.5x hit and resisted 20% lower enemy attack damage, up to 6 s; 45 / 20, 18 s cooldown. No weapon removal. |
| Bleeding Shot | Abdomen | Novice Pistoleer / `healthShot2` | Upgrades the Marksman slot to a 1.0x hit and 40% landed-damage bleed budget, up to 12 s; same 50 / 20 cost, 16 s cooldown and shared bleed channel. |
| Warning Shot | Feet | Existing Marksman Support grants | Existing resisted 2–3 s attack hesitation and shared recovery. |

Fan Shot is a learned gesture from Pistol Techniques IV (`fanShot`). Hold the
pistol normally and make two quick cock-fanning strokes with the free offhand
above its rear/top. Keep the offhand grip and both triggers released. Movement
is measured relative to the pistol, so locomotion alone cannot fan it. One
completed gesture attacks up to five eligible enemies in a 60-degree muzzle cone,
within the shorter of 12 m and the current one-handed pistol range. It costs
80 Action / 25 Mind with a 16 s cooldown, uses normal defenses and line of sight,
and adds no statuses. It needs neither a targeting slot nor an ultimate slot.

Run and Gun is a separate learned gesture from Pistol Stances II. With triggers
released, deliberately hold either pose for approximately 0.8 seconds:

- **Bond stance:** pistol held low near the hip, free arm extended sideways.
- **Gangster stance:** pistol held around shoulder height and rolled sideways,
  with the free hand clear of the weapon.

The confirmation haptic marks activation; leave the pose and move freely.
Both poses share the same buff and cooldown. Holding the pose or changing from
one pose to the other cannot refresh it; leave the recognized stance before
rearming. Recognition mirrors for left-handed controls and uses head-relative
height so seated play does not require standing. The 8 s buff costs 80 Action /
40 Mind and has a 60 s cooldown. Ordinary pistol firing is 25% faster, and
regular single-target pistol specials cost 25% less Action/Mind. Fan Shot and
ultimates retain their costs and timing. The weapon's normal cooldowns remain.
The stance buff has a short 0.25 s activation recovery before firing resumes.

Showdown is the Master Pistoleer ultimate. Select it in the pistol ultimate row,
aim at one opponent, support the pistol and press both triggers together.
Three independently aimed 0.9x projectiles launch at least 0.25 s apart; each follows the
current muzzle and requires contact with that same opponent. The offhand can
release the support after activation. A damaging contact attempts 30% lower
enemy attack damage for up to 5 s before resistance, only once per volley;
strongest damage suppression wins. Costs are paid once: 150 Action / 75 Mind,
with a 120 s cooldown. It has no splash or target hopping. Interrupted or missed
volleys do not refund committed resources or cooldown.
The next shot waits for the previous launch acknowledgment, so network latency
can extend the interval or expire an unfinished volley.

All gestures require learned training and a held, certified, usable pistol.
They remain available to combined builds that also train Pistoleer, independently
of which compatible ultimate or four targeted attacks are selected. Tracking
loss, equipment changes, menus and competing combat input cancel recognition.

The existing client magazine/reload system spends two rounds for Double Tap and
three for Fan Shot. Showdown requires three rounds available at activation, then
spends one per projectile actually launched. A confirmed failed launch restores
its reserved rounds; missed or failed impacts keep them spent. This does not add
a persistent native ammunition model. Core3 owns Action/Mind costs, cooldowns,
damage and effects.

This describes the implemented local input and protocol. Automated validation
does not establish live headset rendering or the feel of these gestures.

## Carbineer: ranged control, sweep and brace

Carbineer training adds reusable ranged control to combined professions. The
recommended four-slot VATS loadout below remains optional. Existing Controlled
Burst can replace Wild Shot when more single-target damage is useful.

| Ability | Marker | Training | Purpose |
| --- | --- | --- | --- |
| Crippling Shot | Knee | Carbine Marksmanship III / `cripplingShot` | 0.6x damage and resisted 40% slow for up to 6 s; 55 Action / 20 Mind, 16 s cooldown. |
| Wild Shot | Head | Assault Tactics II / `wildShot1` | 0.7x damage and resisted native Stun for up to 3 s; 60 / 25, 18 s cooldown. Assault Tactics IV improves effect application chance. |
| Suppression Fire | Weapon arm | Counterinsurgency IV / `suppressionFire2` | Existing slot and cooldown; with a carbine, 0.5x damage and resisted -25 enemy accuracy for up to 6 s; 45 / 15, 18 s cooldown. Unlocks without Marksman Support. |
| Charge Shot | Pelvis | Special Abilities II / `chargeShot1` or higher | 0.8x damage and resisted knockdown for up to 2 s; 75 / 30, 24 s cooldown. |

**Full Auto Sweep** comes from Special Abilities I (`fullAutoArea1`, or its
higher source rank). Hold both grips with triggers released. Deliberately sweep
the supported carbine horizontally, reverse, return forward and briefly settle.
The final muzzle points into a 75-degree cone, reaching the shorter of 18 m and
supported weapon range. Up to five eligible enemies receive 0.5x damage and
an individual resisted 35% slow for up to 4 seconds. The attack costs 90 Action /
30 Mind, three magazine rounds and a 20 s cooldown. It uses native line of sight
and normal defenses; the swept path itself does not deal damage.

**Tactical Brace** is a new gesture unlocked at Counterinsurgency II. Keep both
grips held and triggers released. Start with the carbine level, cant it into a
chest-height ready pose, hold for approximately 0.8 seconds, then return level.
The confirmation haptic marks activation; normal aiming and movement can resume.
For 8 seconds, carbine control effects gain +10 percentage points application
potency before resistance, capped at 95% final chance. The buff costs 50 Action / 25 Mind with
a 60 s cooldown, a 0.25 s activation recovery and no ammunition cost. It does not
change movement spread, damage, effect duration, immunity or control recovery.
Holding the stance cannot refresh it.
Its chance bonus applies to Carbineer controls and Marksman Suppression Fire and
Warning Shot fired with a carbine. It does not change legacy Smuggler formulas.

Both gestures appear in the gesture row and take no VATS or ultimate slot. They
remain available in combined professions that train Carbineer, even with another
compatible ultimate selected. They require a certified usable carbine and
neutral rearming; handedness is mirrored and height is relative to the headset
for seated play. Tracking loss, equipment changes, menus and competing combat
input cancel recognition. Forward Check is excluded.

**Charge Blast** is the Master Carbineer ultimate. Select it in the carbine
ultimate row, support the weapon and press both triggers together. A VATS target
is unnecessary: the actual muzzle defines a 90-degree cone, reaching the shorter
of 20 m and supported weapon range. Up to six eligible enemies each receive
0.75x damage and a resisted knockdown for up to 3 seconds. It costs 150 Action /
80 Mind, three magazine rounds and a 120 s cooldown. It has no physical knockback.

Carbines retain their 1.2-degree movement-spread cap and existing grip/range
behavior. Stun weakens combat effectiveness rather than freezing movement.
Controls retain resistance and immunity. Hard-control attempts and Suppression
Fire retain shared recovery; resisted attempts also spend that recovery window.
Slows use the strongest active value. A cone can deal
damage even when a recipient is protected from its control effect. Accepted
empty-cone activations still spend resources and ammunition.
The three new VATS attacks also retain their damage against eligible targets
whose control effect is immune or recovering. Existing Suppression Fire keeps
its control-availability filtering.

These are local implementation controls and tuning; automated checks do not
establish live headset rendering or gesture comfort.

## Rifleman: heavy single-target fire and bolting Focus

Rifleman concentrates damage on one opponent. The recommended four-slot VATS
loadout remains optional and can be mixed with other learned rifle abilities.
Rifles preserve their existing movement spread, supported range and physical
posture benefits.

| Ability | Marker | Training | Purpose |
| --- | --- | --- | --- |
| Head Shot | Head | Novice Rifleman / `headShot2`; improved at Sniping II / `headShot3` | Upgrades the existing Lethal Shot slot and cooldown to 4.0x / 4.25x damage; 110 Action / 40 Mind, 30 s cooldown. |
| Piercing Shot | Chest | Sniping I / `mindShot2` | 2.0x damage with current Kinetic/Energy body resistance halved for this hit; 75 / 30, 18 s cooldown. |
| Flurry Shot | Abdomen | Rifle Abilities I / `flurryShot1`; improved at III / `flurryShot2` | Three physical projectiles at the same target for 0.8x / 0.9x each; 100 / 35 once, 18 s cooldown. |
| Surprise Shot | Shoulder | Sniping III / `surpriseShot` | 2.0x damage, increased to 3.0x at or above 80% effective target Health at impact; 80 / 35, 24 s cooldown. |

Head Shot shares the original `lethal_shot` ID, preventing a second heavy-shot
slot or independent cooldown. With a qualified rifle, Rifleman training unlocks
it independently of Master Marksman. Other weapon families retain their existing
Lethal Shot behavior and heart marker; the rifle upgrade moves its marker to the
head. Piercing Shot does not leave an armour debuff, and Surprise
Shot does not require stealth. The markers select abilities rather than adding
a separate anatomical critical-hit system.

**Flurry Shot** uses three separate aimed launches. Keep the same target in your
physical aim through the volley; each projectile needs its own contact and
normal defenses apply. The client waits for the preceding launch receipt and
at least 0.25 seconds before the next shot. Native target, weapon and loadout
binding prevent retargeting; network delay can lengthen or interrupt the short
sequence. Three rounds must be available at activation, then one is spent per
launched projectile. Misses and interruptions do not refund accepted shots.
Flurry adds no area damage or Showdown suppression.

**Rifleman's Focus** is a new slot-free gesture unlocked at Concealment II.
Start with the rifle supported and both triggers released. Release the offhand
from the fore-end and bring it beside the receiver. Squeeze that hand's grip,
pull back and push forward in a deliberate bolting motion, then release and
return to the fore-end with a fresh supporting grip. Keep the weapon hand's grip
held throughout. The buff activates only after the supported grip is restored.
It lasts eight seconds and increases ordinary rifle fire and compatible regular
rifle-special damage by 20%. Ultimates receive no damage bonus. Activation costs
50 Action / 25 Mind with a 60-second cooldown, 0.25-second recovery and no
ammunition; it is not a reload. Each projectile captures the buff at launch.
A static stance or canted hold does not activate Focus.

Focus appears in the gesture row and uses no VATS or ultimate slot. Combined
professions retain it with the required Rifleman training and a certified usable
rifle, even with another compatible ultimate selected. The motion mirrors with
handedness, works relative to the rifle for seated play and must be repeated
deliberately after rearming. Tracking loss, discontinuous controller movement,
equipment changes, menus and competing input cancel recognition. Animation never
drives the tracked head or hands.

**Sniper Shot** is the Master Rifleman ultimate, also requiring the native
Sniper Shot grant. Select it in the rifle ultimate row, aim at one eligible
opponent, support the rifle and press both triggers together. It launches one
6.0x physical projectile for 150 Action / 90 Mind and one round, with a
120-second cooldown and normal weapon recovery floored at 2.5 seconds. Eligible
bosses retain normal damage resolution. The original incapacitated-target
deathblow and pool-specific damage are not used.

This describes the local implementation. Automated input and routing checks do
not establish live headset rendering or the comfort of the bolting motion.
The bolting gesture passes 30 checks and production gameplay routing passes 77;
the complete client regression set passes 660 checks across 12 headless suites.
See `runtime/evidence/rifleman/validation.json` for the consolidated native,
protocol, client and actual-stage movement evidence. No VR launch was performed.
