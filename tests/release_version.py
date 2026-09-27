"""Check current release references without rewriting historical test fixtures."""
from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
addon = root / 'addon/SaureksCloset'
version = re.search(r'V.VERSION = "([^"]+)"', (addon / 'Core.lua').read_text()).group(1)
major, minor, patch = map(int, version.split('.'))
renderer = major * 10000 + minor * 100 + patch
assert f'## Version: {version}\n' in (addon / 'SaureksCloset.toc').read_text()
assert f'V.REQUIRED_RENDERER={renderer}\n' in (addon / 'Updates.lua').read_text()
assert f'version(void* L){{return result(L,{renderer});}}' in (root / 'native/SaureksCloset.cpp').read_text()
assert (root / 'update-version.txt').read_text() == f'schema=1\naddon={version}\ndll={renderer}\n'
for path in [root / 'README.md', addon / 'README.md', addon / 'BAGS-MENU.md',
             addon / 'Installation instructions/READ ME.txt', root / 'BUILDING.md']:
    assert version in path.read_text(), f'Missing current release in {path}'
assert (root / 'native/SaureksCloset.dll').read_bytes() == (addon / 'Installation instructions/SaureksCloset.dll').read_bytes()
print(f'PASS: addon, DLL source, required renderer, update manifest and release documentation agree on {version}')
