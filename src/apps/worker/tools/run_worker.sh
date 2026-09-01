#!/usr/bin/env bash

set -euo pipefail

PACKAGE="io.edgemint.edgemint_worker"
DEVICE="emulator-5556"
MODEL_FILE="$HOME/edgemint-models/Qwen2.5-0.5B-Instruct_multi-prefill-seq_q8_ekv1280.task"

if [ ! -f "$MODEL_FILE" ]; then
  echo "ERROR: Model not found:"
  echo "$MODEL_FILE"
  exit 1
fi

echo "==> Stop app"
adb shell am force-stop "$PACKAGE"

echo "==> Clear logs"
adb logcat -c

REMOTE_MODEL="/sdcard/Download/$(basename "$MODEL_FILE")"

LOCAL_SIZE=$(stat -c%s "$MODEL_FILE")

echo "==> Checking model"

REMOTE_SIZE=$(adb shell "stat -c%s '$REMOTE_MODEL' 2>/dev/null" | tr -d '\r')

if [ "$REMOTE_SIZE" = "$LOCAL_SIZE" ]; then
  echo "==> Model already exists and size matches"
else
  echo "==> Uploading model"
  adb push "$MODEL_FILE" "$REMOTE_MODEL"
fi

echo "==> Clear app cache only (not data)"
adb shell pm trim-caches 512M

echo "==> Run Worker"
flutter run \
  -d "$DEVICE" \
  --dart-define=WORKER_USE_BACKEND_ARTIFACT=false \
  --dart-define=WORKER_VERBOSE_TASK_LOGS=true