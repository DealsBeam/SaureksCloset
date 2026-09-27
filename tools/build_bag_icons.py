"""Export the approved reference-based bag artwork as 64px client TGA icons.

Generation is deliberately separate: assets/bag-icons/generation.json records
the built-in image tool prompts and source references. This step only resizes
and converts those approved PNGs, retaining their original alpha channels.
"""
import argparse
import hashlib
import json
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'assets/bag-icons'
ADDON = ROOT / 'addon/SaureksCloset'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def build(preview=None):
    manifest = json.loads((SOURCE / 'generation.json').read_text())
    icons = manifest['icons']
    active = {1} | {e['id'] for e in json.loads((ROOT / 'assets/bags/catalog.json').read_text()) if not e.get('retired')}
    assert {e['id'] for e in icons} == active
    textures = {'BagIcon%d.tga' % entry['id'] for entry in icons}
    artwork_path = ADDON / 'ARTWORK.json'
    artwork = [e for e in json.loads(artwork_path.read_text()) if e['texture'] not in textures]
    previews = []
    for entry in icons:
        source, reference = SOURCE / entry['source'], SOURCE / entry['reference']
        assert digest(source) == entry['source_sha256'] and digest(reference) == entry['reference_sha256']
        original = Image.open(source).convert('RGBA')
        assert original.width == original.height
        icon = original.resize((64, 64), Image.Resampling.LANCZOS)
        texture = ADDON / 'Textures' / ('BagIcon%d.tga' % entry['id'])
        icon.save(texture, compression=None)
        raw = texture.read_bytes()
        assert raw[2] == 2 and raw[16] == 32, 'Client icons must be uncompressed RGBA TGA'
        assert Image.open(texture).convert('RGBA').tobytes() == icon.tobytes()
        artwork.append({'source': source.relative_to(ROOT).as_posix(), 'source_sha256': digest(source),
                        'reference': reference.relative_to(ROOT).as_posix(), 'reference_sha256': digest(reference),
                        'provenance': 'assets/bag-icons/generation.json', 'generated': True,
                        'texture': texture.name, 'size': [64, 64], 'bytes': texture.stat().st_size,
                        'encoding': 'RGBA8 lossless, uncompressed TGA', 'gpu_base_bytes': 16384,
                        'sha256': digest(texture)})
        previews.append((entry, icon))
    artwork_path.write_text(json.dumps(artwork, indent=2) + '\n')
    if preview:
        sheet = Image.new('RGB', (960, 410), '#181512')
        draw = ImageDraw.Draw(sheet)
        for i, (entry, icon) in enumerate(previews):
            x, y = (i % 6) * 160, (i // 6) * 195
            draw.text((x + 8, y + 8), '%d. %s' % (entry['id'], entry['name'][:20]), fill='#ecdcc2')
            draw.text((x + 8, y + 24), entry['name'][20:], fill='#ecdcc2')
            sheet.paste(icon, (x + 8, y + 48), icon)
            small = icon.resize((32, 32), Image.Resampling.LANCZOS)
            sheet.paste(small, (x + 91, y + 64), small)
            draw.text((x + 8, y + 119), '64px', fill='#b5a590')
            draw.text((x + 91, y + 103), '32px', fill='#b5a590')
        preview.parent.mkdir(parents=True, exist_ok=True)
        sheet.save(preview)
    print('Exported %d reference-based bag icons; source hashes and lossless RGBA TGA round trips verified.' % len(icons))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--preview', type=Path)
    args = parser.parse_args()
    build(args.preview)
