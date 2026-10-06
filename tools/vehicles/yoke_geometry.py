"""Partition audited original steering triangles; never synthesize replacement art."""
import math

def steering_component(model, controls):
    if model.get("source_appearance")=="appearance/flash_speeder.apt":
        return flash_component(model,controls)
    if model.get("source_appearance") in ("appearance/speeder_bike.apt", "appearance/swoop_bike.apt"):
        return bike_component(model, controls)
    pivot=[sum(p[i] for p in controls)/2 for i in range(3)]
    candidates=[]
    for si,surface in enumerate(model['surfaces']):
        vertices=list(zip(*[iter(surface['vertices'])]*3))
        triangles=list(zip(*[iter(surface['indices'])]*3))
        parents=list(range(len(triangles)));seen={}
        def root(i):
            while parents[i]!=i:
                parents[i]=parents[parents[i]];i=parents[i]
            return i
        for ti,triangle in enumerate(triangles):
            for vi in triangle:
                key=tuple(round(v,5) for v in vertices[vi])
                if key in seen:parents[root(ti)]=root(seen[key])
                else:seen[key]=ti
        groups={}
        for ti in range(len(triangles)):groups.setdefault(root(ti),[]).append(ti)
        for group in groups.values():
            points=[vertices[vi] for ti in group for vi in triangles[ti]]
            lo=[min(p[i] for p in points) for i in range(3)];hi=[max(p[i] for p in points) for i in range(3)]
            extent=[hi[i]-lo[i] for i in range(3)]
            distance=math.dist([(hi[i]+lo[i])/2 for i in range(3)],pivot)
            if len(group)>=8 and .10<extent[0]<.42 and max(extent)<.42 and distance<.20:
                candidates.append((distance,si,group,lo,hi))
    if len(candidates)!=1:
        return {'status':'unsupported','reason':'No unique detached original steering component within source riding grips','candidate_count':len(candidates)}
    _,surface,triangles,lo,hi=candidates[0]
    return {'status':'ready','surface':surface,'triangles':triangles,'pivot':pivot,'bounds_min':lo,'bounds_max':hi,'source':'Complete welded source triangle component near original rider hold sockets; no replacement geometry'}


def source_components(surface, weld_positions=True):
    """Retain authored vertex seams when requested, otherwise weld position copies."""
    vertices=list(zip(*[iter(surface['vertices'])]*3))
    triangles=list(zip(*[iter(surface['indices'])]*3))
    parents=list(range(len(triangles)));seen={}
    def root(i):
        while parents[i]!=i:
            parents[i]=parents[parents[i]];i=parents[i]
        return i
    for ti,triangle in enumerate(triangles):
        for vi in triangle:
            key=tuple(round(v,5) for v in vertices[vi]) if weld_positions else vi
            if key in seen:parents[root(ti)]=root(seen[key])
            else:seen[key]=ti
    groups={}
    for ti in range(len(triangles)):groups.setdefault(root(ti),[]).append(ti)
    result=[]
    for group in groups.values():
        points=[vertices[vi] for ti in group for vi in triangles[ti]]
        result.append({'triangles':group,'bounds_min':[min(p[i] for p in points) for i in range(3)],'bounds_max':[max(p[i] for p in points) for i in range(3)]})
    return result


