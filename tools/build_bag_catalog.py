"""Import production bags and build their stable Lua/native catalog and client assets.

Use --import-directory once for newly delivered GLBs. Checked-in catalog IDs are
append-only; normal rebuilds use the self-contained assets/bags source snapshot.
"""
import argparse
import hashlib
import io
import json
from pathlib import Path
import re
import shutil

from PIL import Image
from build_bag_model import ROOT, read_glb, write_m2, write_blp

SOURCE = ROOT / 'assets/bags'
OUTPUT = ROOT / 'addon/SaureksCloset/Models'
MODEL_PREFIX = 'Interface\\AddOns\\SaureksCloset\\Models\\'
LEGACY = {'id': 1, 'name': 'Runecloth Bag', 'stem': 'DarkSchoolbag',
          'source': 'DarkSchoolbag.glb', 'origin': 'assets/DarkSchoolbag.glb', 'material': 'cloth'}
TARGET_HEIGHT = 1.239
CLOTH_BAKE = SOURCE / 'cloth-run.npz'
CLOTH_IDS = {12, 13, 14, 16}
# These assets have identical geometry and UVs; only their cloth atlas changes.
# UI grouping never renumbers the underlying renderer/saved-look model IDs.
CLOTH_POUCH = {'id': 16, 'name': 'Mageweave Bag', 'material': 'cloth', 'colors': [
    {'id': 12, 'name': 'Burgundy', 'r': .48, 'g': .18, 'b': .22},
    {'id': 13, 'name': 'Navy', 'r': .18, 'g': .28, 'b': .43},
    {'id': 14, 'name': 'Ochre', 'r': .67, 'g': .46, 'b': .20},
    {'id': 16, 'name': 'Olive', 'r': .39, 'g': .43, 'b': .22},
]}
SLIM_LEATHER = {'id': 5, 'name': 'Slim Leather Bag', 'material': 'leather', 'colors': [
    {'id': 5, 'name': 'Brown', 'r': .55, 'g': .28, 'b': .11},
    {'id': 7, 'name': 'Dark Brown', 'r': .26, 'g': .14, 'b': .07},
    {'id': 8, 'name': 'Tan', 'r': .77, 'g': .54, 'b': .28},
]}
BAG_GROUPS = [SLIM_LEATHER, CLOTH_POUCH]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def validate_cloth_bake_geometry(vertices, triangles, bake=CLOTH_BAKE):
    """A bake belongs to the exact rest mesh/atlas layout being regenerated."""
    import numpy as np
    with np.load(bake, allow_pickle=False) as values:
        for key, expected in [('vertices', [p for p, _, _ in vertices]),
                              ('normals', [n for _, n, _ in vertices]),
                              ('uv', [uv for _, _, uv in vertices])]:
            actual, expected = values[key], np.asarray(expected)
            assert actual.shape == expected.shape and np.allclose(actual, expected, rtol=0, atol=1e-6), 'Stale cloth bake: '+key
        assert np.array_equal(values['triangles'].reshape(-1), triangles), 'Stale cloth bake: triangles'


def validate_bake_material(entry, bake=CLOTH_BAKE):
    """Material settings belong to the selected model's bake, not a global knob."""
    import numpy as np
    assert entry['material'] == 'cloth', 'A cloth bake cannot animate a different material'
    with np.load(bake, allow_pickle=False) as values:
        has_material='material_name' in values and 'material_config_sha256' in values
        assert has_material or 'clip_ids' not in values, 'V2 bake has no material provenance'
        if not has_material:return {'name':'cloth','preset':'legacy-v1'}
        assert 'clip_ids' in values and len(values['clip_ids'])==5 and set(values['clip_ids'].tolist())=={37,38,39,40,187}, 'Material bake is incomplete; all jump, fall and landing clips are required'
        name=str(values['material_name'].item())
        config_hash=str(values['material_config_sha256'].item())
    assert name==entry['material'], 'Selected bag and baked material disagree'
    config=SOURCE/'materials.json'
    profiles=json.loads(config.read_text())
    assert name in profiles['presets'], 'Unknown bag material'
    assert config_hash==digest(config), 'Material settings changed; rebake before exporting'
    return {'name':name,'preset':profiles['presets'][name],'source_sha256':config_hash}


