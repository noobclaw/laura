#!/usr/bin/env bash
# Fetches the bundled Whisper model before `flutter build`.
#
# The model (ggml-base-q5_1.bin, ~57 MB) is a build input, not source: it is
# NOT committed to git. build-app.yml already runs this script when present;
# build-ios.yml needs the same "Prepare assets" step (see PLAN.md「Whisper
# 引擎」). The download is pinned by SHA-256 so every build ships byte-identical
# weights, and a wrong file fails the build instead of shipping a broken engine.
#
# Run it locally once too: `flutter test` needs the asset to exist.
set -euo pipefail

cd "$(dirname "$0")"

MODEL_DIR="assets/models"
MODEL_NAME="ggml-base-q5_1.bin"
MODEL_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/${MODEL_NAME}"
MODEL_SHA256="422f1ae452ade6f30a004d7e5c6a43195e4433bc370bf23fac9cc591f01a8898"
MODEL_SIZE=59707625

mkdir -p "$MODEL_DIR"
target="$MODEL_DIR/$MODEL_NAME"

checksum() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

if [ -f "$target" ] && [ "$(checksum "$target")" = "$MODEL_SHA256" ]; then
  echo "prepare_assets: $target already present and verified."
  exit 0
fi

echo "prepare_assets: downloading $MODEL_NAME (${MODEL_SIZE} bytes)…"
curl -fL --retry 3 --retry-delay 5 -o "$target.part" "$MODEL_URL"
actual="$(checksum "$target.part")"
if [ "$actual" != "$MODEL_SHA256" ]; then
  echo "prepare_assets: SHA-256 mismatch for $MODEL_NAME" >&2
  echo "  expected $MODEL_SHA256" >&2
  echo "  actual   $actual" >&2
  rm -f "$target.part"
  exit 1
fi
mv "$target.part" "$target"
echo "prepare_assets: $target ready."
