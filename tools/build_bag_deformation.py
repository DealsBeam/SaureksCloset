"""Small shared volume rig; runtime supplies local motion, no race-specific clips."""
import itertools
import math
import struct as S

from build_bag_model import write_m2

MARKER = b'ClosetBagV3\0'
GRID = (3, 4, 5)
PALETTE_LIMIT = 21


def volume_rig(points):
    low = [min(p[i] for p in points) for i in range(3)]
    high = [max(p[i] for p in points) for i in range(3)]
    assert all(b > a for a, b in zip(low, high))
    nodes = [tuple(low[i]+q[i]*(high[i]-low[i])/(GRID[i]-1) for i in range(3))
             for q in itertools.product(*[range(n) for n in GRID])]
    weights, bones = [], []
    for p in points:
        coord = [(p[i]-low[i])/(high[i]-low[i])*(GRID[i]-1) for i in range(3)]
        cell = [min(GRID[i]-2, max(0, math.floor(coord[i]))) for i in range(3)]
        fraction = [max(0, min(1, coord[i]-cell[i])) for i in range(3)]
        order = sorted(range(3), key=lambda i: (-fraction[i], i))
        f = [fraction[i] for i in order]
        w = [1-f[0], f[0]-f[1], f[1]-f[2], f[2]]
        corners = [cell.copy()]
        for axis in order:
            cell = cell.copy(); cell[axis] += 1; corners.append(cell)
        ids = [1+(q[0]*GRID[1]+q[1])*GRID[2]+q[2] for q in corners]
        quantized = [int(math.floor(v*255)) for v in w]
        for i in sorted(range(4), key=lambda i: (-(w[i]*255-quantized[i]), i))[:255-sum(quantized)]:
            quantized[i] += 1
        weights.append(quantized); bones.append(ids)
    return nodes, weights, bones


def write_deformable_m2(vertices, triangles, path, model_name):
    # Retain the already-tested rigid file's material/texture/Stand records.
    report = write_m2(vertices, triangles, path, model_name)
    data = bytearray(path.read_bytes())
    points = [v[0] for v in vertices]
    nodes, weights, bones = volume_rig(points)
    def block(blob):
        data.extend(bytes(-len(data) % 16)); at = len(data); data.extend(blob); return at
    def array(at, count, blob):
        S.pack_into('<II', data, at, count, block(blob) if count else 0)
    array(8, len(MARKER), MARKER)
    empty = S.pack('<Hh6I', 0, -1, 0, 0, 0, 0, 0, 0)
    root = S.pack('<iIhH', -1, 0, -1, 0)+empty*3+S.pack('<3f', 0, 0, 0)
    records = [root]+[S.pack('<iIhH', -1, 0x200, 0, 0)+empty*3+S.pack('<3f', *p) for p in nodes]
    array(0x34, len(records), b''.join(records))
    array(0x44, len(vertices), b''.join(S.pack('<3f8B3f4f', *p, *weights[i], *bones[i], *n, *uv, 0, 0)
                                      for i, (p, n, uv) in enumerate(vertices)))
    batches = []
    for at in range(0, len(triangles), 3):
        face = triangles[at:at+3]
        needed = {bones[v][j] for v in face for j in range(4) if weights[v][j]}
        choices = [(len(needed-palette), len(needed|palette), i) for i, (palette, _) in enumerate(batches)
                   if len(needed|palette) <= PALETTE_LIMIT]
        if choices:
            index = min(choices)[2]; batches[index][0].update(needed); batches[index][1].append(face)
        else:
            batches.append((needed, [face]))
    lookup, indices, properties, palettes, sections = [], [], bytearray(), [], []
    for palette, faces in batches:
        palette = sorted(palette); mapping = {}; start = len(lookup); first = len(indices); bone_start = len(palettes)
        local = {bone: i for i, bone in enumerate(palette)}
        for face in faces:
            for vertex in face:
                if vertex not in mapping:
                    mapping[vertex] = len(lookup); lookup.append(vertex)
                    properties.extend(local[bones[vertex][j]] if weights[vertex][j] else 0 for j in range(4))
                indices.append(mapping[vertex])
        palettes.extend(palette)
        center = [sum(points[v][i] for v in mapping)/len(mapping) for i in range(3)]
        influences = max(sum(w > 0 for w in weights[v]) for v in mapping)
        sections.append(S.pack('<10H3f', 0, 0, start, len(mapping), first, len(indices)-first,
                               len(palette), bone_start, influences, 0, *center))
    assert len(lookup) < 65536 and len(indices) < 65536 and len(palettes) < 65536
    view = block(bytes(44)); S.pack_into('<II', data, 0x4c, 1, view)
    array(view, len(lookup), S.pack('<'+'H'*len(lookup), *lookup))
    array(view+8, len(indices), S.pack('<'+'H'*len(indices), *indices))
    array(view+16, len(lookup), properties)
    array(view+24, len(sections), b''.join(sections))
    array(view+32, len(sections), b''.join(S.pack('<4Hh7H', 16, 0, i, i, -1, 0, 0, 1, 0, 0, 0, 0) for i in range(len(sections))))
    S.pack_into('<I', data, view+40, PALETTE_LIMIT)
    array(0x8c, len(palettes), S.pack('<'+'H'*len(palettes), *palettes))
    # Cover the bounded local motion in the culling envelope; the actual rest
    # bounds remain recoverable from the lattice pivots without private data.
    low, high = report['bounds']; margin = (high[2]-low[2])*.22
    bounds = S.pack('<7f', *[v-margin for v in low], *[v+margin for v in high],
                    max(math.sqrt(sum(c*c for c in p)) for p in points)+margin*math.sqrt(3))
    data[0xb4:0xd0] = bounds
    sequence = S.unpack_from('<I', data, 0x20)[0]; data[sequence+36:sequence+64] = bounds
    path.write_bytes(data)
    report.update(bytes=len(data), bones=len(records), submeshes=len(sections), view_vertices=len(lookup),
                  deformation='ClosetBagV3', palette_limit=PALETTE_LIMIT)
    return report