def imported_name(stem):
    return stem.replace('_WoW_Low', '_Low').replace('_', ' ')


def import_material(stem):
    """Initial classification is stored per asset and can then be refined."""
    name = stem.lower()
    return 'cloth' if 'cloth' in name else 'leather' if 'leather' in name or 'milloo' in name else 'canvas'


def import_directory(directory):
    SOURCE.mkdir(parents=True, exist_ok=True)
    manifest_path = SOURCE / 'catalog.json'
    entries = json.loads(manifest_path.read_text()) if manifest_path.exists() else []
    by_origin = {entry['origin']: entry for entry in entries}
    found = sorted(directory.rglob('*.glb'))
    assert found, 'No production GLBs found'
    for source in found:
        origin = source.relative_to(directory).as_posix()
        entry = by_origin.get(origin)
        if entry is None:
            stem = re.sub('[^A-Za-z0-9]', '', source.stem.replace('_WoW_Low', '_Low'))
            assert stem and stem not in {e['stem'] for e in entries} | {LEGACY['stem']}
            entry = {'id': max([1] + [e['id'] for e in entries]) + 1,
                     'name': imported_name(source.stem), 'stem': stem,
                     'source': stem + '.glb', 'origin': origin, 'material': import_material(source.stem)}
            entries.append(entry)
        shutil.copyfile(source, SOURCE / entry['source'])
    # Missing an old input is an error, never a silent deletion or renumbering.
    assert {e['origin'] for e in entries} == {p.relative_to(directory).as_posix() for p in found}
    manifest_path.write_text(json.dumps(entries, indent=2) + '\n')


def cpp_string(value):
    return json.dumps(value)


def lua_catalog(entries):
    active_ids = {e['id'] for e in entries if not e.get('retired')}
    color_ids = {color['id'] for group in BAG_GROUPS for color in group['colors']}
    assert sum(len(group['colors']) for group in BAG_GROUPS)==len(color_ids)
    assert color_ids <= active_ids
    lua = ['-- Generated by tools/build_bag_catalog.py; saved model IDs never change.',
           'local V=VanityStudio', 'V.bagCatalog={']
    for e in entries:
        if e.get('retired'):
            assert not e.get('replacement') or e['replacement'] in active_ids
            continue
        icon = 'Interface\\AddOns\\SaureksCloset\\Textures\\BagIcon%d.tga' % e['id']
        lua.append('    {id=%d,name=%s,icon=%s,model=%s,material=%s},' % (e['id'], json.dumps(e['name']), json.dumps(icon),
                   json.dumps(MODEL_PREFIX + e['stem'] + '.mdx'), json.dumps(e['material'])))
    lua += ['}', 'V.bagCatalogByID={}', 'for _,bag in ipairs(V.bagCatalog) do V.bagCatalogByID[bag.id]=bag end',
            '-- Related variants share a model choice while saved looks retain asset IDs.', 'V.bagModelChoices={']
    groups_by_id = {color['id']: group for group in BAG_GROUPS for color in group['colors']}
    emitted = set()
    for e in entries:
        if e.get('retired'):
            continue
        group = groups_by_id.get(e['id'])
        if not group:
            lua.append('    V.bagCatalogByID[%d],' % e['id'])
        elif group['id'] not in emitted:
            emitted.add(group['id'])
            lua.append('    {id=%d,name=%s,icon=V.bagCatalogByID[%d].icon,material=%s,colors={' %
                       (group['id'], json.dumps(group['name']), group['id'], json.dumps(group['material'])))
            for color in group['colors']:
                lua.append('        {id=%d,name=%s,r=%s,g=%s,b=%s},' %
                           (color['id'], json.dumps(color['name']), color['r'], color['g'], color['b']))
            lua.append('    }},')
    lua += ['}', 'V.bagModelChoicesByID={}', 'V.bagModelColorsByID={}',
            'for _,choice in ipairs(V.bagModelChoices) do',
            '    V.bagModelChoicesByID[choice.id]=choice',
            '    for _,color in ipairs(choice.colors or {}) do',
            '        V.bagModelChoicesByID[color.id]=choice;V.bagModelColorsByID[color.id]=color',
            '    end', 'end',
            '-- Retired selections are removed (0) or migrated to an active model.', 'V.retiredBagModels={']
    for e in entries:
        if e.get('retired'):
            lua.append('    [%d]=%d,' % (e['id'], e.get('replacement', 0)))
    lua += ['}', '']
    return '\n'.join(lua)


