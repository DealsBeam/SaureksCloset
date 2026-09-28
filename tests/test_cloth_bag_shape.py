"""Guard the corrected cloth volume independently of its export recipe."""
from collections import Counter, defaultdict
from pathlib import Path
import sys

import numpy as np

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from build_bag_model import read_glb


def inspect(path):
    raw,indices,_=read_glb(path)
    # UV seams duplicate render vertices; join by position for geometry tests.
    points=[];lookup={};remap=[]
    for position,_,_ in raw:
        key=tuple(round(v,6) for v in position)
        if key not in lookup:lookup[key]=len(points);points.append(position)
        remap.append(lookup[key])
    points=np.asarray(points);faces=np.asarray(remap)[np.asarray(indices).reshape(-1,3)]
    neighbors=defaultdict(set)
    for a,b,c in faces:
        neighbors[a].update((b,c));neighbors[b].update((a,c));neighbors[c].update((a,b))
    unseen=set(neighbors);components=[]
    while unseen:
        root=unseen.pop();component={root};pending=[root]
        while pending:
            new=neighbors[pending.pop()]&unseen
            unseen-=new;component|=new;pending.extend(new)
        component_faces=faces[np.array([int(f[0]) in component for f in faces])]
        components.append((component,component_faces))
    components.sort(key=lambda item:len(item[1]),reverse=True)
    # The closed body and closed flap are the two largest connected surfaces.
    assert len(components)>=2
    for label,(vertices,triangles) in zip(('body','flap'),components[:2]):
        edges=Counter(tuple(sorted((int(a),int(b)))) for tri in triangles for a,b in zip(tri,np.roll(tri,-1)))
        assert set(edges.values())=={2},label+' must remain a closed surface'
        cloud={tuple(round(v,5) for v in p) for p in points[list(vertices)]}
        for x,y,z in cloud:
            assert (x,round(-y,5),z) in cloud,label+' lost left/right volume symmetry'
        p=points[triangles]
        volume=np.sum(p[:,0]*np.cross(p[:,1],p[:,2]))/6
        assert volume>0,label+' normals must face outward'
    return len(faces)


if __name__=='__main__':
    total=0
    for color in ('Olive','Burgundy','Navy','Ochre'):
        total+=inspect(ROOT/'assets/bags'/f'{color}ClothPouchLow.glb')
    print('PASS: four cloth colors retain closed, outward-facing, symmetric body and flap volumes; %d checked triangles'%total)
