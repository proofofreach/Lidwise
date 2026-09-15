#!/bin/bash
# Hash release inputs, including new implementation files. Build products excluded.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
{
  printf '%s\n' VERSION README.md SECURITY.md CHANGELOG.md RELEASE_CHECKLIST.md LICENSE
  find bin lib src scripts tests docs assets -type f ! -name '.DS_Store'
} | LC_ALL=C sort | while IFS= read -r path; do /usr/bin/shasum -a 256 "$path"; done
