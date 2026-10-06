"""Resolve original SAT/LAT selectors and export noncombat ANS animation coverage.

This is a deliberately bounded consumer of the authored graph, not a claim to
reproduce the original combat, priority-mask or ambient-action scheduler.
"""
import hashlib
import json
import struct
from swg_formats import parse_iff, cstring
from character_formats import child, array, qmul, mirror, mirror_quaternion, unpack_quaternion


def version(node):
    return node.children[0] if node.children and node.children[0].tag.isdigit() else node


def resolve(node, selectors, speed_scale=1.0):
    """Return selected leaf clips, preserving source selector decisions."""
    if node.tag == 'PXAT':
        info = version(node).first('INFO').data
        return [{'source': cstring(info)[0], 'speed_scale': speed_scale}]
    data = version(node)
    if node.tag == 'SSAT':
        variable = cstring(child(data, 'INFO').data)[0]
        branches = [n for n in child(data, 'ANMS').children if n.tag != 'INFO']
        default = child(data, 'DFLT')
        index = struct.unpack('<H', default.data)[0] if default else 0
        values = child(data, 'VAL ').data
        count = struct.unpack_from('<H', values)[0]
        offset = 2
        for _ in range(count):
            key, offset = cstring(values, offset)
            selected = struct.unpack_from('<H', values, offset)[0]
            offset += 2
            if key == selectors.get(variable):
                index = selected
        if index >= len(branches):
            raise ValueError(('Selector out of range', variable, index))
        return resolve(branches[index], selectors, speed_scale)
    if node.tag == 'AGAT':
        return resolve(child(data, 'LOOP'), selectors, speed_scale)
    if node.tag == 'TSCL':
        speed_scale *= struct.unpack('<f', child(data, 'INFO').data)[0]
    result = []
    for item in data.children:
        if item.children:
            result.extend(resolve(item, selectors, speed_scale))
    return result


def load_lat(imp, path):
    root = parse_iff(imp.read(path))
    info = root.first('INFO').data
    ash = cstring(info)[0]
    entries = {cstring(child(n, 'INFO').data)[0]: n for n in root.walk('ANIM')}
    return ash, entries


def ash_summary(imp, path):
    root = parse_iff(imp.read(path))
    states, actions = [], {}
    for state in root.walk('STAT'):
        info = child(state, 'INFO')
        if info:
            name, offset = cstring(info.data)
            loop = cstring(info.data, offset)[0]
            states.append({'name': name, 'loop': loop})
    # Root actions define noncombat command aliases; nested actions override them
    # in the original engine and are intentionally outside this bounded graph.
    root_state = root.first('STAT')
    action_root = child(root_state, 'ACTS')
    if action_root:
        for action in action_root.children:
            if action.tag == 'ACTN':
                name, offset = cstring(action.data)
                logical, _ = cstring(action.data, offset)
                actions[name] = logical
    return {'source': path, 'states': states, 'actions': actions}


