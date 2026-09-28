"""Mandatory focused checks before building an installable release."""
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
lua_tests = [
    'body_renderer_version', 'body_arrow_loading', 'body_preview_equipment',
    'bags_list_ui', 'bag_instances', 'bag_tuner', 'wardrobe_save', 'preview_drag',
    'weapon_full_page', 'updates', 'armor_recovery', 'bag_placement_editor',
]
for name in lua_tests:
    subprocess.run(['lua5.1', f'tests/{name}.lua'], cwd=root, check=True)
# Offline Blender experiments retain their individual tests, but are no longer
# installed assets or release prerequisites. Check the actual shipped rig.
for name in ['release_version', 'body_arrow_pixels', 'test_ui_assets', 'test_cloth_bag_shape', 'test_bag_deformation', 'test_bag_catalog']:
    subprocess.run([sys.executable, f'tests/{name}.py'], cwd=root, check=True)
with tempfile.TemporaryDirectory(prefix='closet-native-check-') as temporary:
    for name in ['weapon_renderer', 'bag_response']:
        executable = str(Path(temporary)/name)
        subprocess.run(['c++', '-std=c++17', '-O0', f'tests/{name}.cpp', '-o', executable], cwd=root, check=True)
        subprocess.run([executable], cwd=root, check=True)
print('PASS: all mandatory release checks')
