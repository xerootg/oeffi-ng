#!/bin/bash
#
# Build an unsigned-for-release / debug-signed Öffi NG APK without needing
# santawho's secret release keystore. Assumes the SessionStart hook
# (.claude/hooks/session-start.sh) has provisioned the SDK, the submodule and a
# throwaway debug keystore. Safe to run from any branch.
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ANDROID_HOME="${ANDROID_HOME:-/opt/android-sdk}"
DEBUG_KEYSTORE="${OEFFI_NG_DEBUG_KEYSTORE:-${ANDROID_HOME}/oeffi-ng-debug.jks}"

export ANDROID_HOME
export ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-$ANDROID_HOME}"
export OEFFI_NG_DEBUG_KEYSTORE="$DEBUG_KEYSTORE"
# Password of the throwaway debug keystore; skips the passwords.properties read.
export OEFFI_NG_JKS_PASSWORD="${OEFFI_NG_JKS_PASSWORD:-oeffi-ng-debug}"

if [ ! -f "$DEBUG_KEYSTORE" ]; then
  echo "Debug keystore not found at $DEBUG_KEYSTORE." >&2
  echo "Run the SessionStart hook first: .claude/hooks/session-start.sh" >&2
  exit 1
fi

cd "${REPO_ROOT}/androidstudio"
# --max-workers=1 keeps Maven Central from rate-limiting (429) the first time.
sh ./gradlew --no-daemon --max-workers=1 \
  "${1:-:oeffi-studio:assembleNgDebug}" \
  --init-script "${REPO_ROOT}/.claude/oeffi-debug-signing.init.gradle" "${@:2}"

echo
echo "APK(s):"
find "${REPO_ROOT}/androidstudio/oeffi-studio/build/outputs/apk" -name '*.apk' 2>/dev/null || true
