#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ASSET_ROOT="${REPO_ROOT}/Resources/Kokoro"
CHECKSUM_FILE="${SCRIPT_DIR}/kokoro-checksums.sha256"

source "${SCRIPT_DIR}/kokoro-pins.sh"

HF_REPO="${KOKORO_HF_REPO}"
HF_REVISION="${KOKORO_HF_METADATA_REVISION}"
UPSTREAM_MANIFEST_PATH="${KOKORO_FULL_RUNTIME_MANIFEST_PATH}"
HF_BASE_URL="https://huggingface.co/${HF_REPO}"

MODE="download"

usage() {
  cat <<'EOF'
Usage: scripts/download-kokoro-assets.sh [--verify-only]

Downloads the pinned Kokoro Core ML assets used by ReadAloud, verifies every
file with SHA-256, and installs verified files under Resources/Kokoro.

Options:
  --verify-only   Verify already-downloaded assets without replacing anything.
  -h, --help      Show this help.
EOF
}

case "${1:-}" in
  "")
    ;;
  --verify-only)
    MODE="verify"
    ;;
  -h|--help)
    usage
    exit 0
    ;;
  *)
    echo "error: unknown argument: $1" >&2
    usage >&2
    exit 2
    ;;
esac

for command in curl shasum mktemp python3 awk wc tr; do
  if ! command -v "${command}" >/dev/null 2>&1; then
    echo "error: required command not found: ${command}" >&2
    exit 1
  fi
done

if [[ ! -f "${CHECKSUM_FILE}" ]]; then
  echo "error: missing checksum file: ${CHECKSUM_FILE}" >&2
  exit 1
fi

EXPECTED_MANIFEST_SHA="$(
  awk -v path="${UPSTREAM_MANIFEST_PATH}" '$2 == path { print $1; exit }' "${CHECKSUM_FILE}"
)"

if [[ ! "${EXPECTED_MANIFEST_SHA}" =~ ^[0-9a-f]{64}$ ]]; then
  echo "error: no valid SHA-256 found for ${UPSTREAM_MANIFEST_PATH}" >&2
  exit 1
fi

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/readaloud-kokoro.XXXXXX")"
trap 'rm -rf "${TMP_DIR}"' EXIT

download_url() {
  local remote_path="$1"
  local output_path="$2"
  local url="${HF_BASE_URL}/resolve/${HF_REVISION}/${remote_path}?download=true"

  curl \
    --fail \
    --location \
    --silent \
    --show-error \
    --retry 3 \
    --retry-delay 1 \
    --output "${output_path}" \
    "${url}"
}

sha256_of() {
  shasum -a 256 "$1" | awk '{ print $1 }'
}

size_of() {
  wc -c < "$1" | tr -d '[:space:]'
}

verify_file() {
  local path="$1"
  local expected_sha="$2"
  local expected_bytes="$3"

  if [[ ! -f "${path}" ]]; then
    return 1
  fi

  local actual_sha
  local actual_bytes
  actual_sha="$(sha256_of "${path}")"
  actual_bytes="$(size_of "${path}")"

  [[ "${actual_sha}" == "${expected_sha}" && "${actual_bytes}" == "${expected_bytes}" ]]
}

UPSTREAM_MANIFEST="${TMP_DIR}/KokoroRuntimeManifest.json"
download_url "${UPSTREAM_MANIFEST_PATH}" "${UPSTREAM_MANIFEST}"

ACTUAL_MANIFEST_SHA="$(sha256_of "${UPSTREAM_MANIFEST}")"
if [[ "${ACTUAL_MANIFEST_SHA}" != "${EXPECTED_MANIFEST_SHA}" ]]; then
  echo "error: upstream manifest checksum mismatch" >&2
  echo "expected: ${EXPECTED_MANIFEST_SHA}" >&2
  echo "actual:   ${ACTUAL_MANIFEST_SHA}" >&2
  exit 1
fi

echo "Kokoro source: ${HF_REPO}@${HF_REVISION}"
echo "Verified upstream manifest: ${UPSTREAM_MANIFEST_PATH}"

ASSET_LIST="${TMP_DIR}/assets.tsv"

