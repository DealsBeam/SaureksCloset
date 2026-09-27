"""Export the small vector chevron for native Body-page Button textures."""
from pathlib import Path
import hashlib
import json
import io
import subprocess

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
ADDON = ROOT / 'addon/SaureksCloset'
source = ROOT / 'assets/body-arrow/chevron.svg'
texture = ADDON / 'Textures/BodyChevron.tga'
digest = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()

rendered = subprocess.run(['rsvg-convert', '--width', '64', '--height', '64', str(source)], check=True, capture_output=True).stdout
image = Image.open(io.BytesIO(rendered)).convert('RGBA')
assert image.getchannel('A').getextrema() == (0, 255)
assert all(image.getpixel(point)[3] == 0 for point in [(0, 0), (63, 0), (0, 63), (63, 63)])
image.save(texture, compression=None)
assert texture.read_bytes()[2] == 2 and texture.read_bytes()[16] == 32
assert Image.open(texture).convert('RGBA').tobytes() == image.tobytes()

manifest_path = ADDON / 'ARTWORK.json'
manifest = [entry for entry in json.loads(manifest_path.read_text()) if entry['texture'] != texture.name]
manifest.append({'source': source.relative_to(ROOT).as_posix(), 'source_sha256': digest(source),
                 'provenance': 'Original vector chevron: rounded two-pixel gold stroke with a dark edge, rendered by librsvg. The UI mirrors the same glyph for exact left/right alignment.',
                 'generated': True, 'texture': texture.name, 'size': [64, 64],
                 'bytes': texture.stat().st_size, 'encoding': 'RGBA8 lossless, uncompressed TGA',
                 'gpu_base_bytes': 16384, 'sha256': digest(texture)})
manifest_path.write_text(json.dumps(manifest, indent=2) + '\n')
print('Exported BodyChevron.tga: transparent 64px RGBA texture, verified lossless round trip.')
