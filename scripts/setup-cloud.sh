#!/usr/bin/env bash
set -euo pipefail
flutter_root=/workspace/toolchains/flutter
flutter_revision=c197ca5199e9ee5661e865596c9c07294dfab51c
if [ ! -d "$flutter_root/.git" ]; then
  mkdir -p /workspace/toolchains
  git clone --depth 1 --branch 3.47.9 https://github.com/flutter/flutter.git "$flutter_root"
fi
if [ "$(git -C "$flutter_root" rev-parse HEAD)" != "$flutter_revision" ]; then
  echo 'Flutter SDK revision differs from the project pin; preserve it and select the pinned SDK.' >&2
  exit 1
fi
export PATH="$flutter_root/bin:$PATH"
flutter config --no-analytics
flutter --version
cd /workspace/WEAVER_APP_FLUTTER
flutter pub get --enforce-lockfile
