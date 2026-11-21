#!/bin/sh
set -eu
. /opt/edgemint/apply-host-proxy.sh
apply_host_proxy
cleanup() {
  rm -f "${HOME}/.gradle/gradle.properties"
}
trap cleanup EXIT

if [ -f /run/secrets/android_debug_keystore ]; then
  mkdir -p "${HOME}/.android"
  cp /run/secrets/android_debug_keystore "${HOME}/.android/debug.keystore"
  chmod 600 "${HOME}/.android/debug.keystore"
fi

cd /src
flutter config --no-analytics >/dev/null
flutter pub get
set -- --dart-define="EDGEMINT_WORKER_BASE_URL=${EDGEMINT_WORKER_BASE_URL}"
if [ -n "${EDGEMINT_API_BASE_URL:-}" ]; then
  set -- "$@" --dart-define="EDGEMINT_API_BASE_URL=${EDGEMINT_API_BASE_URL}"
fi
if [ -n "${WORKER_MODEL_DOWNLOAD_SOURCE:-}" ]; then
  set -- "$@" --dart-define="WORKER_MODEL_DOWNLOAD_SOURCE=${WORKER_MODEL_DOWNLOAD_SOURCE}"
fi
if [ -n "${WORKER_BUILD_NAME:-}" ]; then
  set -- "$@" --build-name="${WORKER_BUILD_NAME}"
fi
if [ -n "${WORKER_BUILD_NUMBER:-}" ]; then
  set -- "$@" --build-number="${WORKER_BUILD_NUMBER}"
fi
flutter build apk --release "$@"
mkdir -p /out
cp build/app/outputs/flutter-apk/app-release.apk /out/app-release.apk
