#!/usr/bin/env python3
"""Craft an original mission output without grants and inspect its slice provenance."""
import argparse
import json
import math
import secrets
from delivery_mission_smoke import Probe, item_ids
from services_smoke import ROOT, redact, req


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--execute-native',action='store_true',required=True)
    parser.parse_args()
    output=ROOT/'runtime/evidence/slicing-crafting-native-smoke.json'
    probe=Probe('crafting',output)
    try:
        probe.fixture=dict(account='invtestcraftslice'+secrets.token_hex(3),name='Ivtest'+''.join(secrets.choice('aeilnorstu') for _ in range(8)))
        made=req('/characters',dict(probe.fixture,species='human',profession='crafting_artisan'))
        probe.check('character' in made,'Create fresh original artisan with no privileged skill or ingredient grants')
        probe.fixture['id']=made['character']['id']
        probe.report['fixture']=probe.fixture
        entered=probe.call('/enter')
        probe.initial_pose=entered['source_location']
        probe.start(probe.initial_pose)
        probe.baseline=item_ids(probe.inventory())
        catalog=json.loads((ROOT/'runtime/assets/services/catalog.json').read_text())
        terminals=[t for t in catalog['static_terminals'] if t['kind']=='mission' and int(t['id'])>0 and t['template'].endswith('/terminal_mission_artisan.iff')]
        probe.terminals={'crafting':min(terminals,key=lambda t:math.dist(t['position'],[3500,5,-4860]))}
        offer=probe.accept('crafting')
        _,components=probe.pickup(offer['id'])
        output_item=probe.craft(offer,components)
        inventory=probe.inventory()
        crafted=next(i for i in inventory['items'] if i['id']==output_item['id'])
        probe.report['crafted_output']=crafted
        probe.report['actual_crafting_performed']=True
        # The slicing view exposes the same native crafter-ID/serial predicate
        # used by its equipment gate, including on unsupported mission outputs.
        probe.check(crafted.get('slice_crafted',False),'Actual native crafting output has nonempty original crafter id and serial')
        probe.complete(offer,output_item)
        probe.report['passed']=True
    finally:
        probe.cleanup()
        probe.report['passed']=probe.report['passed'] and not probe.report.get('cleanup_errors')
        output.write_text(json.dumps(redact(probe.report),indent=2)+'\n')
        print(json.dumps(dict(passed=probe.report['passed'],checks=len(probe.report['checks']),evidence=str(output))),flush=True)
    return 0 if probe.report['passed'] else 1


if __name__=='__main__':
    raise SystemExit(main())
