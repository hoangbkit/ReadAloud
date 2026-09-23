#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

bash "${SCRIPT_DIR}/download-kokoro-sdk.sh"
bash "${SCRIPT_DIR}/download-kokoro-assets.sh"

echo
echo "ReadAloud dependencies are ready."
echo "Next: xcodegen generate"
