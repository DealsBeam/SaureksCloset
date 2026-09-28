"""Compare shipped gold-arrow pixels using geometry emitted by the real Lua UI."""
from pathlib import Path
import csv
import os
import subprocess
import tempfile
from PIL import Image, ImageChops

root = Path(__file__).resolve().parents[1]
source = Image.open(root / 'addon/SaureksCloset/Textures/BodyArrow.tga').convert('RGBA')
with tempfile.TemporaryDirectory() as directory:
    records = Path(directory) / 'geometry.tsv'
    env = dict(os.environ, CLOSET_BODY_GEOMETRY=str(records))
    subprocess.run(['lua5.1', 'tests/body_arrow_loading.lua'], cwd=root, env=env, check=True)
    with records.open() as stream:
        rows = list(csv.reader(stream, delimiter='\t'))

checks = 0
for scale in (.64, .8, 1, 1.25, 1.5, 2):
    bounds = {}
    images = {}
    for key, side, state, *numbers in rows:
        x, y, width, height, *uv = map(float, numbers)
        expected_uv = [1,1,0,1,1,0,0,0] if side == 'previous' else [1,0,0,0,1,1,0,1]
        assert uv == expected_uv, 'Use the generated down arrow rotated right, with horizontal mirroring only'
        glyph = source.transpose(Image.Transpose.ROTATE_90)
        if side == 'previous':
            glyph = glyph.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
        size = (round(width * scale), round(height * scale))
        glyph = glyph.resize(size, Image.Resampling.BILINEAR)
        canvas = Image.new('RGBA', (400, 100))
        top = round(50 - y * scale - size[1] / 2)
        canvas.alpha_composite(glyph, (round(200 + x * scale - size[0] / 2), top))
        box = canvas.getchannel('A').point(lambda value: 255 if value > 32 else 0).getbbox()
        assert box, 'The shipped glyph must have visible pixels'
        vertical = (box[1], box[3])
        assert bounds.setdefault(key, vertical) == vertical, f'{key}/{side}/{state}: visible edges drift at UI scale {scale}'
        normalized = glyph.transpose(Image.Transpose.FLIP_LEFT_RIGHT) if side == 'previous' else glyph
        reference = images.setdefault(key, normalized)
        assert ImageChops.difference(reference, normalized).getbbox() is None, 'Mirroring must preserve the complete glyph silhouette'
        checks += 1
assert len(bounds) == 7
print(f'PASS: {checks} visible pixel bounds and mirror checks across seven Body rows, interaction states and six UI scales')
