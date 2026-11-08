"""Generate launcher assets from the original logo using ImageMagick 7.
Run from any directory: python tool/generate_icons.py
"""
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'assets/branding/logo.png'

def icon(path, size, maskable=False):
    target = ROOT / path
    target.parent.mkdir(parents=True, exist_ok=True)
    artwork = round(size * .64) if maskable else size
    subprocess.run([
        'magick', str(SOURCE), '-background', 'white', '-alpha', 'remove',
        '-alpha', 'off', '-filter', 'Lanczos', '-resize', f'{artwork}x{artwork}',
        '-gravity', 'center', '-extent', f'{size}x{size}',
        '-strip', f'PNG24:{target}',
    ], check=True)

icon('web/favicon.png', 32)
icon('web/icons/apple-touch-icon.png', 180)
for size in (192, 512):
    icon(f'web/icons/Icon-{size}.png', size)
    icon(f'web/icons/Icon-maskable-{size}.png', size, maskable=True)
for density, size in {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}.items():
    icon(f'android/app/src/main/res/mipmap-{density}/ic_launcher.png', size)
catalog = Path('ios/Runner/Assets.xcassets/AppIcon.appiconset')
for entry in json.loads((ROOT / catalog / 'Contents.json').read_text())['images']:
    size = round(float(entry['size'].split('x')[0]) * float(entry['scale'].rstrip('x')))
    icon(catalog / entry['filename'], size)
