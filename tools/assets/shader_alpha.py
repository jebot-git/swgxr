"""Source effect alpha intent, without guessing from texture alpha channels.

SWG reuses texture alpha for specularity and other non-opacity data. Only the
effect sort bucket or an enabled fixed-function alpha test authorizes cutouts.
"""
from swg_formats import parse_iff, cstring

SCHEMA_VERSION = 3

def effect_alpha(root, effect):
    evidence=[]
    for implementation in root.walk('IMPL'):
        version=implementation.children[0]
        data=next((n for n in version.children if n.tag=='DATA'),None)
        sort_tag=data.data[1:5].decode('ascii')[::-1] if data and len(data.data)>=5 else ''
        passes=[]
        for node in version.children:
            if node.tag!='PASS' or not node.children:continue
            definition=node.children[0]
            state=next((n for n in definition.children if n.tag=='DATA'),None)
            raw=state.data if state else b''
            # PASS0009 carries the alpha-test enable byte at offset 11.
            # Retain all passes for diagnostics, but only the first/base pass
            # defines surface coverage. A specular overlay can alpha-test its
            # mask over an opaque base without making the object transparent.
            known=definition.tag=='0009' and len(raw)==56
            passes.append({'version':definition.tag,'alpha_test':bool(raw[11]) if known else False,'decoded':known})
        # Original ShaderImplementation::isOpaqueSolid inspects m_pass[0].
        # Inspect every implementation because programmable variants can move
        # the base-pass cutout test into the pixel shader (a_punchout.eft).
        evidence.append({'effect':effect,'implementation':version.tag,'sort_tag':sort_tag,'alpha_test':passes[0]['alpha_test'] if passes else False,'passes':passes})
    return evidence

def shader_alpha(root, read, cache=None):
    evidence=[]
    names=sorted({cstring(n.data)[0].replace('\\','/').lower() for n in root.walk('NAME') if n.data.rstrip(b'\0').lower().endswith(b'.eft')})
    for effect in names:
        if cache is not None and effect in cache:items=cache[effect]
        else:
            items=effect_alpha(parse_iff(read(effect)),effect)
            if cache is not None:cache[effect]=items
        evidence.extend(items)
    return {'alpha':any(e['sort_tag']=='ALPH' or e['alpha_test'] for e in evidence),'alpha_source':evidence,'alpha_schema_version':SCHEMA_VERSION}
