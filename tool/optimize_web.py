#!/usr/bin/env python3
"""Remove renderer artifacts unused by WEAVER's dart2js CanvasKit build."""
import json
import re
import shutil
import sys
from pathlib import Path


def optimize(root: Path):
    bootstrap = (root / 'flutter_bootstrap.js').read_text()
    match = re.search(r'_flutter\.buildConfig\s*=\s*(\{.*?\});', bootstrap, re.S)
    if not match:
        raise ValueError('Flutter build configuration not found')
    builds = json.loads(match.group(1)).get('builds', [])
    if not builds or any(b.get('compileTarget') != 'dart2js' or b.get('renderer') != 'canvaskit' for b in builds):
        raise ValueError('Only dart2js CanvasKit builds can be trimmed')
    if not re.search(r'preferWebParagraph\s*:\s*false', bootstrap):
        raise ValueError('WebParagraph must be explicitly disabled')
    worker = root / 'flutter_service_worker.js'
    if worker.exists() and 'const RESOURCES' in worker.read_text():
        raise ValueError('Legacy caching service worker requires a matching resource manifest')
    renderer = root / 'canvaskit'
    required = ['canvaskit.js', 'canvaskit.wasm', 'chromium/canvaskit.js', 'chromium/canvaskit.wasm']
    if not all((renderer / f).is_file() for f in required):
        raise ValueError('Missing CanvasKit browser fallback')
    size = lambda: sum(p.stat().st_size for p in root.rglob('*') if p.is_file())
    before = size()
    for file in list(renderer.rglob('*.symbols')):
        file.unlink()
    for pattern in ['skwasm*', 'wimp*']:
        for file in renderer.glob(pattern):
            if file.is_file():
                file.unlink()
    if (renderer / 'webparagraph').exists():
        shutil.rmtree(renderer / 'webparagraph')
    after = size()
    print(json.dumps({'before_bytes': before, 'after_bytes': after, 'saved_bytes': before - after}))


if __name__ == '__main__':
    optimize(Path(sys.argv[1] if len(sys.argv) > 1 else 'build/web'))
