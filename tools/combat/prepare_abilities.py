#!/usr/bin/env python3
"""Extract original command icon art to ignored runtime storage with provenance."""
import hashlib
import io
import json
from pathlib import Path
import sys
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools/assets'))
from swg_formats import TreSet
from prepare_datapad import Elements


def main():
    tre = TreSet(ROOT / 'runtime/assets/active_tre')
    out = ROOT / 'runtime/combat/abilities'
    out.mkdir(parents=True, exist_ok=True)
    ui = tre.read('ui/ui_styles.inc')
    styles = {attrs.get('name', '').lower(): attrs for tag, attrs in Elements(ui.decode()).items if tag.lower() == 'imagestyle'}
    result = {'icons':{}, 'sources':{'ui/ui_styles.inc':hashlib.sha256(ui).hexdigest()}}
    for command in ('overchargeshot2', 'melee1hlunge2', 'melee2hlunge2', 'polearmlunge2', 'unarmedlunge2', 'animalattack', 'follow', 'store', 'stopfollow', 'formation', 'group', 'harvestcorpse', 'vrepairother', 'maskscent', 'sampledna', 'burstrun', 'forage', 'healdamage', 'healwound', 'tenddamage', 'tendwound', 'firstaid', 'quickheal',
                    'tame', 'emboldenpets', 'enragepets', 'mount', 'dismount', 'pethigh', 'petlow', 'trainmount',
                    'conceal', 'rescue', 'areatrack'):
        # Mount training is an original pet radial action, with no separate
        # command icon in ui_styles.inc. Reuse the original mount artwork.
        source_style = 'mount' if command == 'trainmount' else command
        style = styles[source_style]
        texture = 'texture/' + style['source'].split(':')[-1] + '.dds'
        raw = tre.read(texture)
        rect = tuple(int(v) for v in style['sourcerect'].split(','))
        # SWG also uses reversed UV rectangles (petLow is petHigh flipped).
        crop = Image.open(io.BytesIO(raw)).convert('RGBA').crop((min(rect[0],rect[2]),min(rect[1],rect[3]),max(rect[0],rect[2]),max(rect[1],rect[3])))
        if rect[2] < rect[0]: crop = crop.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
        if rect[3] < rect[1]: crop = crop.transpose(Image.Transpose.FLIP_TOP_BOTTOM)
        crop.save(out / (command + '.png'))
        result['icons'][command] = {'path':command + '.png', 'source':texture, 'source_rect':rect, 'source_style':source_style}
        result['sources'][texture] = hashlib.sha256(raw).hexdigest()
    (out / 'catalog.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({'icons':len(result['icons']), 'output':str(out)}))


if __name__ == '__main__': main()
