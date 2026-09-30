"""Export the supplied transparent signature as a WoW 1.12 texture."""
from pathlib import Path
import hashlib
import json

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'assets/donations/saurek-signature.png'
ADDON = ROOT / 'addon/SaureksCloset'
TEXTURE = ADDON / 'Textures/DonationSignature.tga'

# Preserve the complete artwork and its 3:1 aspect ratio. The power-of-two
# canvas is required by the client; Lua samples only the inset content region.
with Image.open(SOURCE) as source:
    assert source.size[0] == source.size[1] * 3
    content = source.convert('RGBA').resize((480, 160), Image.Resampling.LANCZOS)
canvas = Image.new('RGBA', (512, 256))
canvas.paste(content, (16, 48))
canvas.save(TEXTURE, compression=None)

digest = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
manifest_path = ADDON / 'ARTWORK.json'
manifest = [entry for entry in json.loads(manifest_path.read_text())
            if entry['texture'] != TEXTURE.name]
manifest.append({
    'source': SOURCE.relative_to(ROOT).as_posix(),
    'source_sha256': digest(SOURCE),
    'provenance': 'User-supplied transparent gold signature, resized proportionally with original colors and alpha; no artwork changes.',
    'generated': True,
    'texture': TEXTURE.name,
    'size': [512, 256],
    'bytes': TEXTURE.stat().st_size,
    'encoding': 'RGBA8 lossless, uncompressed TGA',
    'gpu_base_bytes': 512 * 256 * 4,
    'sha256': digest(TEXTURE),
    'content_rect': [16, 48, 496, 208],
})
manifest_path.write_text(json.dumps(manifest, indent=2) + '\n')
print('Exported DonationSignature.tga: supplied artwork, transparent 3:1 signature.')
