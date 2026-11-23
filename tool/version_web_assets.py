#!/usr/bin/env python3
"""Give Dart, CanvasKit and Flutter assets independent cache URLs."""
import hashlib
import json
import re
import sys
from pathlib import Path


def move_bundle(root: Path, name: str, files: list[Path], base: Path) -> str:
    # Hash paths as well as contents, since the loader relies on relative paths.
    manifest = [
        [path.relative_to(base).as_posix(), hashlib.sha256(path.read_bytes()).hexdigest()]
        for path in sorted(files)
    ]
    digest = hashlib.sha256(json.dumps(manifest).encode()).hexdigest()
    relative = Path('_immutable') / name / digest
    for path in files:
        target = root / relative / path.relative_to(base)
        target.parent.mkdir(parents=True, exist_ok=True)
        path.replace(target)
    return relative.as_posix()


def version_assets(root: Path) -> None:
    bootstrap = root / 'flutter_bootstrap.js'
    source = bootstrap.read_text()
    match = re.search(r'_flutter\.buildConfig\s*=\s*(\{.*?\});', source, re.S)
    if match is None or source.count('canvasKitBaseUrl: "canvaskit/"') != 1:
        raise ValueError('Unexpected Flutter bootstrap configuration')
    config = json.loads(match.group(1))
    if any(build.get('mainJsPath', 'main.dart.js') != 'main.dart.js'
           for build in config['builds']):
        raise ValueError('Unexpected Dart entry point')

    index = root / 'index.html'
    html = index.read_text()
    font = 'assets/assets/fonts/PretendardVariable.ttf'
    preload_marker = '<!-- WEAVER_DART_PRELOAD -->'
    if html.count(preload_marker) != 1 or not (root / font).is_file():
        raise ValueError('Missing Dart preload marker or bundled Pretendard font')

    # main.dart explicitly registers this font on web for Korean text input.
    # Leaving it in the engine manifest would load and register it a second time.
    font_manifest = root / 'assets' / 'FontManifest.json'
    fonts = json.loads(font_manifest.read_text())
    remaining_fonts = [family for family in fonts if family['family'] != 'Pretendard']
    if len(fonts) - len(remaining_fonts) != 1:
        raise ValueError('Unexpected startup font family in Flutter manifest')
    font_manifest.write_text(json.dumps(remaining_fonts))

    main = root / 'main.dart.js'
    dart_url = move_bundle(root, 'dart', [main, *root.glob('main.dart.js_*.part.js')], root)
    canvas = root / 'canvaskit'
    canvas_url = move_bundle(root, 'canvaskit', [p for p in canvas.rglob('*') if p.is_file()], canvas)

    assets = root / 'assets'
    assets_url = move_bundle(root, 'assets', [p for p in assets.rglob('*') if p.is_file()], root)

    for build in config['builds']:
        build['mainJsPath'] = f'{dart_url}/{main.name}'
    source = source[:match.start(1)] + json.dumps(config) + source[match.end(1):]
    bootstrap.write_text(source.replace('canvasKitBaseUrl: "canvaskit/"',
                                        f'canvasKitBaseUrl: "{canvas_url}/",\n'
                                        f'    assetBase: "{assets_url}/"'))
    index.write_text(html.replace(
        preload_marker, f'<link rel="preload" href="{dart_url}/{main.name}" as="script">'))


if __name__ == '__main__':
    version_assets(Path(sys.argv[1]))
