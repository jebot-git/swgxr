#!/usr/bin/env python3
"""Compile current support policies and report their authored balance envelope.

This read-only arithmetic audit launches no game service or client. Its ideal
uptime figures describe policy bounds rather than a measured live encounter.
"""
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'runtime/evidence/squad-leader/balance.json'


def method(source, signature):
    start=source.index(signature)
    opening=source.index('{',start)
    depth=1
    end=opening+1
    while depth:
        depth += (source[end]=='{') - (source[end]=='}')
        end+=1
    return source[start:end]


def compiled():
    with tempfile.TemporaryDirectory(prefix='swgxr-squad-balance-') as directory:
        path=Path(directory)
        resources=(ROOT/'server/combat/CoreCuResources.h').read_text()
        (path/'corecu_resource_reference.inc').write_text('struct CoreCuResources { public:\n'+method(resources,' static int base(')+'\n'+method(resources,' static double regen(')+'\n};\n')
        subprocess.run(['c++','-std=c++17','-O2','-pthread','-I'+directory,'-I'+str(ROOT),str(ROOT/'tests/squad_leader_balance.cpp'),'-o',str(path/'audit')],check=True)
        return json.loads(subprocess.check_output([str(path/'audit')],text=True))


def main():
    values=compiled()
    sources=['server/combat/SquadLeaderPolicy.h','server/combat/SwgxrSquadLeader.h','server/combat/VolleyFirePolicy.h','server/combat/SwgxrVolleyFire.h','server/combat/DoctorPolicy.h','server/combat/CoreCuPolicy.h','server/combat/CoreCuResources.h','server/movement/SwgxrMovement.h','vendor/Core3/MMOCoreORB/src/server/zone/objects/creature/CreatureObjectImplementation.cpp','vendor/Core3/MMOCoreORB/src/server/zone/managers/combat/CombatManager.cpp','tests/squad_leader_balance.cpp','tools/server/audit_squad_leader_balance.py']
    report={
        'scope':'compiled production-policy arithmetic; ideal support envelope, not live encounter validation',
        'validation':{'compiled_current_production_headers':True,'live_encounter':False,'client_launched':False,'headset_or_gpu_validation':False},
        'assumptions':[
            'The recipient is alive and online in a valid group with another online player on the same planet. Native membership, current skills, source eligibility and cooldowns remain authoritative; ungrouped Squad Leaders receive no new group bonuses.',
            'Master progression is used for peak values. Repeated Squad Leaders contribute only the strongest value in each passive category; active support effects share each recipient’s recovery and do not stack.',
            'Each shout is successfully applied on every cooldown and its recipient remains eligible for its entire duration. This ignores targeting, scheduling collisions, the two-second shared command recovery, movement and unavailable allies; measured uptime can be lower.',
            'The caster aims at a visible eligible group member within the support range. Active shouts affect nearby eligible group members within that range; only passive benefits are planet-wide.',
            'Damage and incoming attacks are uniformly distributed over time for mean damage and mitigation. Damage buffs affect direct attacks once; they do not produce attacks or separately multiply an already hit-derived DoT budget.',
            'Resource burden assumes all five shouts, and separately Volley Fire, are used on cooldown. Reference regeneration comes from compiled CoreCuResources base pools and in-combat rates; other offensive or medical spending is absent.',
            'Boost Morale increases existing Action and Mind regeneration only. No Health regeneration, immediate pool refill, maximum pool increase or wound redistribution is supplied by Squad Leader.',
            'Doctor interaction uses the compiled maximum Metabolic preparation. It multiplies existing regeneration; the reported Action/Mind peak is not a healing action or an immediate resource award.',
            'Volley Fire grants a per-member consumable guarantee for one eligible attack at the designated enemy. Its damage benefit depends on the otherwise missed attack and its normal weapon/ability budget, so no universal DPS multiplier is asserted.',
        ],
        'source_sha256':{name:hashlib.sha256((ROOT/name).read_bytes()).hexdigest() for name in sources},
        'compiled':values,
    }
    OUT.parent.mkdir(parents=True,exist_ok=True)
    OUT.write_text(json.dumps(report,indent=2,sort_keys=True)+'\n')
    print(json.dumps({'report':str(OUT),'master':values['master'],'resource_burden':values['resource_burden']},indent=2))


if __name__=='__main__':
    main()