def export_character_animations(imp, appearance, race, bones, names):
    """Return model fields: animations, animation_library and animation_graph."""
    sat = parse_iff(imp.read(appearance))
    raw = sat.first('LATX').data
    count = struct.unpack_from('<H', raw)[0]
    offset = 2
    lat_paths = []
    for _ in range(count):
        skeleton, offset = cstring(raw, offset)
        lat, offset = cstring(raw, offset)
        lat_paths.append({'skeleton': skeleton, 'lat': lat})
    selectors = {'gender': 'f' if race.endswith('_female') else 'm', 'mood': 'neutral'}
    ash, body = load_lat(imp, lat_paths[0]['lat'])
    graph = ash_summary(imp, ash)
    graph.update({'lat_bindings': lat_paths, 'selectors': selectors, 'unavailable': [],
                  'limitations': ['Runtime locomotion/posture selection replaces the original graph scheduler.',
                                 'Combat, animation priority masks and ambient action scheduling are not implemented.',
                                 'Locomotion root motion is ignored; native gameplay physics owns movement.']})
    animations, library = {}, {}

    def selected(logical, table=body):
        if logical not in table:
            return []
        return resolve(table[logical], selectors)

    def add(key, leaf, logical, loop=True, lazy=False):
        source = leaf['source']
        try:
            clip = decode_clip(imp, source, bones, names)
            if not clip['tracks']:
                raise ValueError('No tracks match this skeleton')
            clip.update({'loop': loop, 'logical': logical, 'source_speed_scale': leaf.get('speed_scale', 1)})
            if lazy:
                encoded = json.dumps(clip, separators=(',', ':'))
                path = 'animations/' + hashlib.sha256(encoded.encode()).hexdigest()[:24] + '.json'
                if not (imp.out / path).exists():
                    imp.write(path, clip)
                library[key] = {'path': path, 'source': source, 'logical': logical, 'loop': loop}
            else:
                animations[key] = clip
        except Exception as exc:
            graph['unavailable'].append({'state': key, 'source': source, 'error': str(exc)})

    standing_logical = next((state['loop'] for state in graph['states'] if state['name'] == 'root'), 'loop_standing')
    standing = selected(standing_logical)
    humanoid = lat_paths[0]['lat'] in ('appearance/lat/all_m.lat', 'appearance/lat/all_f.lat')
    # Creature graphs use loop_stand and may call the fastest gait gallop or
    # jog. Select their run gait by authored root speed, not humanoid filenames.
    creature_gaits = []
    if not humanoid:
        for leaf in standing:
            if '_loc_' in leaf['source']:
                speed = locomotion_metadata(imp.read(leaf['source'])).get('source_speed_mps', 0)
                if speed > 0:
                    creature_gaits.append((speed * leaf.get('speed_scale', 1), leaf))
    for key, token in [('idle', None), ('walk', '_walk'), ('run', '_run')]:
        leaves = [x for x in standing if token in x['source']] if token else [x for x in standing if '_loc_' not in x['source']]
        if key == 'idle':
            leaves = [x for x in leaves if '_idl_' in x['source']] or [x for x in leaves if '_turn_' not in x['source']]
        if key == 'run' and creature_gaits:
            leaves = [max(creature_gaits, key=lambda gait: gait[0])[1]]
        if key == 'walk' and not leaves and creature_gaits:
            leaves = [min(creature_gaits, key=lambda gait: gait[0])[1]]
        if leaves:
            add(key, leaves[0], standing_logical)
        else:
            graph['unavailable'].append({'state': key, 'reason': 'No matching gait in original standing selector.', 'logical': standing_logical})
    for state, logical in [('crouch', 'loop_kneeling'), ('prone', 'loop_prone'), ('sit', 'loop_sitting_ground'), ('jump', 'jump')]:
        leaves = selected(logical)
        if leaves:
            add(state, leaves[0], logical, state != 'jump')
        if state == 'prone' and len(leaves) > 1:
            add('crawl', leaves[1], logical)
    # Source-authored ground incapacitation pose also supplies a frozen visual
    # for backend-confirmed DEAD actors; preserve their existing skinned outfit.
    incap = next((s for s in graph['states'] if s['name'] == 'incapacitated_face_up'), None)
    if incap:
        leaves = selected(incap['loop'])
        if len(leaves) == 1:
            add('incapacitated', leaves[0], incap['loop'], False, True)
    transitions = {'stand_to_crouch': 'trn_standing_to_kneeling', 'crouch_to_stand': 'trn_kneeling_to_standing',
                   'stand_to_prone': 'trn_standing_to_prone', 'prone_to_stand': 'trn_prone_to_standing',
                   'stand_to_sit': 'trn_standing_to_sitting_ground', 'sit_to_stand': 'trn_sitting_ground_to_standing'}
    for state, logical in transitions.items():
        leaves = selected(logical)
        if leaves:
            add(state, leaves[0], logical, False)
    # The crackdown carrier is an AiAgent whose native posture drives the
    # original shuttle graph. Its authored flight clips are visual only and
    # must not be treated as humanoid locomotion or move the network identity.
    if appearance == 'appearance/lamda_shuttle_faction_perk.sat':
        for state, logical, loop in [('carrier_land', 'land', False),
                                     ('carrier_takeoff', 'takeoff', False),
                                     ('carrier_ground', 'loop_ground', True),
                                     ('carrier_sky', 'loop_sky', True)]:
            leaves = selected(logical)
            if len(leaves) != 1:
                raise ValueError('Expected one original carrier clip for ' + logical)
            add(state, leaves[0], logical, loop, True)
    # These authored humanoid clips exist outside the default LAT's forward-only
    # locomotion selector. Explicit mappings are recorded, not invented graphs.
    for state, stem in {'strafe_left': 'all_b_loc_walking_side_step_left', 'strafe_right': 'all_b_loc_walking_side_step_right',
                        'backpedal': 'all_b_loc_walk_backwards', 'crouch_walk': 'all_b_loc_crouched_walk'}.items():
        if humanoid:
            add(state, {'source': 'appearance/animation/' + stem + '.ans'}, 'explicit_original_directional_clip')
    for state in ['fall', 'land', 'turn_left', 'turn_right']:
        graph['unavailable'].append({'state': state, 'reason': 'No standalone noncombat humanoid clip in source graph; runtime uses authored jump phases or stationary idle.'})
    emotes = ['wave', 'wave1', 'wave2', 'bow', 'nod', 'shrug', 'salute', 'point_forward', 'laugh', 'clap_rousing',
              'applause_polite', 'applause_excited', 'celebrate', 'beckon', 'stretch', 'yawn', 'sigh', 'shake_head_no', 'cheer']
    for command in emotes:
        logical = graph['actions'].get(command, 'emt_' + command)
        leaves = selected(logical)
        if leaves:
            add('emote_' + command, leaves[0], logical, False, True)
    for binding in lat_paths[1:]:
        _, face = load_lat(imp, binding['lat'])
        for logical in sorted(face):
            if logical.startswith('face_'):
                leaves = selected(logical, face)
                if leaves:
                    add(logical, leaves[0], logical, logical == 'face_idle', True)
    graph['exported_states'] = sorted(animations)
    graph['exported_actions'] = sorted(library)
    return {'animations': animations, 'animation_library': library, 'animation_graph': graph}