def bike_component(model, controls):
    """Use complete source components at audited handle/stem seams, not a box cut.

    The swoop joins its bar base to the body at six duplicated position vertices;
    those vertices are already split in the source index/normal topology. A VR
    steering transform is our extension: neither original saddle has a steering
    bone, hardpoint or authored animation.
    """
    swoop=model['source_appearance']=='appearance/swoop_bike.apt'
    surface_index=0 if swoop else 1
    surface=model['surfaces'][surface_index]
    groups=source_components(surface,weld_positions=not swoop)
    selected=[]
    for group in groups:
        lo=group['bounds_min'];hi=group['bounds_max']
        if swoop:
            keep=lo[1]>.83 and lo[2]>-.39 and hi[2]<-.31 and lo[0]>-.28 and hi[0]<.28
        else:
            keep=lo[1]>.80 and hi[1]>1.29 and lo[2]>-1.10 and hi[2]<-.74 and lo[0]>-.30 and hi[0]<.30
        if keep:selected.append(group)
    expected=sorted([6,6,16,16,22,66] if swoop else [101,36,44,34]*2)
    actual=sorted(len(g['triangles']) for g in selected)
    if actual!=expected:
        return {'status':'unsupported','reason':'Original bike handlebar component topology differs from audited source; refusing an arbitrary hull cut','component_triangle_counts':actual,'expected_triangle_counts':expected}
    triangles=sorted(t for group in selected for t in group['triangles'])
    vertices=list(zip(*[iter(surface['vertices'])]*3));source_triangles=list(zip(*[iter(surface['indices'])]*3))
    selected_set=set(triangles)
    points=[vertices[i] for ti in triangles for i in source_triangles[ti]]
    selected_positions={tuple(round(v,5) for v in p) for p in points}
    other_positions={tuple(round(v,5) for v in vertices[i]) for ti,t in enumerate(source_triangles) if ti not in selected_set for i in t}
    pivot=[sum(p[i] for p in controls)/2 for i in range(3)]
    return {'status':'ready','surface':surface_index,'triangles':triangles,'pivot':pivot,
            'bounds_min':[min(p[i] for p in points) for i in range(3)],'bounds_max':[max(p[i] for p in points) for i in range(3)],
            'component_count':len(selected),'component_triangle_counts':actual,
            'source':'Original swoop bar, stem and grips at source vertex/normal seams' if swoop else 'Eight complete detached original speederbike grip, lever and stem/cable components',
            'partition_method':'authored_index_seams' if swoop else 'complete_position_welded_components',
            'shared_attachment_positions':sorted(selected_positions&other_positions),
            'grip_vertex_distances':[min(math.dist(grip,p) for p in points) for grip in controls],
            'coordinate_system':'Godot Y-up, -Z vehicle forward; pivot is original human rider hold_l/hold_r midpoint',
            'motion_policy':'VR extension rotates original steering triangles about Y for fore/aft handle movement; original saddle supplies no steering bone or animation. Attachment seam motion is not an original articulated mechanism.'}


def flash_component(model,controls):
    """Original driver wheel excluding its stationary steering column."""
    surface=model['surfaces'][1];selected=[]
    for component in source_components(surface,weld_positions=False):
        lo=component['bounds_min'];hi=component['bounds_max']
        if lo[0]>-.44 and hi[0]<-.05 and lo[1]>.93 and hi[1]<1.15 and lo[2]>-.60 and hi[2]<-.47:selected.append(component)
    counts=sorted(len(c['triangles']) for c in selected)
    expected=sorted([2,2,8,9,2,2,2,2,1,1,2,4,1,1,2,9,8,2,2,2,2,2,2,2])
    if counts!=expected:return {'status':'unsupported','reason':'Flash driver wheel source seams differ from audited topology','component_triangle_counts':counts}
    triangles=sorted(i for c in selected for i in c['triangles']);chosen=set(triangles)
    vertices=list(zip(*[iter(surface['vertices'])]*3));ts=list(zip(*[iter(surface['indices'])]*3));points=[vertices[v] for ti in triangles for v in ts[ti]]
    a={tuple(round(x,5) for x in p) for p in points};b={tuple(round(x,5) for x in vertices[v]) for ti,t in enumerate(ts) if ti not in chosen for v in t}
    return {'status':'ready','surface':1,'triangles':triangles,'pivot':[sum(p[i] for p in controls)/2 for i in range(3)],'bounds_min':[min(p[i] for p in points) for i in range(3)],'bounds_max':[max(p[i] for p in points) for i in range(3)],'component_count':len(selected),'component_triangle_counts':counts,'source':'Original Flash driver yoke at source vertex/normal seams; ten steering-column triangles remain stationary','partition_method':'authored_index_seams','shared_attachment_positions':sorted(a&b),'grip_vertex_distances':[min(math.dist(g,p) for p in points) for g in controls],'coordinate_system':'Godot Y-up, -Z vehicle forward; pivot is original human rider hold_l/hold_r midpoint','motion_policy':'VR extension rotates original yoke around Z; original model supplies no steering bone or animation.'}
