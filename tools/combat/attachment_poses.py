"""Bake original stow-pose hold transforms relative to animated torso bones.

These are derived VR mounts, not invented hip/back hardpoints in the source data.
No source stow animation is played on the user's tracked hands or physics body.
"""
import math
from character_animations import decode_clip

SOURCES = {
    'hip': ('appearance/animation/all_b_cbt_pistol_standing_stow_pistol_holster.ans', 'root', 'hold_r'),
    'back': ('appearance/animation/all_b_int_stow_object_backpack.ans', 'spine3', 'hold_l'),
}


def sample(keys, time, quaternion=False):
    a = keys[0]
    for b in keys[1:]:
        if time <= b[0]:
            fraction = max(0, (time-a[0]) / max(1e-9, b[0]-a[0]))
            av, bv = list(a[1:]), list(b[1:])
            if quaternion:
                av = normalized(av); bv = normalized(bv)
                dot = sum(x*y for x,y in zip(av,bv))
                if dot < 0: bv = [-x for x in bv]; dot = -dot
                if dot < 0.9995:
                    angle = math.acos(max(-1, min(1, dot)))
                    return [(math.sin((1-fraction)*angle)*x + math.sin(fraction*angle)*y) / math.sin(angle) for x,y in zip(av,bv)]
            return [x*(1-fraction)+y*fraction for x,y in zip(av,bv)]
        a = b
    return list(a[1:])


def normalized(values):
    length = math.sqrt(sum(v*v for v in values))
    return [v/length for v in values]


def multiply(a, b):
    return [[sum(a[i][k]*b[k][j] for k in range(4)) for j in range(4)] for i in range(4)]


def inverse_rigid(a):
    result = [[a[j][i] for j in range(3)]+[-sum(a[k][i]*a[k][3] for k in range(3))] for i in range(3)]
    return result+[[0,0,0,1]]


def flatten(a):
    return [value for row in a[:3] for value in row]


def transform(position, rotation):
    x,y,z,w = normalized(rotation)
    return [[1-2*(y*y+z*z),2*(x*y-z*w),2*(x*z+y*w),position[0]],
            [2*(x*y+z*w),1-2*(x*x+z*z),2*(y*z-x*w),position[1]],
            [2*(x*z-y*w),2*(y*z+x*w),1-2*(x*x+y*y),position[2]],
            [0,0,0,1]]


def evaluate(bones, clip, frame):
    tracks = {t['name']:t for t in clip['tracks']}
    result = []
    for bone in bones:
        track = tracks.get(bone['name'])
        pose = transform(sample(track['positions'],frame/clip['fps']),sample(track['rotations'],frame/clip['fps'],True)) if track else transform(bone['rest_position'],bone['rest_rotation'])
        result.append(multiply(result[bone['parent']],pose) if bone['parent']>=0 else pose)
    return result



def back_carry_frame(model, anchor='spine3'):
    """Derive a resting carry envelope, separate from the animated hand reach.

    Source body axes are Godot Y-up / +Z-back. Only torso-weighted vertices
    between pelvis and neck contribute, avoiding hair, arms and long species ears.
    """
    bones = model['bones']; names = {b['name']:i for i,b in enumerate(bones)}
    rest = evaluate(bones, {'tracks': [], 'fps': 30}, 0)
    anchor_rest = rest[names[anchor]]
    pelvis = rest[names['root']]
    shoulder = rest[names['neck']]
    torso_bones = {i for i,b in enumerate(bones) if b['name']=='root' or b['name'].startswith('spine')}
    points = []
    for part in model.get('parts', []):
        for surface in part.get('mesh', {}).get('surfaces', []):
            vertices = surface.get('vertices', []); count = len(vertices)//3
            joints = surface.get('bones', []); weights = surface.get('weights', [])
            influences = len(joints)//count if count else 0
            for i in range(count):
                point = vertices[i*3:i*3+3]
                total = sum(weights[i*influences+j] for j in range(influences)
                            if joints[i*influences+j] in torso_bones)
                if total >= .5 and pelvis[1][3] <= point[1] <= shoulder[1][3]:
                    points.append(point)
    if not points:
        raise ValueError('No source torso skin vertices for back carry envelope')
    back = max(p[2] for p in points)
    center = [anchor_rest[0][3], anchor_rest[1][3], back]
    inv = inverse_rigid(anchor_rest)
    local_point = lambda p: [sum(inv[i][j]*p[j] for j in range(3))+inv[i][3] for i in range(3)]
    local_axis = lambda p: [sum(inv[i][j]*p[j] for j in range(3)) for i in range(3)]
    return {'center':local_point(center), 'shoulder':local_point([shoulder[i][3] for i in range(3)]),
            'up':local_axis([0,1,0]), 'back':local_axis([0,0,1]), 'torso_vertex_count':len(points),
            'derivation':'Resting visual carry uses spine3 height and rear surface of source torso-weighted body vertices, capped at source neck height; independent over-shoulder grab uses original animated hold pose.'}

def bake(imp, model, frames):
    bones = model['bones']; names = {b['name']:i for i,b in enumerate(bones)}
    mounts = {}
    for mount,(source,anchor,hold) in SOURCES.items():
        clip = decode_clip(imp,source,bones,names)
        frame = frames[mount]
        pose = evaluate(bones,clip,frame)
        local = multiply(inverse_rigid(pose[names[anchor]]),pose[names[hold]])
        rest = evaluate(bones, {'tracks':[], 'fps':30}, 0)
        mirror = [[-1,0,0,0],[0,1,0,0],[0,0,1,0],[0,0,0,1]]
        anchor_rest = rest[names[anchor]]
        left_local = multiply(multiply(multiply(multiply(inverse_rigid(anchor_rest),mirror),anchor_rest),local),mirror)
        mounts[mount] = {'left_matrix':flatten(left_local), 'anchor_rest_matrix':flatten(anchor_rest), 'source':source,'source_sha256':clip['source_sha256'],'frame':frame,'fps':clip['fps'],
                         'anchor_bone':anchor,'hold_bone':hold,'matrix':flatten(local),
                         'derivation':'original hold bone at selected stow contact frame relative to source anchor; left dominance mirrors sagittally'}
        if mount == 'back': mounts[mount]['carry_frame'] = back_carry_frame(model,anchor)
    return mounts