def locomotion_metadata(raw):
    """Read authored ANS root-travel speed without applying root translation."""
    r = parse_iff(raw)
    result = {'source_sha256': hashlib.sha256(raw).hexdigest()}
    loc = next(r.walk('LOCT'), None)
    if loc is None:
        return result
    # KFAT0003 uses 16-bit locomotion counts/frames too, independently of
    # its uncompressed rotation/translation channels (original load_0003).
    short_frames = r.tag == 'CKAT' or (r.tag == 'KFAT' and r.children[0].tag == '0003')
    count_format = '<fH' if short_frames else '<fI'
    record_format = '<h3f' if short_frames else '<i3f'
    speed, count = struct.unpack_from(count_format, loc.data)
    offset, size = struct.calcsize(count_format), struct.calcsize(record_format)
    if not count or len(loc.data) != offset + count * size:
        raise ValueError('Unexpected LOCT source-motion layout')
    first = struct.unpack_from(record_format, loc.data, offset)
    last = struct.unpack_from(record_format, loc.data, offset + (count - 1) * size)
    result.update({'source_speed_mps': speed,
                   'source_cycle_displacement': mirror([last[i] - first[i] for i in range(1, 4)]),
                   'source_motion_metadata': 'ANS/LOCT; visual cadence only, physics owns translation'})
    return result


def decode_clip(imp, path, bones, names):
    raw=imp.read(path)
    r=parse_iff(raw);assert r.tag in ('KFAT','CKAT');compressed=r.tag=='CKAT'
    fps,last_frame,_,_,_,_,_=struct.unpack('<f6h' if compressed else '<f6i',r.first('INFO').data)
    if compressed:
     rotations=[[(frame,*unpack_quaternion(packed,n.data[2:5])) for frame,packed in array(n.data[5:],'hI')] for n in (next(iter(r.walk('AROT')), None).children if next(iter(r.walk('AROT')), None) else [])]
     static_node=next(r.walk('SROT'),None)
     static_rot=[unpack_quaternion(packed,(x,y,z)) for x,y,z,packed in array(static_node.data if static_node else b'','3BI')]
     translations=[array(n.data[2:],'hf') for n in (next(iter(r.walk('ATRN')), None).children if next(iter(r.walk('ATRN')), None) else [])]
    else:
     rotations=[array(n.data[4:],'I4f') for n in (next(iter(r.walk('AROT')), None).children if next(iter(r.walk('AROT')), None) else [])]
     static_node=next(r.walk('SROT'),None)
     static_rot=array(static_node.data if static_node else b'','4f')
     translations=[array(n.data[4:],'If') for n in (next(iter(r.walk('ATRN')), None).children if next(iter(r.walk('ATRN')), None) else [])]
    static_trans=[v[0] for v in array(r.first('STRN').data,'f')];tracks=[]
    def sample(keys,frame):
     for j in range(1,len(keys)):
      if frame<=keys[j][0]:
       a,b=keys[j-1],keys[j];return a[1]+(b[1]-a[1])*(frame-a[0])/(b[0]-a[0]) if b[0]!=a[0] else b[1]
     return keys[-1][1]
    for n in r.first('XFRM').children:
     name,p=cstring(n.data);name=name.lower()
     if name not in names:continue
     animated,ri,mask,xi,yi,zi=struct.unpack_from('<BhB3h' if compressed else '<BiI3i',n.data,p);bi=names[name];bone=bones[bi]
     qr=rotations[ri] if animated else [(0,*static_rot[ri])]
     qkeys=[[frame/fps,*mirror_quaternion(qmul(bone['source_post_rotation'],qmul(q,qmul(bone['source_bind_rotation'],bone['source_pre_rotation']))))] for frame,*q in qr]
     channels=[translations[index] if mask&(8<<axis) else [(0,static_trans[index])] for axis,index in enumerate((xi,yi,zi))]
     times=sorted(set(frame for keys in channels for frame,_ in keys));pkeys=[]
     for frame in times:
      delta=mirror([sample(keys,frame) for keys in channels]);pkeys.append([frame/fps,*[bone['rest_position'][j]+delta[j] for j in range(3)]])
     tracks.append({'bone':bi,'name':name,'rotations':qkeys,'positions':pkeys})
    return {'fps':fps,'length':last_frame/fps,'source':path,'tracks':tracks,'root_motion':'ignored; gameplay controller drives translation',**locomotion_metadata(raw)}
