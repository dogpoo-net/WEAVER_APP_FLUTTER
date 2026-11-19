#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
flutter build web --release --no-pub --no-wasm-dry-run "$@"
python3 tool/optimize_web.py build/web
python3 tool/version_web_assets.py build/web
