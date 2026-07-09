#!/usr/bin/env bash
# Downloads the whisper model into assets before CI build.
# Quantized base (q5_1) saved under the plain "base" name — whisper.cpp
# identifies the format from the file header, not the filename.
set -euo pipefail
cd "$(dirname "$0")"
MODEL=assets/models/ggml-base.bin
if [ ! -f "$MODEL" ]; then
  echo "Downloading whisper base-q5_1 model..."
  curl -sL -o "$MODEL" \
    "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base-q5_1.bin"
fi
ls -lh "$MODEL"
