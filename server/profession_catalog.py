"""Read-only original profession graphs. Learned state comes from owner CREO1."""
from functools import lru_cache
import hashlib
from .character_protocol import assets
from character_formats import datatable
from stf import string_table
from .corecu_professions import contribution, trap_bonus_contribution


@lru_cache(maxsize=1)
def catalog():
    sources = {}
    def read(path):
        raw = assets().read(path)
        sources[path] = hashlib.sha256(raw).hexdigest()
        return raw
    rows = datatable(read('datatables/skill/skills.iff'))
    names = string_table(read('string/en/skl_n.stf'))
    descriptions = string_table(read('string/en/skl_d.stf'))
    professions = []
    warnings = []
    by_id = {row['NAME']:row for row in rows}
    def profession_parent(skill):
        parent = skill['PARENT']
        seen = set()
        while parent in by_id and parent not in seen:
            seen.add(parent)
            if by_id[parent]['IS_PROFESSION']: return parent
            parent = by_id[parent]['PARENT']
        return ''
    all_labels = {row['NAME']:names.get(row['NAME'], row['NAME']) for row in rows}
    for row in rows:
        if not row['IS_PROFESSION'] or row['IS_HIDDEN'] or row['GOD_ONLY']: continue
        nodes = []
        for skill in rows:
            if profession_parent(skill) != row['NAME'] or skill['IS_HIDDEN'] or skill['GOD_ONLY']: continue
            mods = {}
            for mod in filter(None, skill['SKILL_MODS'].split(',')):
                if mod.count('=') != 1:
                    warnings.append({'skill':skill['NAME'], 'field':'SKILL_MODS', 'raw':mod,
                                     'reason':'Malformed source modifier; not guessed'})
                    continue
                key, value = mod.split('=')
                mods[key] = int(value)
            resistance = contribution(row['NAME'], skill['NAME'])
            description = descriptions.get(skill['NAME'], '')
            if skill['NAME'].startswith('combat_unarmed_'):
                description = all_labels[skill['NAME']] + ': CoreCU unarmed tank progression, area threat and trained defensive passives.'
            if row['NAME'] in ('science_medic','science_doctor','science_combatmedic'):
                description=all_labels[skill['NAME']]+': CoreCU medical progression. Health is the damage and wound pool; Action and Mind are ability resources.'
                if row['NAME']=='science_combatmedic':
                    description+=' Poison deals bounded Health damage over time; disease applies temporary Action pressure. Both use a held Doctor tool aimed at a hostile target, with explicit single-target or area pack selection. Combat Medic has the strongest trained debuff application: raw potency up to 125 before resistance, with up to 30% longer authored duration. Each effect uses one shared channel, and area delivery affects at most six enemies. Both cost 6% Action/8% Mind and share recovery. Double-tap the held Doctor tool within 0.30 seconds for Heal Mind: transfer up to 12–22% of another friendly player or organic pet’s effective Mind, paying the amount actually restored plus 6% Action. Single tap requests Tend Damage; a 0.65-second hold requests Quick Heal. No Heal Mind selection is needed.'
                if row['NAME']=='science_combatmedic':
                    description+=' Ranged stim tiers A–E heal 10–14%, 13–17%, 16–20%, 19–23% and 22–26% effective Health at full Combat Medic proficiency; area tiers A–C heal 6–8%, 8–10% and 10–12% per patient, at most five patients. All share injury recovery and cost 6% Action/8% Mind. Original poison/disease pool variants with no CU role remain retired; 26 useful recipes remain. No Combat Medic ultimate is enabled.'
                if row['NAME']=='science_doctor':
                    description+=' Doctor is a care and preparation profession with no ultimate. Novice Doctor and each Wound Treatment box add 5% ordinary stim and Tend Damage potency; Master Doctor adds another 5%, to 30%. Quick Heal receives half this bonus, to 15%. Wound Medpacks retain 10% per Novice/Wound box, to 50%. Ranged and area stims use Combat Medic proficiency and do not receive Doctor’s direct-heal multiplier.'
                    description+=' Vitality increases maximum Health, Endurance increases maximum Action, and Metabolic increases existing natural regeneration. Each patient can have one general preparation and one poison/disease prophylaxis; replacing either does not refill pools. General tiers A/B/C/D provide 5–8%, 7–10%, 9–12% and 11–15% before battle fatigue. Prophylaxis A/B/C adds 10–15, 15–20 and 20–25 rating after native/profession resistance is compared, with tier C absorption capped at 10%.'
                    description+=' With learned commands and actual supplies, revive by a two-hand pad press and extinguish fire by a blanket sweep and pat. Heal State uses friendly anatomical markers only while the Doctor tool is held: click its stick while aiming at a friendly patient, then aim at the condition marker and trigger. Stowing the tool or losing tracking closes friendly VATS.'
                    doctor_recipes={
                        'science_doctor_support_01':'Vitality A and Endurance A',
                        'science_doctor_support_02':'Vitality B, Endurance B and Metabolic A',
                        'science_doctor_support_03':'Vitality C, Endurance C, Metabolic B and poison/disease prophylaxis A',
                        'science_doctor_support_04':'Vitality D, Endurance D, Metabolic C and poison/disease prophylaxis B',
                        'science_doctor_master':'Metabolic D and poison/disease prophylaxis C'}
                    if skill['NAME'] in doctor_recipes:
                        description+='\nPreparation recipes: '+doctor_recipes[skill['NAME']]+'. Existing relevant cure, state, wound, stim, resuscitation and fire-blanket recipes remain.'
                if skill['NAME']=='science_medic_novice':
                    description='Medic training enables held stim treatment and medical crafting. Apply stims to injured patients and Health Wound Medpacks to wounds; Diagnose and separate Heal/Tend Wound abilities are retired.'
                if row['NAME'] in ('science_medic','science_doctor'):
                    description+='\nOrdinary crafted stim tiers A–E heal 10–14%, 13–17%, 16–20%, 19–23% and 22–26% of effective maximum Health at full treatment proficiency, before Doctor bonuses, battle fatigue and spice effects. Crafting quality is normalized within each tier. Heal Damage costs 6% base Action and 8% base Mind per successful use; ranged/area stims share these costs.'
                if any(mods.get(key,0) for key in ('healing_injury_speed','healing_wound_speed','healing_range_speed')):
                    description+='\nCoreCU medical recovery: relevant speed rating reduces recovery by up to 25% at 100 rating. Injury/ranged speed uses the stronger rating for Heal Damage; wound speed improves Wound Medpack and enhancement recovery.'
                if mods.get('healing_wound_treatment',0):
                    description+='\nCoreCU Wound Medpacks: treatment proficiency increases base wound repair from 3% to 8%, modified by pack quality and capped at 10% per use before spice effects and battle fatigue. Doctor training multiplies output and raises that cap progressively to 15%.'
            if row['NAME'] in ('social_entertainer','social_dancer','social_musician'):
                description=description.replace('mind wounds','Health wounds').replace('Mind wounds','Health wounds').replace('mental wounds','Health wounds')
                description+='\nCoreCU performance treats Health wounds and battle fatigue; original mental-healing ratings continue to determine proficiency and inspiration.'
            if resistance:
                description += '\nCoreCU resistance progression: ' + ', '.join(f'{name.title()} +{value:g}' for name, value in resistance.items()) + ' rating. Strongest profession plus 25% of other contributions; native/profession baseline capped at 100. Doctor prophylaxis adds separately. Rating 100 reduces status chance and duration by 40%; immunity remains separate.'
            trap_bonus = trap_bonus_contribution(skill['NAME'])
            if trap_bonus:
                description += f'\nCoreCU traps: +{trap_bonus} points of status potency before resistance, capped at 95% final chance; enemy duration resistance remains.'
            if skill['NAME'] == 'combat_brawler_novice':
                description += '\nTaunt: clench a free hand with grip and beat your chest twice while aiming the head reticle at an enemy. Keep trigger released; the first eligible enemy in the reticle is challenged.'
            if skill['NAME'] in ('combat_brawler_novice','combat_brawler_master'):
                description += '\nWarcry replaces separate Warcry and Intimidate: find it in the gesture ability row; raise the held weapon above your head and pump it upward, with no targeting slot required. Enemies in a forward cone suffer a brief attack delay and reduced damage. Master Brawler improves durations.'
            marksman_abilities = {
                'combat_marksman_support_01': 'Warning Shot merges Threaten Shot: target the feet for a light hit and resisted 2-second attack hesitation. Preserves threat; bosses immune. Equip in a ranged targeting slot.',
                'combat_marksman_support_03': 'Warning Shot now causes up to 3 seconds of attack hesitation before resistance. It remains one ability and uses shared control recovery.',
                'combat_marksman_support_04': 'Suppression Fire: target the weapon arm for a light hit and -20 enemy accuracy for up to 6 seconds before resistance. Single target; shared control recovery.',
                'combat_marksman_carbine_02': 'Controlled Burst replaces Full Auto Single: one aimed carbine contact resolves three 0.65x hits with normal defenses. Costs 75 Action and 20 Mind once; no blind/dizzy/stun bundle.',
                'combat_marksman_pistol_04': 'Bleeding Shot: target the abdomen with a pistol. Bleed budget is 30% of landed Health damage, at most 12 seconds; one shared non-stacking Fencer bleed channel. Droids immune.',
                'combat_marksman_master': 'Lethal Shot remains the heavy single-target Marksman attack. Marksman grants no ultimate; ultimates require an advanced profession.'}
            if row['NAME'] == 'combat_marksman':
                description = all_labels[skill['NAME']] + ': CoreCU ranged progression. Physical aiming determines player contacts; server resolves damage and normal dodge/block. Accuracy ratings affect enemy attacks only.'
                description += ' Existing grip/range and pose damage bonuses remain. Equip up to four weapon-family abilities through the equipment hologram; click the weapon stick and shoot an eligible anatomical marker.'
                if skill['NAME'] in marksman_abilities:
                    description += '\n' + marksman_abilities[skill['NAME']]
            pistoleer_abilities = {
                'combat_pistol_novice': 'Bleeding Shot upgrades the existing Marksman abdomen ability to a 1.0x hit and a bleed budget of 40% of landed Health damage, at most 12 seconds. The same slot, 16-second cooldown and shared non-stacking bleed channel remain; droids are immune.',
                'combat_pistol_ability_01': 'Disarming Shot: target the weapon arm for a light hit and 20% lower enemy attack damage for up to 6 seconds before resistance. No weapon removal; the strongest damage suppression wins. 18-second cooldown.',
                'combat_pistol_ability_02': 'Double Tap: target the chest with one aimed contact for two 0.8x damage resolutions against that opponent, each with normal defenses. Costs 60 Action and 20 Mind once; 12-second cooldown.',
                'combat_pistol_ability_04': 'Fan Shot: with a held pistol, fan the free open offhand twice above its rear/top while both triggers are released. The sole Pistoleer damaging area attack hits up to five enemies in a 60-degree cone, within 12 metres or the current one-handed pistol range. Gesture row only; 16-second cooldown.',
                'combat_pistol_support_02': 'Run and Gun: hold a low hip-fire pistol with the free arm extended sideways, or a high sideways-canted pistol with the free hand clear, for 0.8 seconds with both triggers released. Both poses activate the same 8-second buff: 25% faster ordinary pistol firing and 25% cheaper regular single-target pistol specials. Fan Shot and ultimates are excluded. Leave the pose before rearming; 60-second shared cooldown.',
                'combat_pistol_master': 'CoreCU ultimate: Showdown. Equip in the pistol ultimate slot, aim at one opponent, support the pistol and press both triggers together. Three separately aimed 0.9x shots at 0.25-second spacing retain physical contact and normal defenses. The first damaging contact attempts 30% lower enemy attack damage for up to 5 seconds before resistance, once per volley. Costs 150 Action and 75 Mind once; 120-second cooldown. Disarming Shot remains one ability regardless of native rank.'}
            if row['NAME'] == 'combat_pistol':
                description = all_labels[skill['NAME']] + ': CoreCU mobile pistol pressure and damage suppression. Pistols add no movement spread; physical aim, range, armour and secondary defenses remain.'
                description += ' Four optional targeting slots and one selected ultimate are shared with other learned compatible pistol abilities. Learned Fan Shot and Run and Gun need no slots and remain available to mixed Smuggler or Bounty Hunter builds.'
                if skill['NAME'] in pistoleer_abilities:
                    description += '\n' + pistoleer_abilities[skill['NAME']]
            carbineer_abilities = {
                'combat_carbine_novice': 'Recommended targeting loadout when learned: Crippling Shot at the knee, Wild Shot at the head, Suppression Fire at the weapon arm and Charge Shot at the pelvis. Existing Controlled Burst remains a damage alternative. Source Action-pool damage and duplicate attack ranks do not add separate abilities.',
                'combat_carbine_speed_03': 'Crippling Shot: one knee contact for 0.6x damage and a resisted 40% movement slow for up to 6 seconds. Strongest active slow wins; 55 Action / 20 Mind, 16-second cooldown.',
                'combat_carbine_accuracy_02': 'Wild Shot: one head contact for 0.7x damage and up to 3 seconds of resisted native Stun. Stun weakens combat effectiveness; it does not freeze movement. 60 Action / 25 Mind, 18-second cooldown.',
                'combat_carbine_accuracy_04': 'Wild Shot improves base effect application chance from 85% to 90% before resistance. The same targeting slot, damage, duration and cooldown remain.',
                'combat_carbine_ability_02': 'Tactical Brace: with both grips held and triggers released, move from level into a chest-height canted ready pose, hold for 0.8 seconds, then return level. New gesture unlock at Counterinsurgency II; 8 seconds of +10 percentage points effect application for Carbineer controls and Marksman Suppression Fire/Warning Shot fired with a carbine, before resistance and capped at 95% final chance. Legacy Smuggler formulas, immunity and recovery remain. Costs 50 Action / 25 Mind; 60-second cooldown.',
                'combat_carbine_ability_04': 'Suppression Fire unlocks independently of Marksman Support and upgrades the existing weapon-arm ability with a carbine: 0.5x damage and -25 enemy accuracy for up to 6 seconds before resistance. Same ability slot and 18-second cooldown; 45 Action / 15 Mind.',
                'combat_carbine_support_01': 'Full Auto Sweep: with both grips held and triggers released, sweep the carbine sideways, reverse, return forward and settle. Attacks up to five enemies in a 75-degree final-muzzle cone, within 18 metres or supported weapon range: 0.5x damage and resisted 35% slow for up to 4 seconds. Gesture row only; 90 Action / 30 Mind, 20-second cooldown.',
                'combat_carbine_support_02': 'Charge Shot: one pelvis contact for 0.8x damage and resisted knockdown for up to 2 seconds. 75 Action / 30 Mind, 24-second cooldown; shared hard-control recovery applies.',
                'combat_carbine_support_03': 'Full Auto Sweep remains one learned gesture, with the same target cap, slow, costs and cooldown; native attack ranks do not create parallel area attacks.',
                'combat_carbine_support_04': 'Charge Shot remains one targeted knockdown ability. Charge Blast adapts the source cone-knockdown concept into the separate Master Carbineer ultimate.',
                'combat_carbine_master': 'CoreCU ultimate: Charge Blast. Select in the carbine ultimate row, support the weapon and press both triggers together; no bound target required. Up to six enemies in a 90-degree final-muzzle cone, within 20 metres or supported weapon range, receive 0.75x damage and individual resisted knockdown for up to 3 seconds. 150 Action / 80 Mind, 120-second cooldown.'}
            if row['NAME'] == 'combat_carbine':
                description = all_labels[skill['NAME']] + ': CoreCU ranged crowd control at medium range. Carbines retain their 1.2-degree movement-spread cap, physical contact, normal armour and secondary defenses.'
                description += ' Four optional targeting slots and one selected ultimate are shared with learned compatible carbine abilities. Full Auto Sweep and Tactical Brace take no slots and remain available in combined professions with a different ultimate selected. Control effects retain resistance and immunity. Hard-control attempts and Suppression Fire retain shared eight-second recovery; strongest movement slow wins.'
                if resistance:
                    description += '\nCoreCU resistance progression: ' + ', '.join(f'{name.title()} +{value:g}' for name, value in resistance.items()) + ' rating. Strongest profession plus 25% of other contributions; native/profession baseline capped at 100. Doctor prophylaxis adds separately. Rating 100 reduces status chance and duration by 40%; immunity remains separate.'
                if skill['NAME'] in carbineer_abilities:
                    description += '\n' + carbineer_abilities[skill['NAME']]
            rifleman_abilities = {
                'combat_rifleman_novice': 'Head Shot upgrades the existing Lethal Shot slot and cooldown with a rifle and moves its marker to the head: 4.0x single-target Health damage, 110 Action / 40 Mind, 30-second cooldown. Unlocks independently of Master Marksman through the native Head Shot grant. Recommended targeting loadout when learned: Head Shot, Piercing Shot, Flurry Shot and Surprise Shot.',
                'combat_rifleman_accuracy_01': 'Piercing Shot: one chest contact for 2.0x Health damage, with current Kinetic/Energy body resistance halved for this hit. No persistent armour debuff; 75 Action / 30 Mind, 18-second cooldown. Adapts the native Mind Shot II grant without Mind-pool damage.',
                'combat_rifleman_accuracy_02': 'Head Shot improves to 4.25x damage through the native Head Shot III grant. It retains the same Lethal Shot ID, targeting slot, costs and 30-second cooldown; the head marker selects the ability rather than introducing a separate anatomical critical-hit system.',
                'combat_rifleman_accuracy_03': 'Surprise Shot: one shoulder contact for 2.0x damage, increased to 3.0x when the target has at least 80% effective Health at impact. No stealth requirement; 80 Action / 35 Mind, 24-second cooldown.',
                'combat_rifleman_accuracy_04': 'The native Sniper Shot grant contributes to the Master Rifleman ultimate unlock. SWGXR uses a normal single-target Health damage projectile, not the legacy incapacitated-target deathblow.',
                'combat_rifleman_speed_02': "Rifleman's Focus: start supported with both triggers released, release the offhand from the fore-end, grasp beside the receiver, pull back and push forward in a deliberate bolting motion, then release and regrip the fore-end. New gesture unlock at Concealment II: 8 seconds of +20% damage to ordinary rifle fire and compatible regular rifle specials. Ultimates are excluded. Costs 50 Action / 25 Mind, no ammunition, 60-second cooldown; no targeting or ultimate slot required.",
                'combat_rifleman_support_01': 'Flurry Shot: target the abdomen, then launch three separately aimed physical projectiles at the same opponent, each for 0.8x damage with normal defenses. Costs 100 Action / 35 Mind once, 18-second cooldown; 0.25-second minimum spacing. Misses and interruptions do not refund accepted launches; no area effect.',
                'combat_rifleman_support_03': 'Flurry Shot improves each of its three physical projectiles to 0.9x damage. Same target binding, ability slot, resources and cooldown; source ranks do not create parallel volleys.',
                'combat_rifleman_master': 'CoreCU ultimate: Sniper Shot. Select in the rifle ultimate row, aim at one opponent, support the rifle and press both triggers together. One physical projectile deals 6.0x damage with normal defenses; eligible bosses are valid targets. Costs 150 Action / 90 Mind, 120-second cooldown, normal weapon recovery with a 2.5-second minimum. Requires the original Sniper Shot grant.'}
            if row['NAME'] == 'combat_rifleman':
                description = all_labels[skill['NAME']] + ': CoreCU dedicated single-target heavy rifle damage. Rifles retain their existing movement spread, supported-grip range, physical posture benefits, player aim, armour and secondary defenses.'
                description += " Four optional targeting slots and one selected ultimate are shared with learned compatible rifle abilities. Rifleman's Focus takes no slots and remains available in combined professions with another ultimate selected. The kit uses Health damage; legacy pool attacks, area Flurry and deathblow behavior are not separate SWGXR abilities."
                if resistance:
                    description += '\nCoreCU resistance progression: ' + ', '.join(f'{name.title()} +{value:g}' for name, value in resistance.items()) + ' rating. Strongest profession plus 25% of other contributions; native/profession baseline capped at 100. Doctor prophylaxis adds separately. Rating 100 reduces status chance and duration by 40%; immunity remains separate.'
                if skill['NAME'] in rifleman_abilities:
                    description += '\n' + rifleman_abilities[skill['NAME']]
            swordsman_abilities = {
                'combat_2hsword_novice': 'CoreCU heavy single-target damage: Rending Cut targets the torso for damage and a bounded, refreshing bleed. Overhead Cleave uses a two-handed raise and committed downward strike, with triggers released. Both require the two-handed melee family.',
                'combat_2hsword_ability_02': 'CoreCU Disrupting Blow: target the weapon arm for moderate damage and a resisted brief attack delay. Shared control recovery applies.',
                'combat_2hsword_speed_02': 'CoreCU Hamstring: target the knee for moderate damage and a resisted short movement slow. Shared control recovery applies.',
                'combat_2hsword_accuracy_04': 'CoreCU Decisive Strike: target the heart below 30% Health. Damage tapers with enemy combat level: 3x through level 30, down to 1.25x at 150. Bosses are ineligible.',
                'combat_2hsword_support_03': 'CoreCU Ground Slam: from a lower two-handed ready position, drive downward with triggers released, stopping above the floor. Strong primary hit with weak collateral on at most two other enemies. No bonus threat or mass knockdown.',
                'combat_2hsword_master': 'CoreCU ultimate: Armour Break. Equip in the two-handed melee ultimate slot, aim at an enemy, hold with both hands and press both triggers. A landed heavy hit opens an 8-second window of 50% lower Kinetic/Energy armour scores for all attackers. No stacking or refresh; 120-second cooldown.'}
            if skill['NAME'] in swordsman_abilities:
                description += '\n' + swordsman_abilities[skill['NAME']]
            fencer_abilities = {
                'combat_1hsword_novice': 'CoreCU one-handed bleed/debuff support: Arterial Cut targets the torso. Probing Jabs uses two forward weapon-hand jabs with retraction, grip held and trigger released; a landed hit grants 6 seconds of Precision for the next Fencer effect attempt.',
                'combat_1hsword_ability_02': 'CoreCU Nerve Strike: target the weapon arm for a light hit and 15% damage suppression. Stronger existing suppression takes precedence.',
                'combat_1hsword_ability_03': 'CoreCU Disorienting Thrust: target the eyes for a light hit and up to 4 seconds of resisted Blind. Shared control recovery applies.',
                'combat_1hsword_support_02': 'CoreCU Raking Slash: grip held, trigger released, slash diagonally from an upper corner across the body. A smaller bleed shares Arterial Cut’s single remaining damage budget.',
                'combat_1hsword_speed_02': 'CoreCU Guard Bash: hold a weapon guard briefly, then thrust the hilt forward with trigger released. Light hit and resisted attack delay up to 2 seconds; shared control recovery applies.',
                'combat_1hsword_support_04': 'CoreCU Exposing Thrust: target the upper chest. Reduces bleed, blind, intimidate and snare resistance by 20 rating, floored at zero, for all attackers. Immunities and other resistance types remain.',
                'combat_1hsword_master': 'CoreCU ultimate: Flawless Assault. Select in the one-handed melee ultimate row, support the weapon with the offhand, release both triggers then press both together. For 12 seconds, new Fencer bleed budgets reach 100% of landed damage; +10 application potency replaces Precision’s +5; both apply before resistance. No retroactive increase; 120-second cooldown.'}
            if skill['NAME'] in fencer_abilities:
                description += '\n' + fencer_abilities[skill['NAME']]
            if row['NAME'] == 'combat_1hsword':
                description += '\nCoreCU Fencer progression: bleed budget grows from 50% to 80% of landed damage, effect application bonus from +5 to +10 potency before resistance (95% final chance cap), and soft-debuff duration by up to 25% before resistance. Blind and attack delay do not gain duration. All Fencers share one bleed channel per target; refresh preserves the next tick and uses the greater of old remaining budget or the new hit budget.'
            pikeman_abilities = {
                'combat_polearm_novice': 'CoreCU crowd control: Unbalancing Thrust upgrades the existing Knockdown Strike slot/cooldown. Overhead Whirl uses a two-handed overhead circle for circular damage and brief Stun on up to four enemies. Driving Jabs uses two forward thrusts with retraction for two light hits on up to two enemies and a short slow. Keep triggers released for gestures.',
                'combat_polearm_accuracy_01': 'CoreCU Concussive Strike upgrades the Polearm Stun slot and shared cooldown: target the head for moderate damage and up to 4 seconds of resisted native Stun. Stun weakens combat effectiveness, not complete immobilisation.',
                'combat_polearm_speed_01': 'CoreCU Pinning Strike: target the foot for light damage and a resisted 40% slow lasting up to 5 seconds. Strongest slow wins.',
                'combat_polearm_support_01': 'CoreCU Disrupting Jab: target the weapon arm for a light hit and up to 2 seconds of resisted attack delay.',
                'combat_polearm_ability_01': 'CoreCU Sweeping Trip: two-handed low horizontal sweep with triggers released. Light damage in a wide forward arc on up to three enemies; individually attempts a brief knockdown.',
                'combat_polearm_master': 'CoreCU ultimate: Whirlwind. Select in the polearm ultimate row, hold with both hands, release both triggers then press both together. Moderate circular damage on up to six enemies with up to 3 seconds of resisted knockdown; 120-second cooldown. No physical body spin required.'}
            if skill['NAME'] in pikeman_abilities:
                description += '\n' + pikeman_abilities[skill['NAME']]
            if row['NAME'] == 'combat_polearm':
                description += '\nCoreCU Pikeman control application gains +5 to +10 potency with training before resistance, capped at 95% final chance. Hard-control duration remains capped; eight-second shared control recovery and immunities apply. Area attacks still damage protected enemies. Legacy pool-targeting and duplicate attack ranks are represented by the unified Health-based kit.'
            if skill['NAME'] == 'combat_unarmed_novice':
                description += '\nCoreCU Teras Kasi tank: unlocks Sweeping Punch in the gesture row and Challenging Strike in the targeting grid. Area damage generates extra threat; trained Center of Being efficacy, duration and status resistance supply survivability. Unarmed family only.'
            if row['NAME'] == 'combat_unarmed':
                grants={grant.lower() for grant in skill['COMMANDS'].split(',') if grant}
                if 'unarmedspinattack2' in grants:
                    description += '\nCoreCU Two-Handed Half-Spin: sweep both clenched hands together across your front with triggers released. Wide forward sector, capped targets, increased threat; no full body rotation required.'
                if 'unarmedcombo1' in grants:
                    description += '\nCoreCU Rapid Punch Volley: three alternating forward punches with clenched grips and triggers released. Capped narrow-cone attack, paid once per completed gesture.'
                if 'unarmedknockdown1' in grants or 'unarmedknockdown2' in grants:
                    description += '\nCoreCU Unbalancing Strike uses the existing knockdown targeting slot; the strongest learned unarmed knockdown rank replaces its source command.'
            if skill['NAME'].startswith('combat_unarmed_'):
                description += '\nSWGXR: Meditate and Power Boost are retired. Their legacy resource conversion and recovery actions are unavailable; Center of Being remains the defensive support buff.'
            if skill['NAME'] == 'combat_unarmed_accuracy_04':
                description += '\nForce of Will: TKA support recovery, outside targeting and ultimate slots. With the unarmed family equipped, release then hold the offhand stick while incapacitated: normal recovery after 1 second, Force of Will after 3 seconds total. Restores at least 15% of effective maximum Health, with a persistent 10-minute cooldown. No resurrection, wound treatment, Action/Mind refill or threat reset.'
            if skill['NAME'] == 'combat_unarmed_master':
                description += '\nCoreCU ultimate: Indomitable Focus. Equip in the unarmed ultimate slot; bring fists together and press both triggers. For 12 seconds, amplifies CoB efficacy under a cap, increases status resistance and adds damage threat. 120-second cooldown.'
            if row['NAME'] == 'combat_commando':
                description += '\nCoreCU Commando is equipment-driven: certified flame, acid, heavy beams and launchers provide bounded elemental area damage. Long weapons require two-handed support; the pistol launcher can fire one-handed. Focused Discharge concentrates one shot through VATS; learned acid cone attacks expose Acid Spray on the acid rifle. Grenades use the trap-style grip, physical throw and release at the reticle, with shared recovery across supplies. No new Commando schematics are granted.'
            if skill['NAME'] == 'combat_commando_master':
                description += '\nCoreCU ultimate: Overdrive. Select in the heavy-family ultimate row, release both triggers, support the weapon, then press both together. For 6 seconds direct special-weapon damage gains 25% and Action costs rise 50%; normal charges, area caps and burn budget remain. Persistent 120-second cooldown.'
            source_modifiers = None
            if row['NAME'] == 'combat_bountyhunter':
                source_modifiers = dict(mods)
                for key in ('pistol_accuracy', 'carbine_accuracy', 'heavy_rifle_lightning_accuracy'):
                    mods.pop(key, None)
                for key in ('pistol_speed', 'carbine_speed', 'heavy_rifle_lightning_speed'):
                    if key in mods:
                        if key == 'heavy_rifle_lightning_speed' and skill['NAME'] == 'combat_bountyhunter_novice':
                            mods.pop(key)
                        else:
                            mods[key] //= 2
                description = all_labels[skill['NAME']] + ': CoreCU single-target bounty combat and PvE investigation.'
                description += ' Pistol/carbine/lightning branch speed reaches +25; the strongest compatible advanced-profession contribution applies alongside the Marksman baseline, instead of stacking trained speed. Raw BH accuracy bonuses are retired. Relevant branch training improves BH effect application from 85 to 95 potency before resistance. Shared controls, bleed and accuracy suppression do not stack duplicate effects.'
                description += ' Spray Shot and Lightning Cones are retired. Additional combat training supplies stronger sustained output or area attacks, including learned Pistoleer Fan Shot. Original prerequisites, skill points, XP, droid investigation and certifications remain.'
                bounty_abilities = {
                    'combat_bountyhunter_novice': 'Use original bounty terminals for PvE missions and nearby informants for target information. Hold and trigger a seeker to search; hold and trigger an Arakyd probe, then select a planet in the popup. Native investigation training, consumable charges and delays apply. The scatter pistol distributes eight physical pellets through a four-degree half cone, sharing one target and one shot damage budget. The distinct BH lightning rifle has slight bounded guidance toward one initially acquired target; range, cover and physical collision still matter.',
                    'combat_bountyhunter_droidresponse_01': 'Bleeding Shot upgrades the shared pistol abdomen ability to a 0.8x hit and 40% landed-damage bleed budget over up to 12 seconds. Costs 55 Action / 20 Mind, 16-second recovery; strongest compatible trained bleed profile wins.',
                    'combat_bountyhunter_droidresponse_02': 'Eye Shot: pistol VATS head marker, 0.6x Health hit and resisted -25 NPC accuracy for up to 6 seconds. Shares the suppression channel; no extra native Blind penalty or HMD blackout. 50 Action / 20 Mind, 18-second recovery.',
                    'combat_bountyhunter_droidresponse_04': 'Torso Shot upgrades the same Bleeding Shot entry to a 45% landed-damage bleed budget. No separate cooldown, Mind damage or fire DoT; droids remain immune to bleeding.',
                    'combat_bountyhunter_droidcontrol_01': 'Underhand Shot gesture: hold the carbine low, raise its muzzle in a short arc, return to aim and trigger within the native 1.5-second armed window. The physical shot deals 0.65x damage and attempts a resisted knockdown for up to 2 seconds. Costs 70 Action / 30 Mind, 24-second recovery; misses still consume the accepted shot.',
                    'combat_bountyhunter_droidcontrol_03': 'Knockdown Fire advances the single Underhand Shot gesture and its application proficiency; it is not an independent attack or recovery timer.',
                    'combat_bountyhunter_droidcontrol_04': 'Confusion Shot: carbine VATS torso marker, 0.6x damage with up to 3 seconds of resisted native Stun. No additional Dizzy or movement freeze. 60 Action / 25 Mind, 20-second recovery.',
                    'combat_bountyhunter_investigation_01': 'Droid Find enables learned seeker/probe investigation for eligible missions. Obsolete BH ranged mitigation grants are retired; surviving grants from other professions remain.',
                    'combat_bountyhunter_investigation_03': 'Droid Track enables repeated target-waypoint updates for eligible native missions. Tracking consumes a droid charge; it does not reveal targets before native discovery.',
                    'combat_bountyhunter_investigation_04': 'Duelist Stance: with a compatible weapon held forward and triggers released, tap the upper chest twice with the free open offhand. A visible enemy in aim and weapon range is bound for 8 seconds: its direct attacks deal 15% less damage. Strongest with equivalent protection such as Rally; no protection from other enemies or DoTs. 60 Action / 30 Mind, 60-second recovery. Open-hand taps remain distinct from Brawler Taunt.',
                    'combat_bountyhunter_master': 'Fast Blast ultimate: select with a pistol, carbine or BH lightning rifle, aim at one opponent and press both triggers together. One 3.0x Health attack, normal defenses and bounded weapon delivery. 140 Action / 70 Mind, persistent 120-second recovery. No multi-pool damage, guaranteed hit or area effect.'}
                if skill['NAME'] in bounty_abilities:
                    description += '\n' + bounty_abilities[skill['NAME']]
                if skill['NAME'].startswith('combat_bountyhunter_support_'):
                    description += '\nLightning proficiency improves the normalized single-target electricity discharge. Original Single I/II ranks do not add separate targeting buttons; Cone I/II cannot cause area damage. This weapon is separate from Commando heavy lightning beams.'
                if resistance:
                    description += '\nCoreCU resistance progression: ' + ', '.join(f'{name.title()} +{value:g}' for name, value in resistance.items()) + ' rating. Strongest profession plus 25% of other contributions; baseline capped at 100, with Doctor preparation added separately.'
            if row['NAME'] == 'outdoors_squadleader':
                source_modifiers = dict(mods)
                mods = {}
                skill_id = skill['NAME']
                master = skill_id == 'outdoors_squadleader_master'
                if master or skill_id.startswith('outdoors_squadleader_offense_'):
                    mods['group_damage_percent'] = 2
                if master or skill_id.startswith('outdoors_squadleader_movement_'):
                    mods['group_action_mind_regen_percent'] = 2
                for key in ('group_melee_defense', 'group_ranged_defense'):
                    if source_modifiers.get(key):
                        mods[key] = source_modifiers[key] * .5
                description = all_labels[skill_id] + ': CoreCU group support with any weapon, including unarmed. Squad Leader provides no new standalone attack or solo damage bonus.'
                description += ' Passives apply to eligible online party members on the same planet, without a distance or building limit. They require another eligible player; strongest same-party Squad Leader contributions apply once. Master caps are +10% direct damage, +10% existing Action/Mind regeneration, and +15 melee/ranged defense against native accuracy rolls. Fractional defense contributions are summed and rounded up once.'
                description += ' Aim at a nearby group member and open friendly VATS for all learned support shouts. They take no offensive targeting slots, affect eligible nearby group members within 48 metres, and retain per-recipient recovery so multiple leaders cannot chain the same order. Physical tracking remains authoritative.'
                squad_abilities = {
                    'outdoors_squadleader_offense_01': 'Steady Aim: +15% direct attack damage for 12 seconds. 60 Action / 30 Mind; 45-second recovery. Together with mastered passive output, the Squad Leader damage bonus is capped at +25%.',
                    'outdoors_squadleader_offense_02': 'Original Steady Aim accuracy rating is retired; this box advances the CU group damage passive.',
                    'outdoors_squadleader_offense_03': 'The original Volley Fire grant contributes to the Master Squad Leader ultimate; it does not force automatic attacks by group members.',
                    'outdoors_squadleader_offense_04': 'Original Volley accuracy rating is retired; this box advances the CU group damage passive.',
                    'outdoors_squadleader_defense_01': 'Form Up: clear Stun and Dizzy, then add 20 status resistance rating for 6 seconds within the existing baseline cap. 60 Action / 40 Mind; 45-second recovery. No forced posture or HMD movement.',
                    'outdoors_squadleader_defense_04': 'Boost Morale: +50% existing Action/Mind regeneration for 15 seconds, additive with the Squad Leader passive to +60%. 40 Action / 60 Mind; 90-second recovery. No instant healing, pool refill or wound redistribution.',
                    'outdoors_squadleader_support_01': 'Rally: 15% less incoming direct attack damage for 12 seconds. 70 Action / 40 Mind; 60-second recovery. No obsolete raw accuracy bonus.',
                    'outdoors_squadleader_support_03': 'Retreat: +20% voluntary movement speed for 8 seconds. 80 Action / 30 Mind; 60-second recovery. Does not move tracked head/hands, force retreat or clear enemy threat.',
                    'outdoors_squadleader_master': 'Volley Fire ultimate: select with any weapon, aim at an enemy and press both triggers together. Places a visible local reticle for each eligible party member for 12 seconds. Each member gets one guaranteed in-range direct hit against that enemy, even if the physical attack misses. Normal damage, armor, costs and charges remain; separate status resistance remains. Joining later does not grant another hit. 80 Action / 40 Mind; persistent 120-second recovery.'}
                if skill_id in squad_abilities:
                    description += '\n' + squad_abilities[skill_id]
                if skill_id.startswith('outdoors_squadleader_movement_'):
                    description += '\nOriginal group terrain traversal and Burst Run ratings are retired; this box advances existing Action/Mind regeneration instead.'
                if resistance:
                    description += '\nPersonal CoreCU resistance progression: ' + ', '.join(f'{name.title()} +{value:g}' for name, value in resistance.items()) + ' rating. Existing profession combination and caps remain.'
            nodes.append({'corecu_trap_success_bonus':trap_bonus, 'id':skill['NAME'], 'label':all_labels[skill['NAME']],
                          'description':description, 'corecu_resistance_contribution':resistance,
                          'requires':list(filter(None, skill['SKILLS_REQUIRED'].split(','))),
                          'requires_count':skill['SKILLS_REQUIRED_COUNT'],
                          'excludes':list(filter(None, skill['PRECLUSION_SKILLS'].split(','))),
                          'xp_type':skill['XP_TYPE'], 'xp_cost':skill['XP_COST'],
                          'credits':skill['MONEY_REQUIRED'], 'points':skill['POINTS_REQUIRED'],
                          'modifiers':mods,
                          **({'source_modifiers':source_modifiers} if source_modifiers is not None else {}),
                          'schematic_groups':list(filter(None,skill['SCHEMATICS_GRANTED'].split(','))),
                          'certificates':[c for c in skill['COMMANDS'].split(',') if c.startswith('cert_')]})
        professions.append({'id':row['NAME'], 'label':all_labels[row['NAME']],
                            'graph_type':row['GRAPH_TYPE'], 'nodes':nodes})
    return {'schema':1, 'backend_name':'CoreCU', 'advanced_professions':'provisional_core3_skeleton', 'professions':professions, 'labels':all_labels,
            'provenance':sources, 'warnings':warnings, 'read_only':True}
