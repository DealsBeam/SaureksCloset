"""Mandatory focused checks before building an installable release."""
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
lua_tests = [
    'body_renderer_version', 'body_arrow_loading', 'body_preview_equipment',
    'bags_list_ui', 'bag_instances', 'bag_tuner', 'wardrobe_save', 'preview_drag',
    'weapon_full_page', 'updates', 'armor_recovery',
]
for name in lua_tests:
    subprocess.run(['lua5.1', f'tests/{name}.lua'], cwd=root, check=True)
for name in ['release_version', 'body_arrow_pixels', 'test_ui_assets']:
    subprocess.run([sys.executable, f'tests/{name}.py'], cwd=root, check=True)
print('PASS: all mandatory release checks')
