#!/usr/bin/env bash
# Downloads the prebuilt ncnn iOS frameworks (Tencent/ncnn, BSD-3) into
# ios/Frameworks/ so the Runner target can link them. Idempotent: a matching
# version marker short-circuits the download.
#
# Invoked automatically by the "Fetch ncnn" run-script phase in
# ios/Runner.xcodeproj (first phase of the Runner target), so a plain
# `xcodebuild archive` from a clean checkout works without touching the shared
# build-ios.yml. It can also be called explicitly from CI before the archive
# step for clearer logs / caching (see PLAN.md).
#
# CPU-only build on purpose: the Vulkan flavour needs MoltenVK bundled and
# shipped with the app, which is a separate milestone (PLAN.md「iOS GPU」).
set -euo pipefail

NCNN_VERSION="20260526"
NCNN_NAME="ncnn-${NCNN_VERSION}-ios"
NCNN_URL="https://github.com/Tencent/ncnn/releases/download/${NCNN_VERSION}/${NCNN_NAME}.zip"

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${APP_DIR}/ios/Frameworks"
MARKER="${DEST}/.ncnn-version"

if [ -f "${DEST}/ncnn.framework/ncnn" ] && [ -f "${DEST}/openmp.framework/openmp" ] \
   && [ -f "${MARKER}" ] && [ "$(cat "${MARKER}")" = "${NCNN_NAME}" ]; then
  echo "ncnn iOS frameworks already present (${NCNN_NAME})"
  exit 0
fi

echo "Fetching ${NCNN_URL}"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT
curl -fsSL --retry 3 -o "${TMP}/${NCNN_NAME}.zip" "${NCNN_URL}"
(cd "${TMP}" && unzip -q "${NCNN_NAME}.zip")

for fw in ncnn openmp; do
  if [ ! -d "${TMP}/${fw}.framework" ]; then
    echo "error: ${fw}.framework missing from ${NCNN_NAME}.zip" >&2
    exit 1
  fi
done

mkdir -p "${DEST}"
rm -rf "${DEST}/ncnn.framework" "${DEST}/openmp.framework" "${DEST}/glslang.framework"
mv "${TMP}/ncnn.framework" "${TMP}/openmp.framework" "${DEST}/"
echo "${NCNN_NAME}" > "${MARKER}"
echo "ncnn iOS frameworks installed into ${DEST}"
ls "${DEST}/ncnn.framework/Headers" | head -5
