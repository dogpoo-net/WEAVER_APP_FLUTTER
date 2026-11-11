#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
flutter_version=3.47.9
flutter_revision=c197ca5199e9ee5661e865596c9c07294dfab51c
flutter_root="${WEAVER_FLUTTER_ROOT:-${XDG_CACHE_HOME:-$HOME/.cache}/weaver/flutter-$flutter_version}"

if [[ ! -d "$flutter_root/.git" ]]; then
  if [[ -e "$flutter_root" ]]; then
    echo "SDK directory already exists without Git metadata: $flutter_root" >&2
    exit 1
  fi
  mkdir -p "$(dirname -- "$flutter_root")"
  git clone --depth 1 --branch "$flutter_version" https://github.com/flutter/flutter.git "$flutter_root"
fi
if [[ "$(git -C "$flutter_root" rev-parse HEAD)" != "$flutter_revision" ]]; then
  echo 'Flutter SDK revision differs from the project pin.' >&2
  exit 1
fi
export PATH="$flutter_root/bin:$PATH"
export CI=true
flutter config --no-analytics
flutter --version
cd "$project_root"
flutter pub get --enforce-lockfile
build_args=(build web --release --no-pub --base-href /)
if [[ -n "${GOOGLE_WEB_CLIENT_ID:-}" ]]; then
  build_args+=("--dart-define=GOOGLE_WEB_CLIENT_ID=$GOOGLE_WEB_CLIENT_ID")
fi
flutter "${build_args[@]}"
test -s build/web/index.html
test -s build/web/main.dart.js
