#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=${HELPERS_DIR:-"$ROOT/.build/helpers"}
ARCHS=${ARCHS:-"arm64 x86_64"}
mkdir -p "$ROOT/.build" "$OUT"
WORK=$(mktemp -d "$ROOT/.build/helpers.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
build_helper() {
  local name=$1 arch
  shift
  local sources=()
  local source
  for source in "$@"; do sources+=("$ROOT/src/$source"); done
  local objects=()
  for arch in $ARCHS; do
    xcrun swiftc -O -target "$arch-apple-macosx13.0" "${sources[@]}" -o "$WORK/$name-$arch"
    objects+=("$WORK/$name-$arch")
  done
  if [ "${#objects[@]}" -eq 1 ]; then
    cp "${objects[0]}" "$WORK/$name"
  else
    xcrun lipo -create "${objects[@]}" -output "$WORK/$name"
  fi
  chmod 0755 "$WORK/$name"
  if [ -n "${SIGNING_IDENTITY:-}" ]; then
    /usr/bin/codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$WORK/$name"
  else
    /usr/bin/codesign --force --sign - "$WORK/$name"
  fi
  mv "$WORK/$name" "$OUT/$name"
}
build_helper lidwise-thermal ThermalState.swift
if [ -f "$ROOT/src/AgentScan.swift" ]; then build_helper lidwise-agent-scan-core ProcessRunner.swift AgentHooks.swift AgentScan.swift; fi
build_helper lidwise-lid-probe LidProbeModel.swift LidProbe.swift