python3 - "${UPSTREAM_MANIFEST}" "${KOKORO_SDK_COMMIT}" > "${ASSET_LIST}" <<'PY'
import json
import sys

manifest_path, expected_sdk_commit = sys.argv[1:3]
with open(manifest_path, "r", encoding="utf-8") as handle:
    manifest = json.load(handle)

expected_buckets = [3, 7, 10, 15, 30]
expected_duration_sizes = [128]
selected_voices = ["af_heart", "af_bella", "am_michael"]

if manifest.get("bundle_profile") != "full":
    raise SystemExit("upstream runtime manifest is not the full profile")
if manifest.get("sdk_commit") != expected_sdk_commit:
    raise SystemExit(
        "upstream runtime manifest SDK commit does not match ReadAloud's pinned SDK"
    )
if manifest.get("buckets") != expected_buckets:
    raise SystemExit(f"unexpected Kokoro buckets: {manifest.get('buckets')!r}")
if manifest.get("duration_token_sizes") != expected_duration_sizes:
    raise SystemExit(
        f"unexpected duration token sizes: {manifest.get('duration_token_sizes')!r}"
    )

required_packages = ["coreml/kokoro_duration_t128.mlpackage"]
for bucket in expected_buckets:
    required_packages.extend(
        [
            f"coreml/kokoro_f0ntrain_t{bucket * 40}.mlpackage",
            f"coreml/kokoro_decoder_pre_{bucket}s.mlpackage",
            f"coreml/kokoro_decoder_har_post_{bucket}s.mlpackage",
        ]
    )

package_map = {entry["path"]: entry for entry in manifest.get("model_packages", [])}
for package_path in required_packages:
    package = package_map.get(package_path)
    if package is None:
        raise SystemExit(f"missing package in upstream manifest: {package_path}")

    files = package.get("files") or []
    if not files:
        raise SystemExit(f"package has no files in upstream manifest: {package_path}")

    for entry in files:
        local_path = f"{package_path}/{entry['path']}"
        remote_path = local_path
        print(
            f"{entry['sha256']}\t{entry['bytes']}\t"
            f"{local_path}\t{remote_path}"
        )

voice_map = {entry["path"]: entry for entry in manifest.get("voices", [])}
for voice in selected_voices:
    local_path = f"voices/{voice}.bin"
    entry = voice_map.get(local_path)
    if entry is None:
        raise SystemExit(f"missing voice in upstream manifest: {local_path}")

    remote_path = f"kokoro.js/voices/{voice}.bin"
    print(
        f"{entry['sha256']}\t{entry['bytes']}\t"
        f"{local_path}\t{remote_path}"
    )

runtime_assets = manifest.get("runtime_assets") or {}
for key in ("vocab", "hnsf_weights"):
    entry = runtime_assets.get(key)
    if not entry:
        raise SystemExit(f"missing runtime asset in upstream manifest: {key}")

    local_path = entry["path"]
    remote_path = local_path
    print(
        f"{entry['sha256']}\t{entry['bytes']}\t"
        f"{local_path}\t{remote_path}"
    )
PY

SUBSET_MANIFEST="${TMP_DIR}/ReadAloudKokoroRuntimeManifest.json"

python3 - "${UPSTREAM_MANIFEST}" "${SUBSET_MANIFEST}" "${EXPECTED_MANIFEST_SHA}" "${HF_REVISION}" <<'PY'
import json
import sys

source_path, output_path, source_manifest_sha, pinned_revision = sys.argv[1:5]

with open(source_path, "r", encoding="utf-8") as handle:
    manifest = json.load(handle)

expected_buckets = [3, 7, 10, 15, 30]
selected_voices = ["af_heart", "af_bella", "am_michael"]

required_packages = ["coreml/kokoro_duration_t128.mlpackage"]
for bucket in expected_buckets:
    required_packages.extend(
        [
            f"coreml/kokoro_f0ntrain_t{bucket * 40}.mlpackage",
            f"coreml/kokoro_decoder_pre_{bucket}s.mlpackage",
            f"coreml/kokoro_decoder_har_post_{bucket}s.mlpackage",
        ]
    )

