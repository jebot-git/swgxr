"""Apply deterministic Core3 outfit variants to original NPC CDF appearances."""
import copy
import hashlib
import json
import re
from pathlib import Path
from interior_layout import template_properties
from static_assets import StaticAssets
from swg_formats import parse_iff, cstring


def rigid_equipment(importer, static, cache, source, shared, properties, bones, customization, provenance):
    appearance = properties.get('appearanceFilename', '')
    arrangement = properties.get('arrangementDescriptorFilename', '')
    if not appearance or not arrangement:
        raise ValueError('Rigid equipment requires an original appearance and arrangement descriptor')
    root = parse_iff(importer.read(arrangement))
    if root.tag != 'ARGD' or root.children[0].tag != '0000':
        raise ValueError('Unsupported equipment arrangement format')
    choices = []
    for entry in root.walk('ARG '):
        position = 0; slots = []
        while position < len(entry.data):
            slot, position = cstring(entry.data, position); slots.append(slot)
        choices.append(slots)
    names = {bone['name'] for bone in bones}
    selected = next(((index, slot, slots) for index, slots in enumerate(choices) for slot in slots if slot in names), None)
    if selected is None:
        raise ValueError('No source equipment arrangement names an existing animated bone: ' + repr(choices))
    variant, bone, slots = selected
    if appearance not in cache:
        parts = static.resolve(appearance)
        if not parts:
            raise ValueError('No rigid equipment triangles')
        surfaces = []; hardpoints = []
        for part in parts:
            model = json.loads((static.out / static.meshes[part['mesh']]['path']).read_text())
            for surface in model['surfaces']:
                surface = copy.deepcopy(surface)
                if surface.get('texture'): surface['texture'] = 'equipment/' + surface['texture']
                surfaces.append(surface)
        # HPTS are attachment anchors for children, not a reason to invent a
        # grip offset. Retain their presence; object origin binds to its slot.
        seen = set()
        def collect_hardpoints(path):
            if not path.startswith('appearance/'): path = 'appearance/' + path
            if path in seen: return
            seen.add(path); resource = parse_iff(static.read(path))
            for form in resource.walk('HPTS'):
                hardpoints.extend({'source':path,'tag':node.tag,'raw_hex':node.data.hex()} for node in form.children)
            if path.endswith('.apt'):
                collect_hardpoints(cstring(resource.first('NAME').data)[0])
            elif path.endswith('.lod'):
                for node in resource.walk('CHLD'): collect_hardpoints(cstring(node.data, 4)[0])
            elif path.endswith('.cmp'):
                for node in resource.walk('PART'): collect_hardpoints(cstring(node.data)[0])
        collect_hardpoints(appearance)
        relative = 'equipment/models/' + hashlib.sha256(appearance.encode()).hexdigest()[:24] + '.json'
        importer.write(relative, {'schema_version':1,'source_appearance':appearance,'coordinate_system':'Godot Y-up; original SWG Z mirrored; equipment origin retained','source_meshes':[part['mesh'] for part in parts],'surfaces':surfaces})
        cache[appearance] = (relative, hardpoints)
    relative, hardpoints = cache[appearance]
    return {'template':source,'shared_template':shared,'appearance':appearance,'model':relative,'bone':bone,'local_transform':[1,0,0,0,0,1,0,0,0,0,1,0],'local_transform_layout':'row_major_3x4','source_arrangement':arrangement,'source_arrangement_index':variant,'source_slots':slots,'source_hardpoints':hardpoints,'attachment_policy':'Original object origin bound to the first source arrangement slot naming an animated skeleton bone; no guessed grip offset','customization':customization,**provenance}

