# Ability activation audit

Audited against the working client and native command adapters on 2026-10-08.
This records implemented player-facing actions, not every command inherited
from Core3. A controller button or selecting a holographic option is not a
dedicated body/hand gesture. Physical tool contact is distinguished below.

## Primary actions without a dedicated gesture

| Profession/system | Abilities/actions | Current activation |
| --- | --- | --- |
| Scout | Mask Scent | Empty-hand circle selection, then A. |
| Medic | Heal Damage, Heal Wound, Tend Damage, Tend Wound, First Aid, Quick Heal | Draw the medical focus; choose an ability in its offhand circle, aim and press trigger. |
| Entertainer, Dancer, Musician | Flourishes, including learned special effects | A during a performance chooses a random learned flourish. |
| Image Designer | Start Image Design | Circle menu, then recipient/options/consent panels. |
| Creature Handler and droid pets | Learned pet commands and command training | Trigger over the pet opens its circle; select a command, then trigger, aiming at a target when required. Calling uses the datapad. |
| Marksman and Smuggler | Lethal Shot, Last Ditch, Low Blow, Restraining Shot, Concussion Shot Improved | Shared circle selection and A to arm; the next ranged attack consumes the ability. These have no individual gesture; the Smuggler flow matches the requested marksman activation. |

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

Gesture paths already exist for Brawler Taunt (chest beats), Feign Death
(posture), Burst Run (arm strokes), Forage (digging), creature inspection
(pondering pose and gaze), Rescue (two-finger pointing), Area Track (hand over
eyes and head sweep), taming (clap/beckon), Embolden and Enrage (fist poses),
mount training (head stroking), dancing/instrument performance, performance
location registration (raised-arm hold), and band joining (thumbs-up).
Medical dragging and pet recovery also use tracked hand contact.

See [client controls](../client/README.md), [Smuggler](SMUGGLER.md),
[creature gestures](../client/pets/creature_handler.gd),
[Scout gestures](../client/scout/gestures.gd), and
[performance gestures](../client/entertainment/gestures.gd).

Start/Leave Band, Stop Performance, and Leave Party are management menu actions.
Fist-bump party formation is implemented separately from performance bands.

Melee Assault remains a local profession-lab translation; it is not a missing
gesture on an enabled native melee special. Likewise, inherited advanced
profession command definitions do not imply a supported client action. Their
remaining ability design and Doctor/buff redesign are deferred in
[CoreCU scope](CORECU_COMBAT.md). The native medical interface above exposes six
abilities; it does not expose Doctor resurrection or the entire Combat Medic
command tree.
