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
flutter build apk --release \
  --dart-define="EDGEMINT_WORKER_BASE_URL=${EDGEMINT_WORKER_BASE_URL}"
mkdir -p /out
cp build/app/outputs/flutter-apk/app-release.apk /out/app-release.apk
