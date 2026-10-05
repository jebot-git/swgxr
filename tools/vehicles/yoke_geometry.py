"""Identify detached original steering geometry; never cut connected hull triangles."""
import math

def steering_component(model, controls):
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
