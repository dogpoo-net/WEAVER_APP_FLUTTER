"""Generate launcher assets from the original logo using ImageMagick 7.
Run from any directory: python tool/generate_icons.py
"""
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'assets/branding/app-icon.png'
FAVICON = ROOT / 'assets/branding/favicon.png'

def icon(path, size, maskable=False, source=SOURCE):
    target = ROOT / path
    target.parent.mkdir(parents=True, exist_ok=True)
    artwork = round(size * .64) if maskable else size
    subprocess.run([
        'magick', str(source), '-background', 'white', '-alpha', 'remove',
        '-alpha', 'off', '-filter', 'Lanczos', '-resize', f'{artwork}x{artwork}',
        '-gravity', 'center', '-extent', f'{size}x{size}',
        '-strip', f'PNG24:{target}',
    ], check=True)

icon('web/favicon.png', 32, source=FAVICON)
icon('web/icons/splash.png', 576)
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

# Native launch screens: 192 logical pixels, plus Android 12 safe-area artwork.
for density, scale in {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}.items():
    icon(f'android/app/src/main/res/drawable-{density}/launch_image.png', round(192 * scale))
    icon(f'android/app/src/main/res/drawable-{density}/launch_icon.png', round(288 * scale), maskable=True)
for scale, suffix in [(1, ''), (2, '@2x'), (3, '@3x')]:
    icon(f'ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage{suffix}.png', 192 * scale)
