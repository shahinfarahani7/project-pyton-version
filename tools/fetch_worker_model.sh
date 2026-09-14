#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT/src/apps/worker/assets/models}"
FILE_NAME="${FILE_NAME:-Qwen2.5-0.5B-Instruct_multi-prefill-seq_q8_ekv1280.task}"
URL="${URL:-https://huggingface.co/litert-community/Qwen2.5-0.5B-Instruct/resolve/main/$FILE_NAME}"
mkdir -p "$OUTPUT_DIR"
DEST="$OUTPUT_DIR/$FILE_NAME"
if [[ -f "$DEST" ]]; then
  echo "Model already present: $DEST"
  exit 0
fi
echo "Downloading Qwen dev model to $DEST ..."
curl -fsSL "$URL" -o "$DEST"
echo "Done. Size bytes: $(wc -c < "$DEST")"
