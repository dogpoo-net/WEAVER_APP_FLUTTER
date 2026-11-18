"""Generate launcher assets from the original logo using ImageMagick 7.
Run from any directory: python tool/generate_icons.py
"""
import argparse
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'assets/branding/app-icon.png'
FAVICON = ROOT / 'assets/branding/favicon.png'
ANDROID_SOURCE = ROOT / 'tool/branding/android-launcher.jpg'

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

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--android-splash-only', action='store_true', help='Generate Android splash assets from the web loading logo')
parser.add_argument('--android-only', action='store_true', help='Generate only Android launcher icons')
args = parser.parse_args()
def android_splash():
    for density, scale in {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}.items():
        for name, canvas in [('launch_image', 192), ('launch_icon', 288)]:
            # Android 12 clips the icon to a circle: keep artwork within 192dp.
            subprocess.run(['magick', str(ROOT / 'web/icons/loading-logo.png'),
                '-filter', 'Lanczos', '-resize', f'{round(192*scale)}x{round(192*scale)}',
                '-background', 'none', '-gravity', 'center', '-extent', f'{round(canvas*scale)}x{round(canvas*scale)}',
                '-strip', str(ROOT / f'android/app/src/main/res/drawable-{density}/{name}.png')], check=True)

if args.android_splash_only:
    android_splash()
    raise SystemExit(0)

for density, size in {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}.items():
    icon(f'android/app/src/main/res/mipmap-{density}/ic_launcher.png', size, source=ANDROID_SOURCE)
if args.android_only:
    raise SystemExit(0)

icon('web/favicon.png', 32, source=FAVICON)
icon('web/icons/splash.png', 576)
icon('web/icons/apple-touch-icon.png', 180)
for size in (192, 512):
    icon(f'web/icons/Icon-{size}.png', size)
    icon(f'web/icons/Icon-maskable-{size}.png', size, maskable=True)
catalog = Path('ios/Runner/Assets.xcassets/AppIcon.appiconset')
for entry in json.loads((ROOT / catalog / 'Contents.json').read_text())['images']:
    size = round(float(entry['size'].split('x')[0]) * float(entry['scale'].rstrip('x')))
    icon(catalog / entry['filename'], size)

# Native launch screens: 192 logical pixels, plus Android 12 safe-area artwork.
android_splash()
for scale, suffix in [(1, ''), (2, '@2x'), (3, '@3x')]:
    icon(f'ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage{suffix}.png', 192 * scale)
