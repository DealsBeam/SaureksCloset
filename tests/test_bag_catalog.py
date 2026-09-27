"""Validate every shipped bag, its saved identity, original atlas and client layout."""
import hashlib
import io
import json
import math
from pathlib import Path
import re
import struct as S
import sys
import tempfile

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from build_bag_model import read_glb, write_m2, write_blp
from build_bag_catalog import LEGACY, TARGET_HEIGHT, CLOTH_POUCH, lua_catalog

source_entries = json.loads((ROOT / 'assets/bags/catalog.json').read_text())
manifest = json.loads((ROOT / 'native/BAG-ASSETS.json').read_text())
assert manifest['schema'] == 2
bags = manifest['bags']
assert len(source_entries) == 15 and len(bags) == 16
assert [b['id'] for b in bags] == list(range(1, 17))
assert len({b['origin'] for b in bags}) == len(bags)
assert {e['source'] for e in source_entries} == {p.name for p in (ROOT / 'assets/bags').glob('*.glb')}
assert source_entries == [{k: b[k] for k in e} for e, b in zip(source_entries, bags[1:])]
assert {e['id'] for e in source_entries if e.get('retired')} == {3, 4, 6, 9, 15}
assert {e['id']: e['replacement'] for e in source_entries if e.get('replacement')} == {15: 16}
lua = (ROOT / 'addon/SaureksCloset/BagCatalog.lua').read_text()
header = (ROOT / 'native/BagCatalog.h').read_text()
assert lua == lua_catalog([LEGACY] + source_entries), 'Regeneration must preserve retired model choices'
assert [int(i) for i in re.findall(r'\{id=(\d+),', lua.split('V.bagCatalogByID={}')[0])] == [1, 2, 5, 7, 8, 10, 11, 12, 13, 14, 16]
assert CLOTH_POUCH['id'] == 16 and CLOTH_POUCH['name'] == 'Cloth Pouch'
assert [(c['id'], c['name']) for c in CLOTH_POUCH['colors']] == [(12, 'Burgundy'), (13, 'Navy'), (14, 'Ochre'), (16, 'Olive')]
assert len(re.findall(r'^    V.bagCatalogByID\[\d+\],', lua, re.M)) == 7
for model_id in [1, 2, 5, 7, 8, 10, 11, 12, 13, 14, 16]:
    assert json.dumps('Interface\\AddOns\\SaureksCloset\\Textures\\BagIcon%d.tga' % model_id) in lua
