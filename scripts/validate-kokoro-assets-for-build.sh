#!/bin/bash
set -euo pipefail

ASSET_ROOT="${SRCROOT}/Resources/Kokoro"
MANIFEST="${ASSET_ROOT}/KokoroRuntimeManifest.json"

if [[ ! -f "${MANIFEST}" ]]; then
  echo "error: Kokoro assets are missing. Run: bash scripts/download-kokoro-assets.sh" >&2
  exit 1
fi

python3 - "${ASSET_ROOT}" "${MANIFEST}" <<'PY'
import json
import os
import sys

asset_root, manifest_path = sys.argv[1:3]

with open(manifest_path, "r", encoding="utf-8") as handle:
    manifest = json.load(handle)

expected_buckets = [3, 7, 10, 15, 30]
expected_voices = [
    "voices/af_heart.bin",
    "voices/af_bella.bin",
    "voices/am_michael.bin",
]

if manifest.get("bundle_profile") != "custom":
    raise SystemExit("error: unexpected Kokoro runtime manifest profile")
if manifest.get("hf_provenance_verified") is not True:
    raise SystemExit("error: Kokoro runtime manifest provenance is not verified")
if len(manifest.get("readaloud_source_manifest_sha256", "")) != 64:
    raise SystemExit("error: missing ReadAloud source manifest digest")
if manifest.get("buckets") != expected_buckets:
    raise SystemExit("error: Kokoro runtime manifest has unexpected bucket set")

voice_paths = [entry.get("path") for entry in manifest.get("voices", [])]
if voice_paths != expected_voices:
    raise SystemExit("error: Kokoro runtime manifest has unexpected voice set")

expected_packages = ["coreml/kokoro_duration_t128.mlpackage"]
for bucket in expected_buckets:
    expected_packages.extend(
        [
            f"coreml/kokoro_f0ntrain_t{bucket * 40}.mlpackage",
            f"coreml/kokoro_decoder_pre_{bucket}s.mlpackage",
            f"coreml/kokoro_decoder_har_post_{bucket}s.mlpackage",
        ]
    )

package_paths = [entry.get("path") for entry in manifest.get("model_packages", [])]
if package_paths != expected_packages:
    raise SystemExit("error: Kokoro runtime manifest has unexpected model package set")

def require_file(relative_path: str, expected_bytes: int) -> None:
    full_path = os.path.join(asset_root, relative_path)
    if not os.path.isfile(full_path):
        raise SystemExit(f"error: missing Kokoro asset: {relative_path}")
    actual_bytes = os.path.getsize(full_path)
    if actual_bytes != expected_bytes:
        raise SystemExit(
            f"error: Kokoro asset size mismatch: {relative_path} "
            f"(expected {expected_bytes}, got {actual_bytes})"
        )

for package in manifest.get("model_packages", []):
    package_path = package["path"]
    package_root = os.path.join(asset_root, package_path)
    if not os.path.isdir(package_root):
        raise SystemExit(f"error: missing Kokoro model package: {package_path}")
    for entry in package.get("files", []):
        require_file(
            f"{package_path}/{entry['path']}",
            int(entry["bytes"]),
        )

for entry in manifest.get("voices", []):
    require_file(entry["path"], int(entry["bytes"]))

runtime_assets = manifest.get("runtime_assets", {})
for key in ("vocab", "hnsf_weights"):
    entry = runtime_assets.get(key)
    if not entry:
        raise SystemExit(f"error: missing runtime asset declaration: {key}")
    require_file(entry["path"], int(entry["bytes"]))

print("Kokoro bundled assets present")
PY
