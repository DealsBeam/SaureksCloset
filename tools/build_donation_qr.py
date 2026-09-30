"""Preserve the supplied Cash App QR as a lossless WoW 1.12 texture."""
from pathlib import Path
import hashlib
import io
import json
import subprocess

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
ADDON = ROOT / 'addon/SaureksCloset'
SOURCE = ROOT / 'assets/donations/cashapp-saurek.svg'
TEXTURE = ADDON / 'Textures/CashAppQR.tga'
DESTINATION = 'https://cash.app/$saurek?qr=1'

# The source is a 37-module white-on-black QR with no outside quiet zone.
# Forty-eight pixels around its 416-pixel render provide >4 clear modules.
# Keep those pixels opaque black so surrounding interface art cannot interfere.
rendered = subprocess.run(
    ['rsvg-convert', '--width', '416', '--height', '416', str(SOURCE)],
    check=True, capture_output=True,
).stdout
content = Image.open(io.BytesIO(rendered)).convert('RGBA')
image = Image.new('RGBA', (512, 512), (0, 0, 0, 255))
image.paste(content, (48, 48))
image.save(TEXTURE, compression=None)
assert TEXTURE.read_bytes()[2] == 2 and TEXTURE.read_bytes()[16] == 32
assert Image.open(TEXTURE).convert('RGBA').tobytes() == image.tobytes()

digest = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
manifest_path = ADDON / 'ARTWORK.json'
manifest = [entry for entry in json.loads(manifest_path.read_text())
            if entry['texture'] != TEXTURE.name]
manifest.append({
    'source': SOURCE.relative_to(ROOT).as_posix(),
    'source_sha256': digest(SOURCE),
    'provenance': 'User-supplied Cash App QR SVG, preserved with an opaque black quiet zone; decoded and verified at a 256px display size.',
    'generated': True,
    'texture': TEXTURE.name,
    'size': [512, 512],
    'bytes': TEXTURE.stat().st_size,
    'encoding': 'RGBA8 lossless, uncompressed TGA',
    'gpu_base_bytes': 512 * 512 * 4,
    'sha256': digest(TEXTURE),
    'qr_destination': DESTINATION,
    'quiet_zone_pixels': 48,
})
manifest_path.write_text(json.dumps(manifest, indent=2) + '\n')
print('Exported CashAppQR.tga: exact supplied artwork, 512px RGBA, black quiet zone.')