package_map = {entry["path"]: entry for entry in manifest.get("model_packages", [])}
voice_map = {entry["path"]: entry for entry in manifest.get("voices", [])}

subset = dict(manifest)
subset["bundle_profile"] = "custom"
subset["buckets"] = expected_buckets
subset["duration_token_sizes"] = [128]
subset["model_packages"] = [package_map[path] for path in required_packages]
subset["voices"] = [
    voice_map[f"voices/{voice}.bin"]
    for voice in selected_voices
]
subset["readaloud_source_manifest_sha256"] = source_manifest_sha
subset["readaloud_hosted_revision"] = pinned_revision

with open(output_path, "w", encoding="utf-8") as handle:
    json.dump(subset, handle, indent=2, sort_keys=True)
    handle.write("\n")
PY

mkdir -p "${ASSET_ROOT}"

STAGE_ROOT="${TMP_DIR}/staged"
mkdir -p "${STAGE_ROOT}"
TAB="$(printf '\t')"

verified_count=0
downloaded_count=0

while IFS="${TAB}" read -r expected_sha expected_bytes local_path remote_path; do
  [[ -n "${local_path}" ]] || continue

  destination="${ASSET_ROOT}/${local_path}"

  if [[ -e "${destination}" ]]; then
    if verify_file "${destination}" "${expected_sha}" "${expected_bytes}"; then
      echo "verified: ${local_path}"
      verified_count=$((verified_count + 1))
      continue
    fi

    echo "error: existing asset does not match pinned checksum: ${local_path}" >&2
    echo "refusing to replace the mismatched file automatically" >&2
    exit 1
  fi

  if [[ "${MODE}" == "verify" ]]; then
    echo "error: missing asset: ${local_path}" >&2
    exit 1
  fi

  staged_file="${STAGE_ROOT}/${local_path}"
  mkdir -p "$(dirname "${staged_file}")"
  download_url "${remote_path}" "${staged_file}"

  if ! verify_file "${staged_file}" "${expected_sha}" "${expected_bytes}"; then
    echo "error: downloaded asset failed verification: ${local_path}" >&2
    exit 1
  fi

  echo "staged + verified: ${local_path}"
  downloaded_count=$((downloaded_count + 1))
  verified_count=$((verified_count + 1))
done < "${ASSET_LIST}"

MANIFEST_DESTINATION="${ASSET_ROOT}/KokoroRuntimeManifest.json"
GENERATED_MANIFEST_SHA="$(sha256_of "${SUBSET_MANIFEST}")"

if [[ -e "${MANIFEST_DESTINATION}" ]]; then
  EXISTING_MANIFEST_SHA="$(sha256_of "${MANIFEST_DESTINATION}")"
  if [[ "${EXISTING_MANIFEST_SHA}" != "${GENERATED_MANIFEST_SHA}" ]]; then
    echo "error: existing KokoroRuntimeManifest.json does not match the pinned asset set" >&2
    echo "refusing to replace the mismatched manifest automatically" >&2
    exit 1
  fi
  echo "verified: KokoroRuntimeManifest.json"
elif [[ "${MODE}" == "verify" ]]; then
  echo "error: missing asset: KokoroRuntimeManifest.json" >&2
  exit 1
fi

if [[ "${MODE}" == "download" ]]; then
  while IFS="${TAB}" read -r _ _ local_path _; do
    [[ -n "${local_path}" ]] || continue

    staged_file="${STAGE_ROOT}/${local_path}"
    [[ -f "${staged_file}" ]] || continue

    destination="${ASSET_ROOT}/${local_path}"
    mkdir -p "$(dirname "${destination}")"
    mv "${staged_file}" "${destination}"
    echo "installed: ${local_path}"
  done < "${ASSET_LIST}"

  if [[ ! -e "${MANIFEST_DESTINATION}" ]]; then
    mv "${SUBSET_MANIFEST}" "${MANIFEST_DESTINATION}"
    echo "installed: KokoroRuntimeManifest.json"
  fi
fi

echo
echo "Kokoro assets verified: ${verified_count}"
if [[ "${MODE}" == "download" ]]; then
  echo "New assets installed: ${downloaded_count}"
fi
