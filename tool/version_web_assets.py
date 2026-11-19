#!/usr/bin/env python3
"""Give the Dart entry point and local CanvasKit independent cache URLs."""
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

    main = root / 'main.dart.js'
    dart_url = move_bundle(root, 'dart', [main, *root.glob('main.dart.js_*.part.js')], root)
    canvas = root / 'canvaskit'
    canvas_url = move_bundle(root, 'canvaskit', [p for p in canvas.rglob('*') if p.is_file()], canvas)

    for build in config['builds']:
        build['mainJsPath'] = f'{dart_url}/{main.name}'
    source = source[:match.start(1)] + json.dumps(config) + source[match.end(1):]
    bootstrap.write_text(source.replace('canvasKitBaseUrl: "canvaskit/"',
                                        f'canvasKitBaseUrl: "{canvas_url}/"'))


if __name__ == '__main__':
    version_assets(Path(sys.argv[1]))