def apply_outfit_variants(importer, catalog, placements):
    models = {}; wearables = {}; templates = {}; variants = {}; failures = []; unsupported = []; rigid_cache = {}
    static = StaticAssets(importer.t.archives[0].parent, importer.out / 'equipment')
    static.t = importer.t # Preserve the complete active archive set and precedence.
    for placement in placements['instances']:
        outfit = placement.get('core3_outfit')
        primary = placement.get('source_primary_weapon')
        primary = primary if primary and primary.get('status') == 'selected' else None
        if not outfit and not primary:
            continue
        key = placement['appearance_id']
        if key in variants:
            continue
        base = catalog['races'].get(placement['template'])
        if not base:
            failures.append({'appearance_id': key, 'phase': 'core3_outfit', 'error': 'Base NPC descriptor unavailable'})
            continue
        descriptor = copy.deepcopy(base)
        descriptor['appearance_id'] = key
        descriptor['source_outfit'] = copy.deepcopy(outfit)
        descriptor['source_primary_weapon'] = copy.deepcopy(primary)
        descriptor['unsupported_equipment'] = []
        descriptor['rigid_equipment'] = copy.deepcopy(base.get('rigid_equipment', []))
        # Keep the original CDF, including its body customization and wearables.
        # Core3 supplies additional equipped objects rather than a replacement CDF.
        if base['body'] not in models:
            models[base['body']] = json.loads((importer.out / base['body']).read_text())
        body = models[base['body']]; bones = body['bones']; names = {b['name']: i for i, b in enumerate(bones)}
        skin = next((s for part in body['parts'] for s in part['mesh']['surfaces'] if '_body' in s['shader'] and s.get('palettes')), next(s for part in body['parts'] for s in part['mesh']['surfaces']))
        importer.skin_material = {k: v for k, v in skin.items() if k not in ('vertices','normals','uv','indices','bones','weights','triangle_zones','blend_shapes')}
        count = 0
        if outfit and outfit.get('resolution_error'):
            failures.append({'appearance_id': key, 'phase': 'core3_outfit_resolution', 'error': outfit['resolution_error']})
        jobs = [(index,item,False) for index,item in enumerate(outfit['items'])] if outfit else []
        if primary: jobs.append((-1,primary,True))
        for index, item, is_primary in jobs:
            source = item['template']; shared = str(Path(source).parent / ('shared_' + Path(source).name))
            provenance = {'source_kind':'primary_weapon','source_weapon_group':primary['group'],'source_file':item['source_file'],'source_line':item['source_line'],'selection_policy':primary['selection_policy']} if is_primary else {'source_kind':'outfit','source_outfit': outfit['name'], 'source_outfit_variant': outfit['variant_index'], 'source_outfit_index': index, 'source_file': item['source_file'], 'source_line': item['source_line']}
            try:
                properties = template_properties(importer.read, shared, templates)
                appearance = properties.get('appearanceFilename', '')
                if not appearance:
                    raise ValueError('No original equipped-object appearance')
                if not source.startswith(('object/tangible/wearables/', 'object/tangible/hair/')):
                    try:
                        attachment = rigid_equipment(importer, static, rigid_cache, source, shared, properties, bones, item['customization'], provenance)
                        if is_primary and any(existing['bone']==attachment['bone'] for existing in descriptor['rigid_equipment']):
                            raise ValueError('Explicit outfit equipment already occupies source bone '+attachment['bone'])
                        descriptor['rigid_equipment'].append(attachment)
                    except Exception as error:
                        omitted = {'template':source,'shared_template':shared,'appearance':appearance,'customization':item['customization'],**provenance,'reason':str(error)}
                        descriptor['unsupported_equipment'].append(omitted)
                        unsupported.append({'appearance_id':key,**omitted})
                    continue
                sex = 'f' if Path(base['appearance']).stem.endswith('_f') else 'm'
                stem = re.sub(r'_[mf]$', '_' + sex, Path(appearance).stem)
                prefix = 'wke_' if 'wookiee' in base['appearance'] else 'ith_' if 'ithorian' in base['appearance'] else ''
                candidates = ['appearance/' + prefix + stem + '.sat', 'appearance/' + stem + '.sat', appearance]
                appearance = next(candidate for candidate in candidates if candidate in importer.t.entries)
                identity = (base['appearance'], shared, appearance, importer.skin_material['shader'])
                if identity not in wearables:
                    model = importer.model(appearance, bones, names)
                    path = 'clothing/core3/' + hashlib.sha256(repr(identity).encode()).hexdigest()[:24] + '.json'
                    importer.write(path, model)
                    wearables[identity] = path
                descriptor['default_outfit'].append({'template': source, 'shared_template': shared, 'appearance': appearance, 'model': wearables[identity], 'customization': item['customization'], **provenance})
                count += 1
            except Exception as error:
                record = {'appearance_id': key, 'resource': source, 'phase': 'core3_outfit_wearable', **provenance, 'error': str(error)}
                failures.append(record)
        catalog['races'][key] = descriptor
        variants[key] = {'template': placement['template'], 'outfit': outfit['name'] if outfit else '', 'primary_weapon':primary['template'] if primary else '', 'variant_index': outfit['variant_index'] if outfit else 0, 'source_items': len(jobs), 'converted_items': count, 'cdf_items': len(base['default_outfit']), 'rigid_items':len(descriptor['rigid_equipment']), 'unsupported_attachments': len(descriptor['unsupported_equipment'])}
    importer.dependencies.update(static.dependencies)
    failures.extend({'phase':'core3_outfit_rigid',**failure} for failure in static.failures)
    importer.failures.extend(failures)
    report = {'schema_version': 1, 'variants': variants, 'converted_items': sum(v['converted_items'] for v in variants.values()), 'unique_models': len(wearables), 'converted_rigid_items':sum(v['rigid_items'] for v in variants.values()),'unique_rigid_models':len(rigid_cache), 'unsupported_attachments': unsupported, 'conversion_failures': failures, 'excluded_primary_placements':[{'id':item['id'],'mobile':item['mobile'],'source_primary_weapon':item['source_primary_weapon']} for item in placements['instances'] if item.get('source_primary_weapon') and item['source_primary_weapon'].get('status')!='selected'],'source_policy': 'Deterministic first source primary weapon where the authored arrangement matches an actual skeleton bone. Original Core3 outfit objects/customization plus original CDF wearables; no substitute outfits or live Core3 equipment claims.'}
    catalog['outfit_report'] = report
    importer.write('outfit_report.json', report)
    return report


def refresh_outfits(importer, placements, placement_path, placement_bytes):
    catalog = json.loads((importer.out / 'catalog.json').read_text())
    importer.dependencies.update(catalog['provenance']['dependencies'])
    importer.failures = [failure for failure in catalog.get('failures', []) if not failure.get('phase', '').startswith('core3_outfit')]
    catalog['failures'] = importer.failures
    for key in list(catalog['races']):
        if '#outfit=' in key or '#weapon=' in key:
            del catalog['races'][key]
    report = apply_outfit_variants(importer, catalog, placements)
    catalog['provenance'].update(placement_manifest=str(placement_path.resolve()), placement_sha256=hashlib.sha256(placement_bytes).hexdigest(), dependencies=importer.dependencies, core3_outfit_files_sha256={key: value for key, value in placements['provenance']['files_sha256'].items() if '/mobile/outfits/' in key})
    catalog['statistics'].update(outfit_variants=sum(bool(v['outfit']) for v in report['variants'].values()),equipment_variants=len(report['variants']), outfit_converted_items=report['converted_items'], outfit_rigid_items=report['converted_rigid_items'], unsupported_outfit_attachments=len(report['unsupported_attachments']), outfit_conversion_failures=len(report['conversion_failures']), exported_descriptors=len(catalog['races']), failures=len(importer.failures))
    importer.write('catalog.json', catalog)
    return catalog['statistics']
