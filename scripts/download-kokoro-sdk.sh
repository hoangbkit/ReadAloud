#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
VENDOR_ROOT="${REPO_ROOT}/Vendor"
SDK_ROOT="${VENDOR_ROOT}/kokoro-coreml"

SDK_REPO="https://github.com/mattmireles/kokoro-coreml.git"
SDK_COMMIT="0594fcca424fa4228f4627ee399fbfd3e066eac6"

for command in git mktemp; do
  if ! command -v "${command}" >/dev/null 2>&1; then
    echo "error: required command not found: ${command}" >&2
    exit 1
  fi
done

if [[ -d "${SDK_ROOT}/.git" ]]; then
  ACTUAL_COMMIT="$(git -C "${SDK_ROOT}" rev-parse HEAD)"
  if [[ "${ACTUAL_COMMIT}" != "${SDK_COMMIT}" ]]; then
    echo "error: existing Kokoro SDK checkout is not pinned to the expected commit" >&2
    echo "expected: ${SDK_COMMIT}" >&2
    echo "actual:   ${ACTUAL_COMMIT}" >&2
    echo "remove Vendor/kokoro-coreml manually before replacing it" >&2
    exit 1
  fi

  echo "Kokoro SDK already present at pinned commit: ${SDK_COMMIT}"
  exit 0
fi

if [[ -e "${SDK_ROOT}" ]]; then
  echo "error: Vendor/kokoro-coreml exists but is not a Git checkout" >&2
  echo "remove it manually before continuing" >&2
  exit 1
fi

mkdir -p "${VENDOR_ROOT}"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/readaloud-kokoro-sdk.XXXXXX")"
trap 'rm -rf "${TMP_DIR}"' EXIT

git -C "${TMP_DIR}" init -q
git -C "${TMP_DIR}" remote add origin "${SDK_REPO}"
git -C "${TMP_DIR}" config core.sparseCheckout true

cat > "${TMP_DIR}/.git/info/sparse-checkout" <<'EOF'
/swift/
/swift-tts/
EOF

GIT_LFS_SKIP_SMUDGE=1 git -C "${TMP_DIR}" fetch -q --depth 1 origin "${SDK_COMMIT}"
git -C "${TMP_DIR}" checkout -q --detach FETCH_HEAD

ACTUAL_COMMIT="$(git -C "${TMP_DIR}" rev-parse HEAD)"
if [[ "${ACTUAL_COMMIT}" != "${SDK_COMMIT}" ]]; then
  echo "error: fetched Kokoro SDK commit does not match the pin" >&2
  exit 1
fi

mv "${TMP_DIR}" "${SDK_ROOT}"
trap - EXIT

echo "Kokoro SDK installed: ${SDK_REPO}@${SDK_COMMIT}"