def build():
    entries = [LEGACY] + json.loads((SOURCE / 'catalog.json').read_text())
    assert [e['id'] for e in entries] == list(range(1, len(entries) + 1))
    assert len({e['stem'] for e in entries}) == len(entries)
    assert all(e['material'] in {'cloth', 'canvas', 'leather'} for e in entries)
    OUTPUT.mkdir(parents=True, exist_ok=True)
    reports = []
    for entry in entries:
        source = ROOT / 'assets/DarkSchoolbag.glb' if entry['id'] == 1 else SOURCE / entry['source']
        vertices, triangles, atlas = read_glb(source)
        height = max(p[2] for p, _, _ in vertices) - min(p[2] for p, _, _ in vertices)
        assert height > 0
        scale = 1.0 if entry['id'] == 1 else TARGET_HEIGHT / height
        if entry['id'] != 1:
            vertices = [(tuple(c * scale for c in p), n, uv) for p, n, uv in vertices]
        m2, blp = [OUTPUT / (entry['stem'] + extension) for extension in ('.m2', '.blp')]
        # Offline cloth clips are experimental reference data, never implicitly
        # enabled by an NPZ left on disk. Every selected bag shares this rig.
        from build_bag_deformation import write_deformable_m2
        report = write_deformable_m2(vertices, triangles, m2, entry['stem'])
        write_blp(atlas, blp, size=128 if entry['id'] == 1 else None)
        dimensions = Image.open(io.BytesIO(atlas)).size
        report.update(entry)
        report.update(source_sha256=digest(source), texture_sha256=hashlib.sha256(atlas).hexdigest(),
                      source_atlas_size=dimensions, normalization_scale=scale,
                      model=m2.name, model_sha256=digest(m2), texture=blp.name,
                      blp_sha256=digest(blp), blp_bytes=blp.stat().st_size)
        reports.append(report)
    (ROOT / 'native/BAG-ASSETS.json').write_text(json.dumps({'schema': 2, 'bags': reports}, indent=2) + '\n')

    header = ['#pragma once', '// Generated by tools/build_bag_catalog.py. IDs are stable across releases.',
              'struct BagAsset { unsigned id; const char* name; const char* model; const char* texture; const char* material; };',
              'static constexpr BagAsset bagCatalog[]={']
    for e in entries:
        header.append('    {%d,%s,%s,%s,%s},' % (e['id'], cpp_string(e['name']),
                      cpp_string(MODEL_PREFIX + e['stem'] + '.mdx'), cpp_string(MODEL_PREFIX + e['stem'] + '.blp'),
                      cpp_string(e['material'])))
    header += ['};', 'static constexpr unsigned bagCatalogCount=sizeof(bagCatalog)/sizeof(bagCatalog[0]);',
               'static inline const BagAsset* bagAsset(unsigned id){',
               '    for(const auto& asset:bagCatalog)if(asset.id==id)return &asset;', '    return nullptr;', '}',
               'static inline const BagAsset* bagCatalogFind(unsigned id){return bagAsset(id);}',
               '// Exact on-disk names: the client changes model .mdx requests to .m2.',
               'static constexpr const char* bagAssetFiles[]={']
    for e in entries:
        for extension in ('.m2', '.blp'):
            header.append('    ' + cpp_string(MODEL_PREFIX + e['stem'] + extension) + ',')
    header += ['};', '']
    (ROOT / 'native/BagCatalog.h').write_text('\n'.join(header))

    (ROOT / 'addon/SaureksCloset/BagCatalog.lua').write_text(lua_catalog(entries))
    print('Built %d bag models, %d matching textures and stable Lua/native catalogs.' % (len(entries), len(entries)))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--import-directory', type=Path)
    args = parser.parse_args()
    if args.import_directory:
        import_directory(args.import_directory)
    build()