assert len(re.findall(r'^    \{\d+,', header, re.M)) == len(bags)
all_files = {'ASSETS-LICENSE'}
triangles_total = 0
quality = []
cloth_geometry = None
cloth_textures = set()
for bag in bags:
    source = ROOT / 'assets/DarkSchoolbag.glb' if bag['id'] == 1 else ROOT / 'assets/bags' / bag['source']
    assert hashlib.sha256(source.read_bytes()).hexdigest() == bag['source_sha256']
    vertices, triangles, atlas = read_glb(source)
    if bag['id'] in {c['id'] for c in CLOTH_POUCH['colors']}:
        geometry = (vertices, triangles)
        if cloth_geometry is None:
            cloth_geometry = geometry
        assert geometry == cloth_geometry, 'A color choice must use the same positions, normals, UVs and triangles'
        cloth_textures.add(hashlib.sha256(atlas).hexdigest())
    source_height = max(p[2] for p, _, _ in vertices) - min(p[2] for p, _, _ in vertices)
    factor = 1 if bag['id'] == 1 else TARGET_HEIGHT / source_height
    assert factor == bag['normalization_scale']
    if bag['id'] != 1:
        vertices = [(tuple(c * factor for c in p), n, uv) for p, n, uv in vertices]
    folder = ROOT / 'addon/SaureksCloset/Models'
    model_path, blp_path = folder / bag['model'], folder / bag['texture']
    all_files |= {model_path.name, blp_path.name}
    model, blp = model_path.read_bytes(), blp_path.read_bytes()
    assert hashlib.sha256(model).hexdigest() == bag['model_sha256']
    assert hashlib.sha256(blp).hexdigest() == bag['blp_sha256']
    assert model[:8] == b'MD20\0\1\0\0'

    def array(offset, stride):
        count, start = S.unpack_from('<II', model, offset)
        assert count > 0 and start >= 0x144 and start + count * stride <= len(model)
        return count, start

    n, offset = array(0x44, 48)
    assert n == bag['vertices'] == len(vertices) and n < 65536
    positions = []
    for i in range(n):
        values = S.unpack_from('<3f8B3f4f', model, offset + i * 48)
        assert all(math.isfinite(v) for v in values)
        assert values[3:11] == (255, 0, 0, 0, 0, 0, 0, 0)
        assert abs(sum(v*v for v in values[11:14]) - 1) < .001
        assert all(0 <= v <= 1 for v in values[14:16])
        positions.append(values[:3])
    low, high = S.unpack_from('<3f', model, 0xb4), S.unpack_from('<3f', model, 0xc0)
    assert low == tuple(min(p[i] for p in positions) for i in range(3))
    assert high == tuple(max(p[i] for p in positions) for i in range(3))
    assert high[0] == 0 and low[0] < 0
    assert abs(low[1] + high[1]) < .00001 and abs(low[2] + high[2]) < .00001
    assert abs(high[2] - low[2] - TARGET_HEIGHT) < .00001
    count, bone = array(0x34, 108)
    assert count == 1 and S.unpack_from('<h', model, bone + 8)[0] == -1
    count, view = array(0x4c, 44)
    assert count == 1
    ni, offset = array(view, 2)
    assert ni == n and S.unpack_from('<' + 'H' * n, model, offset) == tuple(range(n))
    nt, offset = array(view + 8, 2)
    assert nt == len(triangles) == bag['triangles'] * 3 and nt < 65536
    assert S.unpack_from('<' + 'H' * nt, model, offset) == tuple(triangles)
    assert max(triangles) < n
    count, offset = array(view + 24, 32)
    assert count == 1 and S.unpack_from('<10H', model, offset)[2:10] == (0, n, 0, nt, 1, 0, 1, 0)
    assert array(view + 32, 24)[0] == 1
    count, texture = array(0x5c, 16)
    assert count == 1
    kind, flags, length, offset = S.unpack_from('<4I', model, texture)
    expected_texture = ('Interface\\AddOns\\SaureksCloset\\Models\\' + bag['texture'] + '\0').encode()
    assert kind == 2 and flags == 0 and model[offset:offset + length] == expected_texture
    expected_model = json.dumps('Interface\\AddOns\\SaureksCloset\\Models\\' + bag['stem'] + '.mdx')
    assert (expected_model not in lua) if bag.get('retired') else (expected_model in lua)
    assert expected_model in header
    assert json.dumps(expected_texture[:-1].decode()) in header
    width = 128 if bag['id'] == 1 else bag['source_atlas_size'][0]
    assert S.unpack_from('<4sI4BII', blp) == (b'BLP2', 1, 2, 0, 0, 1, width, width)
    levels = int(math.log2(width)) + 1
    offsets, sizes = S.unpack_from('<16I', blp, 20), S.unpack_from('<16I', blp, 84)
    end = 1172
    for i in range(levels):
        side = max(1, width >> i)
        size = max(1, (side + 3) // 4) ** 2 * 8
        assert offsets[i] == end and sizes[i] == size
        end += size
    assert end == len(blp) and not any(offsets[levels:]) and not any(sizes[levels:])
    image = Image.open(io.BytesIO(atlas)).convert('RGB').resize((width, width), Image.Resampling.LANCZOS)
    decoded = Image.open(blp_path).convert('RGB')
    assert image.size == decoded.size
    error = sum((a-b)**2 for p, q in zip(image.get_flattened_data(), decoded.get_flattened_data()) for a, b in zip(p, q)) / (width*width*3)
    psnr = 10 * math.log10(255**2/error)
    assert psnr > 28, (bag['name'], psnr)
    quality.append(psnr)
    with tempfile.TemporaryDirectory() as temp:
        m2_out, blp_out = Path(temp) / 'test.m2', Path(temp) / 'test.blp'
        write_m2(vertices, triangles, m2_out, bag['stem'])
        write_blp(atlas, blp_out, size=128 if bag['id'] == 1 else None)
        assert m2_out.read_bytes() == model and blp_out.read_bytes() == blp
    triangles_total += bag['triangles']
assert {p.name for p in (ROOT / 'addon/SaureksCloset/Models').iterdir() if p.is_file()} == all_files
assert len(cloth_textures) == 4
print('PASS: 8 bag choices, 4 cloth colors, 11 active assets, 5 retired IDs; all 16 compatibility assets retain stable IDs, centered normalized meshes, bounded M2 arrays, matching atlases, full mip chains, deterministic rebuilds; %d triangles total; minimum texture fidelity %.1f dB.' % (triangles_total, min(quality)))
