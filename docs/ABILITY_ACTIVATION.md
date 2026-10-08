# Ability activation audit

Audited against the working client and native command adapters on 2026-10-08.
This records implemented player-facing actions, not every command inherited
from Core3. A controller button or selecting a holographic option is not a
dedicated body/hand gesture. Physical tool contact is distinguished below.

## Primary actions without a dedicated gesture

| Profession/system | Abilities/actions | Current activation |
| --- | --- | --- |
| Medic | Tend Damage, Quick Heal | Accepted tool triggers: aim the medical focus and tap/release for Tend Damage; hold trigger 0.65 seconds for Quick Heal. The hold fires once without first casting Tend Damage. No circle selection needed. |
| Medic / Doctor / Combat Medic | Stims, Health Wound Medpacks, cures, state packs, enhancements, resuscitation | Hold the actual supply against an eligible patient and trigger. Ranged stims can be aimed; native skill, consent, recovery and location rules apply. |
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
focus abilities plus held medical supplies, including Doctor resuscitation; the entire Combat Medic command tree is not exposed.

Pet stims, droid damage kits and Droid Engineer reconstruction kits also use held-item contact/trigger treatment on the existing companion model. Their native recipient type, supply, resource and recovery checks remain authoritative.

## Combat ability equipment

Each weapon family has four combat slots and one selected ultimate. While the
equipment hologram is open, click the **physical right stick** (also when using
left-handed weapon controls) to expand the ability editor. The four slots appear
above the avatar, learned compatible abilities fill the left grid, and pointing
at one shows its description in the right pane. Grip-drag an ability into a slot;
dragging between slots swaps them. Drag an equipped slot back to the grid to
clear it. Confirmed occupied slots draw lines to their activation body parts.

Ultimates occupy a separate row in the left grid. Click with the pointing-hand
trigger to select one; clicking it again clears the selection. The pointing hand
is the weapon hand. Stick up/down pages large catalogs. Right-stick click returns
to equipment. Tracking loss or dropping outside a destination cancels the drag.

Core3 confirms and persists these choices per character and weapon family. Only
equipped abilities can produce target markers or respond to the ultimate chord;
normal cooldown, resource, weapon, range and target checks still apply. New family
loadouts are empty. The current native melee catalog has no specials, so its
four-slot editor is present but does not show fabricated choices.
