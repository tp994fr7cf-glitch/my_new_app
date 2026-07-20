#!/usr/bin/env bash
# Runs on every Cloud Agent startup (environment.json "install" field).
# Must be idempotent: safe to re-run after git pull.
set -euo pipefail

if [[ -x "${FLUTTER_ROOT:-/opt/flutter}/bin/flutter" ]]; then
  export PATH="${FLUTTER_ROOT}/bin:${FLUTTER_ROOT}/bin/cache/dart-sdk/bin:${PATH}"
elif [[ -x "${HOME}/flutter/bin/flutter" ]]; then
  export PATH="${HOME}/flutter/bin:${HOME}/flutter/bin/cache/dart-sdk/bin:${PATH}"
fi

if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter SDK not found. Rebuild the Cloud Agent environment from .cursor/Dockerfile." >&2
  exit 1
fi

flutter --version
flutter pub get
