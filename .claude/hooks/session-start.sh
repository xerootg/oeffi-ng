#!/bin/bash
#
# SessionStart hook for Öffi NG — provisions the Android build toolchain so
# Claude Code on the web can build the app (the `androidstudio/` project).
#
# Runs synchronously (blocks session start until finished) so the build never
# races an unfinished install. Idempotent and non-interactive: safe to re-run.
#
set -euo pipefail

# Only provision in the remote (Claude Code on the web) environment.
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
ANDROID_HOME="${ANDROID_HOME:-/opt/android-sdk}"
CMDLINE_TOOLS_ZIP="commandlinetools-linux-15859902_latest.zip"
CMDLINE_TOOLS_SHA256="4e4c464f145a7512b57d088ac6c278c03c9eea610886b35a5e0804e74eedf583"
DEBUG_KEYSTORE="${PROJECT_DIR}/.claude/oeffi-ng-debug.jks"
DEBUG_KEYSTORE_PASSWORD="oeffi-ng-debug"

SUDO=""
[ "$(id -u)" -ne 0 ] && SUDO="sudo"

log() { echo "[oeffi-ng setup] $*"; }

# --- 1. Android SDK command-line tools ---------------------------------------
SDKMGR="${ANDROID_HOME}/cmdline-tools/latest/bin/sdkmanager"
if [ ! -x "$SDKMGR" ]; then
  log "installing Android command-line tools into ${ANDROID_HOME}"
  tmp="$(mktemp -d)"
  curl -fsSL -o "${tmp}/cmdline-tools.zip" \
    "https://dl.google.com/android/repository/${CMDLINE_TOOLS_ZIP}"
  echo "${CMDLINE_TOOLS_SHA256}  ${tmp}/cmdline-tools.zip" | sha256sum -c -
  ${SUDO} mkdir -p "${ANDROID_HOME}/cmdline-tools"
  (cd "$tmp" && unzip -q cmdline-tools.zip)         # -> ${tmp}/cmdline-tools
  ${SUDO} rm -rf "${ANDROID_HOME}/cmdline-tools/latest"
  ${SUDO} mv "${tmp}/cmdline-tools" "${ANDROID_HOME}/cmdline-tools/latest"
  rm -rf "$tmp"
else
  log "Android command-line tools already present"
fi

# --- 2. SDK packages (idempotent; sdkmanager skips what is installed) ---------
log "accepting licenses and installing SDK packages"
# `yes |` can win the pipe race and die with SIGPIPE; don't let that abort us.
set +o pipefail
yes | ${SUDO} "$SDKMGR" --sdk_root="${ANDROID_HOME}" --licenses >/dev/null 2>&1 || true
set -o pipefail
# Licenses are accepted above, so installs need no interactive input.
${SUDO} "$SDKMGR" --sdk_root="${ANDROID_HOME}" \
  "platform-tools" \
  "platforms;android-36" \
  "platforms;android-37.0" \
  "build-tools;36.1.0" \
  "build-tools;37.0.0" >/dev/null

# --- 3. public-transport-enabler submodule -----------------------------------
log "initializing public-transport-enabler submodule"
git -C "$PROJECT_DIR" submodule update --init --depth 1 public-transport-enabler

# --- 3b. Apply not-yet-upstreamed public-transport-enabler fixes -------------
# These ride as patches until they land upstream (santawho/public-transport-enabler).
# Idempotent: skip if already applied, warn (don't fail) if a patch no longer applies.
if [ -d "${PROJECT_DIR}/.claude/patches" ]; then
  for patch in "${PROJECT_DIR}"/.claude/patches/*.patch; do
    [ -e "$patch" ] || continue
    if git -C "${PROJECT_DIR}/public-transport-enabler" apply --reverse --check "$patch" >/dev/null 2>&1; then
      log "PTE patch already applied: $(basename "$patch")"
    elif git -C "${PROJECT_DIR}/public-transport-enabler" apply --check "$patch" >/dev/null 2>&1; then
      git -C "${PROJECT_DIR}/public-transport-enabler" apply "$patch"
      log "applied PTE patch: $(basename "$patch")"
    else
      log "WARNING: PTE patch no longer applies, skipping: $(basename "$patch")"
    fi
  done
fi

# --- 4. SDK location for the Gradle build ------------------------------------
printf 'sdk.dir=%s\n' "$ANDROID_HOME" > "${PROJECT_DIR}/androidstudio/local.properties"

# --- 5. Stable debug keystore ------------------------------------------------
# Debug builds are signed with the committed, stable throwaway key
# (.claude/oeffi-ng-debug.jks) so a new build installs over the previous one
# (no uninstall) and Obtainium can auto-update. Real releases still use the
# committed oeffi-ng.jks + OEFFI_NG_JKS_PASSWORD.
if [ ! -f "$DEBUG_KEYSTORE" ]; then
  # Fallback only; the keystore should already be committed in the repo.
  log "committed debug keystore missing; generating a temporary one"
  DEBUG_KEYSTORE="${ANDROID_HOME}/oeffi-ng-debug.jks"
  ${SUDO} keytool -genkeypair -keystore "$DEBUG_KEYSTORE" -storetype JKS -alias apk \
    -storepass "$DEBUG_KEYSTORE_PASSWORD" -keypass "$DEBUG_KEYSTORE_PASSWORD" \
    -keyalg RSA -keysize 2048 -validity 10000 \
    -dname "CN=Oeffi NG Debug, OU=CI, O=oeffi-ng, C=DE" -noprompt >/dev/null 2>&1
  ${SUDO} chmod a+r "$DEBUG_KEYSTORE" || true
fi

# --- 6. Persist environment for the session ----------------------------------
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  {
    grep -q "ANDROID_HOME=${ANDROID_HOME}" "$CLAUDE_ENV_FILE" 2>/dev/null || \
      echo "export ANDROID_HOME=${ANDROID_HOME}"
    grep -q "ANDROID_SDK_ROOT=${ANDROID_HOME}" "$CLAUDE_ENV_FILE" 2>/dev/null || \
      echo "export ANDROID_SDK_ROOT=${ANDROID_HOME}"
    grep -q "OEFFI_NG_DEBUG_KEYSTORE=" "$CLAUDE_ENV_FILE" 2>/dev/null || \
      echo "export OEFFI_NG_DEBUG_KEYSTORE=${DEBUG_KEYSTORE}"
    grep -q "OEFFI_NG_JKS_PASSWORD=" "$CLAUDE_ENV_FILE" 2>/dev/null || \
      echo "export OEFFI_NG_JKS_PASSWORD=${DEBUG_KEYSTORE_PASSWORD}"
  } >> "$CLAUDE_ENV_FILE"
fi

log "done. Build with:  ./.claude/build-debug.sh"
